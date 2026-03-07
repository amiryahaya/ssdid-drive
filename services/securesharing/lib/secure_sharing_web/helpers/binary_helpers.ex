defmodule SecureSharingWeb.Helpers.BinaryHelpers do
  @moduledoc """
  Helper functions for safely handling binary data in API requests.

  Provides strict Base64 decoding that rejects invalid input instead
  of silently falling back to the original data.

  ## Security

  Previous implementations used a fallback pattern that returned the original
  data on decode failure:

      case Base.decode64(data) do
        {:ok, decoded} -> decoded
        :error -> data  # DANGEROUS: silently accepts invalid input
      end

  This is a security issue because:
  1. Invalid crypto material could be stored
  2. Signature verification could be bypassed
  3. Key material integrity cannot be guaranteed

  This module provides safe alternatives that either:
  - Return `{:ok, decoded}` or `{:error, :invalid_base64}`
  - Return `nil` for optional fields (only when appropriate)
  """

  @doc """
  Safely decode a Base64 string, returning {:ok, decoded} or {:error, :invalid_base64}.

  Use this when the field is required and must be valid Base64.

  ## Examples

      iex> decode_base64("SGVsbG8=")
      {:ok, "Hello"}

      iex> decode_base64("not valid base64!!!")
      {:error, :invalid_base64}

      iex> decode_base64(nil)
      {:ok, nil}
  """
  @spec decode_base64(String.t() | nil) :: {:ok, binary() | nil} | {:error, :invalid_base64}
  def decode_base64(nil), do: {:ok, nil}

  def decode_base64(data) when is_binary(data) do
    case Base.decode64(data) do
      {:ok, decoded} -> {:ok, decoded}
      :error -> {:error, :invalid_base64}
    end
  end

  def decode_base64(_), do: {:error, :invalid_base64}

  @doc """
  Decode a Base64 string, returning nil on failure.

  Use this ONLY for optional fields where nil is an acceptable value
  and the absence of data is not a security concern.

  ## Examples

      iex> decode_base64_optional("SGVsbG8=")
      "Hello"

      iex> decode_base64_optional("not valid")
      nil

      iex> decode_base64_optional(nil)
      nil
  """
  @spec decode_base64_optional(String.t() | nil) :: binary() | nil
  def decode_base64_optional(nil), do: nil

  def decode_base64_optional(data) when is_binary(data) do
    case Base.decode64(data) do
      {:ok, decoded} -> decoded
      :error -> nil
    end
  end

  def decode_base64_optional(_), do: nil

  @doc """
  Decode multiple Base64 fields from a map, returning {:ok, decoded_map} or {:error, {:invalid_base64, field}}.

  Useful for decoding request parameters with multiple binary fields.

  ## Parameters
  - params: Map of parameters
  - fields: List of field names to decode

  ## Examples

      iex> decode_fields(%{"key" => "SGVsbG8=", "data" => "V29ybGQ="}, [:key, :data])
      {:ok, %{key: "Hello", data: "World"}}

      iex> decode_fields(%{"key" => "invalid!!!"}, [:key])
      {:error, {:invalid_base64, :key}}
  """
  @spec decode_fields(map(), [atom()]) :: {:ok, map()} | {:error, {:invalid_base64, atom()}}
  def decode_fields(params, fields) when is_map(params) and is_list(fields) do
    Enum.reduce_while(fields, {:ok, %{}}, fn field, {:ok, acc} ->
      string_field = to_string(field)
      value = params[string_field] || params[field]

      case decode_base64(value) do
        {:ok, decoded} ->
          {:cont, {:ok, Map.put(acc, field, decoded)}}

        {:error, :invalid_base64} ->
          {:halt, {:error, {:invalid_base64, field}}}
      end
    end)
  end

  @doc """
  Decode optional Base64 fields from a map, returning a map with decoded values.

  Fields that fail to decode are set to nil. Use this only for truly optional fields.

  ## Examples

      iex> decode_optional_fields(%{"key" => "SGVsbG8=", "bad" => "!!!"}, [:key, :bad])
      %{key: "Hello", bad: nil}
  """
  @spec decode_optional_fields(map(), [atom()]) :: map()
  def decode_optional_fields(params, fields) when is_map(params) and is_list(fields) do
    Enum.reduce(fields, %{}, fn field, acc ->
      string_field = to_string(field)
      value = params[string_field] || params[field]
      Map.put(acc, field, decode_base64_optional(value))
    end)
  end
end
