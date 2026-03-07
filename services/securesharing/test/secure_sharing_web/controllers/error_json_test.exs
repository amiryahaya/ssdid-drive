defmodule SecureSharingWeb.ErrorJSONTest do
  use SecureSharingWeb.ConnCase, async: true

  test "renders 404" do
    assert SecureSharingWeb.ErrorJSON.render("404.json", %{}) ==
             %{error: %{code: "not_found", message: "Resource not found"}}
  end

  test "renders 500" do
    assert SecureSharingWeb.ErrorJSON.render("500.json", %{}) ==
             %{error: %{code: "internal_error", message: "An unexpected error occurred"}}
  end
end
