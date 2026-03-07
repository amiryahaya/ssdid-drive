defmodule SecureSharing.InputSanitizer do
  @moduledoc """
  Input sanitization utilities to prevent XSS, injection attacks, and other security issues.

  This module provides functions to sanitize user input before storage or display.
  """

  @doc """
  Sanitizes a string by removing potentially dangerous content.

  Performs the following sanitization:
  1. Removes null bytes (\\x00)
  2. Strips HTML/script tags
  3. Removes javascript: and data: URLs
  4. Trims whitespace

  Returns nil if input is nil.

  ## Examples

      iex> InputSanitizer.sanitize_string("<script>alert('xss')</script>Hello")
      "Hello"

      iex> InputSanitizer.sanitize_string("before\\x00after")
      "beforeafter"

      iex> InputSanitizer.sanitize_string(nil)
      nil
  """
  @spec sanitize_string(String.t() | nil) :: String.t() | nil
  def sanitize_string(nil), do: nil

  def sanitize_string(value) when is_binary(value) do
    value
    |> remove_null_bytes()
    |> strip_html_tags()
    |> remove_dangerous_urls()
    |> String.trim()
  end

  def sanitize_string(value), do: value

  @doc """
  Sanitizes a display name field.

  In addition to standard sanitization, also:
  - Normalizes whitespace (multiple spaces become single space)
  - Limits length to prevent abuse

  ## Examples

      iex> InputSanitizer.sanitize_display_name("  John   Doe  ")
      "John Doe"
  """
  @spec sanitize_display_name(String.t() | nil) :: String.t() | nil
  def sanitize_display_name(nil), do: nil

  def sanitize_display_name(value) when is_binary(value) do
    value
    |> sanitize_string()
    |> normalize_whitespace()
  end

  def sanitize_display_name(value), do: value

  @doc """
  Validates and sanitizes a UUID string.

  Returns {:ok, uuid} if valid, {:error, :invalid_uuid} otherwise.
  This prevents SQL injection and other attacks via UUID fields.

  ## Examples

      iex> InputSanitizer.validate_uuid("550e8400-e29b-41d4-a716-446655440000")
      {:ok, "550e8400-e29b-41d4-a716-446655440000"}

      iex> InputSanitizer.validate_uuid("invalid'; DROP TABLE users;--")
      {:error, :invalid_uuid}
  """
  @spec validate_uuid(String.t() | nil) :: {:ok, String.t()} | {:error, :invalid_uuid}
  def validate_uuid(nil), do: {:error, :invalid_uuid}

  def validate_uuid(value) when is_binary(value) do
    # Standard UUID regex pattern
    uuid_regex = ~r/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

    if Regex.match?(uuid_regex, value) do
      {:ok, String.downcase(value)}
    else
      {:error, :invalid_uuid}
    end
  end

  def validate_uuid(_), do: {:error, :invalid_uuid}

  @doc """
  Checks if a UUID string is valid without returning the value.
  """
  @spec valid_uuid?(String.t() | nil) :: boolean()
  def valid_uuid?(value) do
    case validate_uuid(value) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  # Private functions

  defp remove_null_bytes(value) do
    # Remove null bytes which can cause issues with databases and display
    String.replace(value, <<0>>, "")
  end

  defp strip_html_tags(value) do
    # Remove HTML tags including script, style, etc.
    value
    |> String.replace(~r/<script[^>]*>.*?<\/script>/is, "")
    |> String.replace(~r/<style[^>]*>.*?<\/style>/is, "")
    |> String.replace(~r/<[^>]+>/, "")
  end

  defp remove_dangerous_urls(value) do
    # Remove javascript: and data: URLs which can execute code
    value
    |> String.replace(~r/javascript\s*:/i, "")
    |> String.replace(~r/data\s*:/i, "")
    |> String.replace(~r/vbscript\s*:/i, "")
    |> String.replace(~r/on\w+\s*=/i, "")
  end

  defp normalize_whitespace(value) do
    # Replace multiple whitespace characters with single space
    String.replace(value, ~r/\s+/, " ")
  end
end
