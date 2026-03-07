defmodule SecureSharingWeb.Admin.UserLive.Show do
  @moduledoc """
  LiveView for showing user details.
  """
  use SecureSharingWeb, :live_view

  alias SecureSharing.{Accounts, Files, Sharing}

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_params(%{"id" => id}, _url, socket) do
    user = Accounts.get_user!(id) |> SecureSharing.Repo.preload(:tenant)
    storage_used = Files.calculate_user_storage(user)
    share_stats = Sharing.count_user_shares(user)

    {:noreply,
     socket
     |> assign(:page_title, user.email)
     |> assign(:user, user)
     |> assign(:storage_used, storage_used)
     |> assign(:share_stats, share_stats)}
  end

  @impl true
  def handle_event("suspend", _, socket) do
    {:ok, user} = Accounts.update_user_status(socket.assigns.user, :suspended)
    {:noreply, assign(socket, :user, SecureSharing.Repo.preload(user, :tenant))}
  end

  @impl true
  def handle_event("activate", _, socket) do
    {:ok, user} = Accounts.update_user_status(socket.assigns.user, :active)
    {:noreply, assign(socket, :user, SecureSharing.Repo.preload(user, :tenant))}
  end

  @impl true
  def handle_event("toggle_admin", _, socket) do
    user = socket.assigns.user
    {:ok, updated_user} = Accounts.set_admin(user, not user.is_admin)
    {:noreply, assign(socket, :user, SecureSharing.Repo.preload(updated_user, :tenant))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.header>
      User: {@user.email}
      <:subtitle>
        <.link navigate={~p"/admin/tenants/#{@user.tenant_id}"} class="text-blue-600 hover:text-blue-500">
          {@user.tenant && @user.tenant.name}
        </.link>
      </:subtitle>
      <:actions>
        <.button :if={@user.status == :active} phx-click="suspend" class="bg-red-600 hover:bg-red-700">
          Suspend User
        </.button>
        <.button :if={@user.status == :suspended} phx-click="activate" class="bg-green-600 hover:bg-green-700">
          Activate User
        </.button>
        <.button phx-click="toggle_admin">
          {if @user.is_admin, do: "Remove Admin", else: "Make Admin"}
        </.button>
      </:actions>
    </.header>

    <div class="mt-6 grid grid-cols-1 gap-6 lg:grid-cols-2">
      <!-- User Details -->
      <div class="bg-white shadow rounded-lg">
        <div class="px-4 py-5 sm:px-6 border-b border-gray-200">
          <h3 class="text-lg font-medium leading-6 text-gray-900">Details</h3>
        </div>
        <div class="px-4 py-5 sm:p-6">
          <dl class="grid grid-cols-1 gap-x-4 gap-y-6 sm:grid-cols-2">
            <div>
              <dt class="text-sm font-medium text-gray-500">Email</dt>
              <dd class="mt-1 text-sm text-gray-900">{@user.email}</dd>
            </div>
            <div>
              <dt class="text-sm font-medium text-gray-500">Status</dt>
              <dd class="mt-1">
                <.badge color={status_color(@user.status)}>{@user.status}</.badge>
              </dd>
            </div>
            <div>
              <dt class="text-sm font-medium text-gray-500">Admin</dt>
              <dd class="mt-1">
                <.badge :if={@user.is_admin} color={:blue}>Yes</.badge>
                <span :if={!@user.is_admin} class="text-sm text-gray-500">No</span>
              </dd>
            </div>
            <div>
              <dt class="text-sm font-medium text-gray-500">Recovery Setup</dt>
              <dd class="mt-1">
                <.badge :if={@user.recovery_setup_complete} color={:green}>Complete</.badge>
                <span :if={!@user.recovery_setup_complete} class="text-sm text-gray-500">Not Setup</span>
              </dd>
            </div>
            <div>
              <dt class="text-sm font-medium text-gray-500">Email Confirmed</dt>
              <dd class="mt-1 text-sm text-gray-900">
                {if @user.confirmed_at, do: Calendar.strftime(@user.confirmed_at, "%b %d, %Y"), else: "Not confirmed"}
              </dd>
            </div>
            <div>
              <dt class="text-sm font-medium text-gray-500">Joined</dt>
              <dd class="mt-1 text-sm text-gray-900">
                {Calendar.strftime(@user.created_at, "%B %d, %Y at %H:%M")}
              </dd>
            </div>
          </dl>
        </div>
      </div>

      <!-- Storage & Shares -->
      <div class="bg-white shadow rounded-lg">
        <div class="px-4 py-5 sm:px-6 border-b border-gray-200">
          <h3 class="text-lg font-medium leading-6 text-gray-900">Storage & Shares</h3>
        </div>
        <div class="px-4 py-5 sm:p-6">
          <dl class="grid grid-cols-1 gap-x-4 gap-y-6 sm:grid-cols-2">
            <div>
              <dt class="text-sm font-medium text-gray-500">Storage Used</dt>
              <dd class="mt-1 text-sm text-gray-900">{format_bytes(@storage_used)}</dd>
            </div>
            <div>
              <dt class="text-sm font-medium text-gray-500">Shares Received</dt>
              <dd class="mt-1 text-sm text-gray-900">{@share_stats.received}</dd>
            </div>
            <div>
              <dt class="text-sm font-medium text-gray-500">Shares Created</dt>
              <dd class="mt-1 text-sm text-gray-900">{@share_stats.created}</dd>
            </div>
          </dl>
        </div>
      </div>

      <!-- Public Keys Info -->
      <div class="bg-white shadow rounded-lg lg:col-span-2">
        <div class="px-4 py-5 sm:px-6 border-b border-gray-200">
          <h3 class="text-lg font-medium leading-6 text-gray-900">Cryptographic Keys</h3>
        </div>
        <div class="px-4 py-5 sm:p-6">
          <dl class="grid grid-cols-1 gap-x-4 gap-y-6 sm:grid-cols-3">
            <div>
              <dt class="text-sm font-medium text-gray-500">ML-KEM Public Key</dt>
              <dd class="mt-1 text-sm text-gray-900">
                {if @user.public_keys["ml_kem"], do: "Present", else: "Not set"}
              </dd>
            </div>
            <div>
              <dt class="text-sm font-medium text-gray-500">ML-DSA Public Key</dt>
              <dd class="mt-1 text-sm text-gray-900">
                {if @user.public_keys["ml_dsa"], do: "Present", else: "Not set"}
              </dd>
            </div>
            <div>
              <dt class="text-sm font-medium text-gray-500">Key Derivation Salt</dt>
              <dd class="mt-1 text-sm text-gray-900">
                {if @user.key_derivation_salt, do: "Present", else: "Not set"}
              </dd>
            </div>
          </dl>
        </div>
      </div>
    </div>

    <.back navigate={~p"/admin/users"}>Back to users</.back>
    """
  end

  defp status_color(:active), do: :green
  defp status_color(:suspended), do: :red
  defp status_color(:pending_recovery), do: :yellow
  defp status_color(_), do: :gray

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

  defp format_bytes(_), do: "0 B"
end
