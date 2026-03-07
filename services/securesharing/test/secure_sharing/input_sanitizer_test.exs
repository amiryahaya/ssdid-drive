defmodule SecureSharing.InputSanitizerTest do
  @moduledoc """
  Tests for InputSanitizer module.

  Covers XSS prevention, null byte removal, UUID validation, and display name sanitization.
  """

  use ExUnit.Case, async: true

  alias SecureSharing.InputSanitizer

  describe "sanitize_string/1" do
    test "returns nil for nil input" do
      assert InputSanitizer.sanitize_string(nil) == nil
    end

    test "returns non-binary values unchanged" do
      assert InputSanitizer.sanitize_string(123) == 123
      assert InputSanitizer.sanitize_string(%{key: "value"}) == %{key: "value"}
    end

    test "removes null bytes" do
      assert InputSanitizer.sanitize_string("hello\x00world") == "helloworld"
      assert InputSanitizer.sanitize_string("\x00start") == "start"
      assert InputSanitizer.sanitize_string("end\x00") == "end"
    end

    test "strips script tags" do
      assert InputSanitizer.sanitize_string("<script>alert('xss')</script>Hello") == "Hello"
      assert InputSanitizer.sanitize_string("<SCRIPT>alert('xss')</SCRIPT>text") == "text"

      assert InputSanitizer.sanitize_string("<script type='text/javascript'>code</script>safe") ==
               "safe"
    end

    test "strips style tags" do
      assert InputSanitizer.sanitize_string("<style>.evil{}</style>content") == "content"

      assert InputSanitizer.sanitize_string("<STYLE>body{display:none}</STYLE>visible") ==
               "visible"
    end

    test "strips all HTML tags" do
      assert InputSanitizer.sanitize_string("<b>bold</b>") == "bold"
      assert InputSanitizer.sanitize_string("<a href='http://evil.com'>click</a>") == "click"
      assert InputSanitizer.sanitize_string("<img src='x' onerror='alert(1)'>") == ""
      assert InputSanitizer.sanitize_string("<div class='test'>content</div>") == "content"
    end

    test "removes javascript: URLs" do
      assert InputSanitizer.sanitize_string("javascript:alert('xss')") == "alert('xss')"
      assert InputSanitizer.sanitize_string("JAVASCRIPT:alert(1)") == "alert(1)"
      assert InputSanitizer.sanitize_string("javascript :alert(1)") == "alert(1)"
    end

    test "removes data: URLs" do
      # data: is removed, then script tags are stripped
      assert InputSanitizer.sanitize_string("data:text/html,<script>alert(1)</script>") ==
               "text/html,"

      assert InputSanitizer.sanitize_string("DATA:image/svg+xml,evil") == "image/svg+xml,evil"
    end

    test "removes vbscript: URLs" do
      assert InputSanitizer.sanitize_string("vbscript:msgbox('xss')") == "msgbox('xss')"
    end

    test "removes event handlers" do
      assert InputSanitizer.sanitize_string("onclick=alert(1)") == "alert(1)"
      assert InputSanitizer.sanitize_string("onmouseover=evil()") == "evil()"
      assert InputSanitizer.sanitize_string("ONERROR=hack()") == "hack()"
    end

    test "trims whitespace" do
      assert InputSanitizer.sanitize_string("  hello  ") == "hello"
      assert InputSanitizer.sanitize_string("\tworld\n") == "world"
    end

    test "handles complex XSS payloads" do
      # Nested tags - the regex captures the outer script tag content
      assert InputSanitizer.sanitize_string("<scr<script>ipt>alert(1)</scr</script>ipt>") == ""

      # Mixed case - content inside script tags is also removed
      assert InputSanitizer.sanitize_string("<ScRiPt>evil</sCrIpT>") == ""

      # Multiple vectors
      payload = "<script>x</script><style>y</style>javascript:z"
      assert InputSanitizer.sanitize_string(payload) == "z"
    end

    test "preserves safe content" do
      assert InputSanitizer.sanitize_string("Hello, World!") == "Hello, World!"
      assert InputSanitizer.sanitize_string("user@example.com") == "user@example.com"
      assert InputSanitizer.sanitize_string("John Doe") == "John Doe"
      assert InputSanitizer.sanitize_string("123-456-7890") == "123-456-7890"
    end
  end

  describe "sanitize_display_name/1" do
    test "returns nil for nil input" do
      assert InputSanitizer.sanitize_display_name(nil) == nil
    end

    test "returns non-binary values unchanged" do
      assert InputSanitizer.sanitize_display_name(42) == 42
    end

    test "normalizes whitespace" do
      assert InputSanitizer.sanitize_display_name("John    Doe") == "John Doe"
      assert InputSanitizer.sanitize_display_name("  Alice   Bob  ") == "Alice Bob"
      assert InputSanitizer.sanitize_display_name("Tab\tSeparated") == "Tab Separated"
      assert InputSanitizer.sanitize_display_name("New\nLine") == "New Line"
    end

    test "applies all string sanitization rules" do
      assert InputSanitizer.sanitize_display_name("<script>x</script>John") == "John"
      # Null byte is simply removed, no space added
      assert InputSanitizer.sanitize_display_name("Jane\x00Doe") == "JaneDoe"
    end

    test "handles typical display names" do
      assert InputSanitizer.sanitize_display_name("John Doe") == "John Doe"
      assert InputSanitizer.sanitize_display_name("María García") == "María García"
      assert InputSanitizer.sanitize_display_name("李明") == "李明"
    end
  end

  describe "validate_uuid/1" do
    test "returns error for nil" do
      assert InputSanitizer.validate_uuid(nil) == {:error, :invalid_uuid}
    end

    test "returns error for non-binary values" do
      assert InputSanitizer.validate_uuid(123) == {:error, :invalid_uuid}
      assert InputSanitizer.validate_uuid(%{}) == {:error, :invalid_uuid}
      assert InputSanitizer.validate_uuid([]) == {:error, :invalid_uuid}
    end

    test "validates correct UUID format" do
      uuid = "550e8400-e29b-41d4-a716-446655440000"
      assert {:ok, ^uuid} = InputSanitizer.validate_uuid(uuid)
    end

    test "normalizes UUID to lowercase" do
      uuid = "550E8400-E29B-41D4-A716-446655440000"
      assert {:ok, "550e8400-e29b-41d4-a716-446655440000"} = InputSanitizer.validate_uuid(uuid)
    end

    test "accepts various valid UUIDs" do
      # UUID v4
      assert {:ok, _} = InputSanitizer.validate_uuid("f47ac10b-58cc-4372-a567-0e02b2c3d479")
      # UUID v1
      assert {:ok, _} = InputSanitizer.validate_uuid("6ba7b810-9dad-11d1-80b4-00c04fd430c8")
      # UUID v7
      assert {:ok, _} = InputSanitizer.validate_uuid("019064da-7ba3-7c13-8e74-7be0a3e8d73b")
    end

    test "rejects invalid UUID formats" do
      assert {:error, :invalid_uuid} = InputSanitizer.validate_uuid("not-a-uuid")
      assert {:error, :invalid_uuid} = InputSanitizer.validate_uuid("550e8400-e29b-41d4-a716")

      assert {:error, :invalid_uuid} =
               InputSanitizer.validate_uuid("550e8400e29b41d4a716446655440000")

      assert {:error, :invalid_uuid} =
               InputSanitizer.validate_uuid("550e8400-e29b-41d4-a716-44665544000g")
    end

    test "rejects SQL injection attempts" do
      assert {:error, :invalid_uuid} = InputSanitizer.validate_uuid("'; DROP TABLE users;--")
      assert {:error, :invalid_uuid} = InputSanitizer.validate_uuid("1' OR '1'='1")

      assert {:error, :invalid_uuid} =
               InputSanitizer.validate_uuid("550e8400-e29b-41d4-a716-446655440000'; --")
    end

    test "rejects empty string" do
      assert {:error, :invalid_uuid} = InputSanitizer.validate_uuid("")
    end

    test "rejects UUID with extra characters" do
      assert {:error, :invalid_uuid} =
               InputSanitizer.validate_uuid(" 550e8400-e29b-41d4-a716-446655440000")

      assert {:error, :invalid_uuid} =
               InputSanitizer.validate_uuid("550e8400-e29b-41d4-a716-446655440000 ")

      assert {:error, :invalid_uuid} =
               InputSanitizer.validate_uuid("{550e8400-e29b-41d4-a716-446655440000}")
    end
  end

  describe "valid_uuid?/1" do
    test "returns true for valid UUIDs" do
      assert InputSanitizer.valid_uuid?("550e8400-e29b-41d4-a716-446655440000") == true
      assert InputSanitizer.valid_uuid?("F47AC10B-58CC-4372-A567-0E02B2C3D479") == true
    end

    test "returns false for invalid UUIDs" do
      assert InputSanitizer.valid_uuid?(nil) == false
      assert InputSanitizer.valid_uuid?("invalid") == false
      assert InputSanitizer.valid_uuid?(123) == false
    end
  end
end
