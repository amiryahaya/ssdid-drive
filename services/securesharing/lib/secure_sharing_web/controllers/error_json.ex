defmodule SecureSharingWeb.ErrorJSON do
  @moduledoc """
  Standardized JSON error responses for the API.

  Error format:
  ```json
  {
    "error": {
      "code": "error_code",
      "message": "Human readable message",
      "details": {}  // Optional, for validation errors
    }
  }
  ```
  """

  def render("400.json", assigns) do
    %{
      error: %{
        code: "bad_request",
        message: assigns[:message] || "Bad request"
      }
    }
  end

  def render("401.json", assigns) do
    %{
      error: %{
        code: "unauthorized",
        message: assigns[:message] || "Authentication required"
      }
    }
  end

  def render("402.json", assigns) do
    %{
      error: %{
        code: "payment_required",
        message: assigns[:message] || "Payment required"
      }
    }
  end

  def render("403.json", assigns) do
    %{
      error: %{
        code: "forbidden",
        message: assigns[:message] || "Access denied"
      }
    }
  end

  def render("404.json", assigns) do
    %{
      error: %{
        code: "not_found",
        message: assigns[:message] || "Resource not found"
      }
    }
  end

  def render("409.json", assigns) do
    %{
      error: %{
        code: "conflict",
        message: assigns[:message] || "Resource already exists"
      }
    }
  end

  def render("410.json", assigns) do
    %{
      error: %{
        code: "gone",
        message: assigns[:message] || "Resource is no longer available"
      }
    }
  end

  def render("412.json", assigns) do
    %{
      error: %{
        code: "precondition_failed",
        message: assigns[:message] || "Precondition failed"
      }
    }
  end

  def render("422.json", %{changeset: changeset}) do
    %{
      error: %{
        code: "validation_error",
        message: "Validation failed",
        details: format_changeset_errors(changeset)
      }
    }
  end

  def render("422.json", assigns) do
    %{
      error: %{
        code: "unprocessable_entity",
        message: assigns[:message] || "Unable to process request"
      }
    }
  end

  def render("429.json", _assigns) do
    %{
      error: %{
        code: "rate_limited",
        message: "Too many requests. Please try again later."
      }
    }
  end

  def render("500.json", _assigns) do
    %{
      error: %{
        code: "internal_error",
        message: "An unexpected error occurred"
      }
    }
  end

  # Default handler for any other status codes
  def render(template, _assigns) do
    status_message = Phoenix.Controller.status_message_from_template(template)
    code = template |> String.replace(".json", "") |> String.downcase()

    %{
      error: %{
        code: code,
        message: status_message
      }
    }
  end

  # Format Ecto changeset errors into a map
  defp format_changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts
        |> Keyword.get(String.to_existing_atom(key), key)
        |> to_string()
      end)
    end)
  end
end
