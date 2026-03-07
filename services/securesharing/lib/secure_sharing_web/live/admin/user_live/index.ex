defmodule SecureSharingWeb.Admin.UserLive.Index do
  @moduledoc """
  LiveView for listing and managing users across all tenants.
  """
  use SecureSharingWeb, :live_view

  alias SecureSharing.Accounts

  @impl true
  def mount(_params, _session, socket) do
    {:ok, stream(socket, :users, Accounts.list_all_users())}
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, assign(socket, page_title: "Users")}
  end

  @impl true
  def handle_event("suspend", %{"id" => id}, socket) do
    user = Accounts.get_user!(id)
    {:ok, updated_user} = Accounts.update_user_status(user, :suspended)
    {:noreply, stream_insert(socket, :users, SecureSharing.Repo.preload(updated_user, :tenant))}
  end

  @impl true
  def handle_event("activate", %{"id" => id}, socket) do
    user = Accounts.get_user!(id)
    {:ok, updated_user} = Accounts.update_user_status(user, :active)
    {:noreply, stream_insert(socket, :users, SecureSharing.Repo.preload(updated_user, :tenant))}
  end

  @impl true
  def handle_event("toggle_admin", %{"id" => id}, socket) do
    user = Accounts.get_user!(id)
    {:ok, updated_user} = Accounts.set_admin(user, not user.is_admin)
    {:noreply, stream_insert(socket, :users, SecureSharing.Repo.preload(updated_user, :tenant))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.header>
      Users
      <:subtitle>Manage users across all tenants</:subtitle>
    </.header>

    <.table
      id="users"
      rows={@streams.users}
      row_click={fn {_id, user} -> JS.navigate(~p"/admin/users/#{user}") end}
    >
      <:col :let={{_id, user}} label="Email">{user.email}</:col>
      <:col :let={{_id, user}} label="Tenant">
        <.link :if={user.tenant_id} navigate={~p"/admin/tenants/#{user.tenant_id}"} class="text-blue-600 hover:text-blue-500">
          {user.tenant && user.tenant.name}
        </.link>
        <span :if={!user.tenant_id} class="text-gray-400">No tenant</span>
      </:col>
      <:col :let={{_id, user}} label="Status">
        <.badge color={status_color(user.status)}>{user.status}</.badge>
      </:col>
      <:col :let={{_id, user}} label="Admin">
        <.badge :if={user.is_admin} color={:blue}>Admin</.badge>
      </:col>
      <:col :let={{_id, user}} label="Created">
        {Calendar.strftime(user.created_at, "%b %d, %Y")}
      </:col>
      <:action :let={{_id, user}}>
        <div class="sr-only">
          <.link navigate={~p"/admin/users/#{user}"}>Show</.link>
        </div>
        <.link :if={user.status == :active} phx-click={JS.push("suspend", value: %{id: user.id})} class="text-red-600 hover:text-red-500">
          Suspend
        </.link>
        <.link :if={user.status == :suspended} phx-click={JS.push("activate", value: %{id: user.id})} class="text-green-600 hover:text-green-500">
          Activate
        </.link>
      </:action>
      <:action :let={{_id, user}}>
        <.link phx-click={JS.push("toggle_admin", value: %{id: user.id})}>
          {if user.is_admin, do: "Remove Admin", else: "Make Admin"}
        </.link>
      </:action>
    </.table>
    """
  end

  defp status_color(:active), do: :green
  defp status_color(:suspended), do: :red
  defp status_color(:pending_recovery), do: :yellow
  defp status_color(_), do: :gray
end
