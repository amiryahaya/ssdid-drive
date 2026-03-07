defmodule SecureSharingWeb.Admin.TenantLive.Index do
  @moduledoc """
  LiveView for listing and managing tenants.
  """
  use SecureSharingWeb, :live_view

  alias SecureSharing.Accounts
  alias SecureSharing.Accounts.Tenant

  @impl true
  def mount(_params, _session, socket) do
    {:ok, stream(socket, :tenants, Accounts.list_tenants())}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    tenant = Accounts.get_tenant(id)

    socket
    |> assign(:page_title, "Edit Tenant")
    |> assign(:tenant, tenant)
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New Tenant")
    |> assign(:tenant, %Tenant{})
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Tenants")
    |> assign(:tenant, nil)
  end

  @impl true
  def handle_info({SecureSharingWeb.Admin.TenantLive.FormComponent, {:saved, tenant}}, socket) do
    {:noreply, stream_insert(socket, :tenants, tenant, at: 0)}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    tenant = Accounts.get_tenant(id)
    {:ok, _} = Accounts.delete_tenant(tenant)

    {:noreply, stream_delete(socket, :tenants, tenant)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.header>
      Tenants
      <:actions>
        <.link patch={~p"/admin/tenants/new"}>
          <.button>New Tenant</.button>
        </.link>
      </:actions>
    </.header>

    <.table
      id="tenants"
      rows={@streams.tenants}
      row_click={fn {_id, tenant} -> JS.navigate(~p"/admin/tenants/#{tenant}") end}
    >
      <:col :let={{_id, tenant}} label="Name">{tenant.name}</:col>
      <:col :let={{_id, tenant}} label="Slug">{tenant.slug}</:col>
      <:col :let={{_id, tenant}} label="Storage Quota">
        {format_bytes(tenant.storage_quota_bytes)}
      </:col>
      <:col :let={{_id, tenant}} label="Max Users">{tenant.max_users}</:col>
      <:col :let={{_id, tenant}} label="Created">
        {Calendar.strftime(tenant.created_at, "%b %d, %Y")}
      </:col>
      <:action :let={{_id, tenant}}>
        <div class="sr-only">
          <.link navigate={~p"/admin/tenants/#{tenant}"}>Show</.link>
        </div>
        <.link patch={~p"/admin/tenants/#{tenant}/edit"}>Edit</.link>
      </:action>
      <:action :let={{id, tenant}}>
        <.link
          phx-click={JS.push("delete", value: %{id: tenant.id}) |> hide("##{id}")}
          data-confirm="Are you sure you want to delete this tenant?"
        >
          Delete
        </.link>
      </:action>
    </.table>

    <.modal :if={@live_action in [:new, :edit]} id="tenant-modal" show on_cancel={JS.patch(~p"/admin/tenants")}>
      <.live_component
        module={SecureSharingWeb.Admin.TenantLive.FormComponent}
        id={@tenant.id || :new}
        title={@page_title}
        action={@live_action}
        tenant={@tenant}
        patch={~p"/admin/tenants"}
      />
    </.modal>
    """
  end

  defp format_bytes(bytes) when is_integer(bytes) do
    cond do
      bytes >= 1_099_511_627_776 ->
        "#{Float.round(bytes / 1_099_511_627_776, 2)} TB"

      bytes >= 1_073_741_824 ->
        "#{Float.round(bytes / 1_073_741_824, 2)} GB"

      bytes >= 1_048_576 ->
        "#{Float.round(bytes / 1_048_576, 2)} MB"

      bytes >= 1024 ->
        "#{Float.round(bytes / 1024, 2)} KB"

      true ->
        "#{bytes} B"
    end
  end

  defp format_bytes(_), do: "N/A"
end
