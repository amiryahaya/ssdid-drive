defmodule SecureSharingWeb.Helpers.BinaryHelpersTest do
  use ExUnit.Case, async: true

  alias SecureSharingWeb.Helpers.BinaryHelpers

  describe "decode_base64/1" do
    test "decodes valid Base64 string" do
      assert {:ok, "Hello"} = BinaryHelpers.decode_base64("SGVsbG8=")
    end

    test "decodes empty Base64 string" do
      assert {:ok, ""} = BinaryHelpers.decode_base64("")
    end

    test "returns nil for nil input" do
      assert {:ok, nil} = BinaryHelpers.decode_base64(nil)
    end

    test "returns error for invalid Base64" do
      assert {:error, :invalid_base64} = BinaryHelpers.decode_base64("not valid!!!")
    end

    test "returns error for invalid characters" do
      assert {:error, :invalid_base64} = BinaryHelpers.decode_base64("SGVs!!!bG8=")
    end

    test "returns error for non-string input" do
      assert {:error, :invalid_base64} = BinaryHelpers.decode_base64(12345)
      assert {:error, :invalid_base64} = BinaryHelpers.decode_base64(%{})
      assert {:error, :invalid_base64} = BinaryHelpers.decode_base64([:list])
    end

    test "decodes binary data correctly" do
      original = :crypto.strong_rand_bytes(32)
      encoded = Base.encode64(original)
      assert {:ok, ^original} = BinaryHelpers.decode_base64(encoded)
    end

    test "rejects truncated Base64 (potential attack vector)" do
      # Base64 should have proper padding
      # Missing =
      assert {:error, :invalid_base64} = BinaryHelpers.decode_base64("SGVsbG8")
    end
  end

  describe "decode_base64_optional/1" do
    test "decodes valid Base64 string" do
      assert "Hello" = BinaryHelpers.decode_base64_optional("SGVsbG8=")
    end

    test "returns nil for nil input" do
      assert nil == BinaryHelpers.decode_base64_optional(nil)
    end

    test "returns nil for invalid Base64" do
      assert nil == BinaryHelpers.decode_base64_optional("not valid!!!")
    end

    test "returns nil for non-string input" do
      assert nil == BinaryHelpers.decode_base64_optional(12345)
    end
  end

  describe "decode_fields/2" do
    test "decodes multiple fields successfully" do
      params = %{
        "key" => Base.encode64("secret_key"),
        "data" => Base.encode64("my_data")
      }

      assert {:ok, decoded} = BinaryHelpers.decode_fields(params, [:key, :data])
      assert decoded.key == "secret_key"
      assert decoded.data == "my_data"
    end

    test "returns error with field name on invalid Base64" do
      params = %{
        "key" => Base.encode64("valid"),
        "bad" => "not valid base64!!!"
      }

      assert {:error, {:invalid_base64, :bad}} = BinaryHelpers.decode_fields(params, [:key, :bad])
    end

    test "handles nil values as valid" do
      params = %{
        "key" => Base.encode64("value"),
        "optional" => nil
      }

      assert {:ok, decoded} = BinaryHelpers.decode_fields(params, [:key, :optional])
      assert decoded.key == "value"
      assert decoded.optional == nil
    end

    test "handles missing fields as nil" do
      params = %{"key" => Base.encode64("value")}

      assert {:ok, decoded} = BinaryHelpers.decode_fields(params, [:key, :missing])
      assert decoded.key == "value"
      assert decoded.missing == nil
    end

    test "works with atom keys in params" do
      params = %{
        key: Base.encode64("from_atom"),
        data: Base.encode64("more_data")
      }

      assert {:ok, decoded} = BinaryHelpers.decode_fields(params, [:key, :data])
      assert decoded.key == "from_atom"
      assert decoded.data == "more_data"
    end

    test "fails fast on first invalid field" do
      params = %{
        "first" => "invalid!!!",
        "second" => "also invalid!!!"
      }

      # Should fail on :first, not :second
      assert {:error, {:invalid_base64, :first}} =
               BinaryHelpers.decode_fields(params, [:first, :second])
    end

    test "decodes crypto material correctly" do
      key_material = :crypto.strong_rand_bytes(32)
      ciphertext = :crypto.strong_rand_bytes(128)

      params = %{
        "wrapped_key" => Base.encode64(key_material),
        "ciphertext" => Base.encode64(ciphertext)
      }

      assert {:ok, decoded} = BinaryHelpers.decode_fields(params, [:wrapped_key, :ciphertext])
      assert decoded.wrapped_key == key_material
      assert decoded.ciphertext == ciphertext
    end
  end

  describe "decode_optional_fields/2" do
    test "decodes valid fields" do
      params = %{
        "key" => Base.encode64("value"),
        "data" => Base.encode64("data")
      }

      decoded = BinaryHelpers.decode_optional_fields(params, [:key, :data])
      assert decoded.key == "value"
      assert decoded.data == "data"
    end

    test "sets invalid fields to nil" do
      params = %{
        "good" => Base.encode64("valid"),
        "bad" => "not valid!!!"
      }

      decoded = BinaryHelpers.decode_optional_fields(params, [:good, :bad])
      assert decoded.good == "valid"
      assert decoded.bad == nil
    end

    test "handles missing fields as nil" do
      params = %{"present" => Base.encode64("here")}

      decoded = BinaryHelpers.decode_optional_fields(params, [:present, :absent])
      assert decoded.present == "here"
      assert decoded.absent == nil
    end
  end

  describe "security: rejects invalid input" do
    test "does not silently accept raw binary as Base64" do
      # This is the dangerous pattern we're protecting against
      raw_data = <<1, 2, 3, 4, 5>>

      # Should fail, not return the raw data
      assert {:error, :invalid_base64} = BinaryHelpers.decode_base64(raw_data)
    end

    test "properly validates before accepting crypto material" do
      # Simulate malformed request trying to bypass validation
      params = %{
        "signature" => "this is not valid base64!!!",
        # Raw binary, not Base64
        "wrapped_key" => <<0xFF, 0xFE>>
      }

      # Both should be rejected
      assert {:error, {:invalid_base64, :signature}} =
               BinaryHelpers.decode_fields(params, [:signature, :wrapped_key])
    end
  end
end
