defmodule SecureSharingWeb.API.SsdidAuthJSON do
  @moduledoc """
  JSON rendering for SSDID authentication responses.
  """

  @doc """
  Render registration challenge response.
  """
  def render("register.json", %{result: result}) do
    %{
      challenge: result["challenge"],
      server_did: result["server_did"] || result["did"],
      server_key_id: result["server_key_id"] || result["key_id"],
      server_signature: result["server_signature"]
    }
  end

  @doc """
  Render registration verification response.
  """
  def render("verify.json", %{result: result}) do
    %{
      credential: result["credential"],
      did: result["did"]
    }
  end

  @doc """
  Render authentication response with user and tenant info.
  """
  def render("authenticate.json", %{result: result, user: user, tenants: tenants}) do
    %{
      session_token: result["session_token"],
      did: result["did"],
      server_did: result["server_did"],
      server_signature: result["server_signature"],
      user: render_user(user),
      tenants: Enum.map(tenants, &render_tenant/1)
    }
  end

  @doc """
  Render tenant switch response.
  """
  def render("tenant_switch.json", %{tenant: tenant, role: role}) do
    %{
      tenant: %{
        id: tenant.id,
        name: tenant.name,
        slug: tenant.slug
      },
      role: to_string(role)
    }
  end

  defp render_user(user) do
    %{
      id: user.id,
      did: user.did,
      display_name: user.display_name,
      status: user.status
    }
  end

  defp render_tenant(tenant) do
    %{
      id: tenant.id,
      name: tenant.name,
      slug: tenant.slug,
      role: to_string(tenant.role)
    }
  end
end
