defmodule SecureSharingWeb.Admin.DashboardLive do
  @moduledoc """
  Admin dashboard LiveView displaying system statistics.
  """
  use SecureSharingWeb, :live_view

  alias SecureSharing.{Accounts, Files, Sharing}

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      # Subscribe to relevant PubSub topics for real-time updates
      Phoenix.PubSub.subscribe(SecureSharing.PubSub, "admin:stats")
    end

    {:ok, assign_stats(socket)}
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, assign(socket, page_title: "Dashboard")}
  end

  @impl true
  def handle_info({:stats_updated, _}, socket) do
    {:noreply, assign_stats(socket)}
  end

  defp assign_stats(socket) do
    socket
    |> assign(:tenant_count, Accounts.count_tenants())
    |> assign(:user_count, Accounts.count_users())
    |> assign(:file_count, Files.count_files())
    |> assign(:share_count, Sharing.count_shares())
    |> assign(:total_storage, Files.calculate_total_storage())
    |> assign(:tenant_file_stats, Files.get_all_tenants_file_stats(limit: 10))
    |> assign(:recent_tenants, Accounts.list_recent_tenants(limit: 5))
    |> assign(:recent_users, Accounts.list_recent_users(limit: 5))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <!-- Stats Grid -->
      <div class="grid grid-cols-1 gap-5 sm:grid-cols-2 lg:grid-cols-5">
        <.stat_card title="Total Tenants" value={@tenant_count} icon="+" />
        <.stat_card title="Total Users" value={@user_count} icon="+" />
        <.stat_card title="Total Files" value={@file_count} icon="+" />
        <.stat_card title="Active Shares" value={@share_count} icon="+" />
        <.stat_card title="Total Storage" value={format_bytes(@total_storage)} icon="+" />
      </div>

      <!-- Storage by Tenant -->
      <div class="bg-white shadow rounded-lg">
        <div class="px-4 py-5 sm:px-6 border-b border-gray-200">
          <h3 class="text-lg font-medium leading-6 text-gray-900">Storage by Tenant</h3>
          <p class="mt-1 text-sm text-gray-500">Top tenants by storage usage</p>
        </div>
        <div class="overflow-x-auto">
          <table class="min-w-full divide-y divide-gray-200">
            <thead class="bg-gray-50">
              <tr>
                <th scope="col" class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  Tenant
                </th>
                <th scope="col" class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  Files
                </th>
                <th scope="col" class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  Storage Used
                </th>
                <th scope="col" class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  Quota
                </th>
                <th scope="col" class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  Usage
                </th>
              </tr>
            </thead>
            <tbody class="bg-white divide-y divide-gray-200">
              <tr :for={stat <- @tenant_file_stats} class="hover:bg-gray-50">
                <td class="px-6 py-4 whitespace-nowrap">
                  <.link navigate={~p"/admin/tenants/#{stat.tenant_id}"} class="text-sm font-medium text-blue-600 hover:text-blue-500">
                    {stat.tenant_name}
                  </.link>
                  <p class="text-xs text-gray-500">{stat.tenant_slug}</p>
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                  {stat.file_count}
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                  {format_bytes(stat.storage_bytes)}
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                  {format_bytes(stat.storage_quota_bytes)}
                </td>
                <td class="px-6 py-4 whitespace-nowrap">
                  <div class="flex items-center">
                    <div class="w-24 bg-gray-200 rounded-full h-2 mr-2">
                      <div
                        class={[
                          "h-2 rounded-full",
                          storage_bar_color(stat.storage_percentage)
                        ]}
                        style={"width: #{min(stat.storage_percentage, 100)}%"}
                      >
                      </div>
                    </div>
                    <span class="text-sm text-gray-600">{stat.storage_percentage}%</span>
                  </div>
                </td>
              </tr>
              <tr :if={@tenant_file_stats == []}>
                <td colspan="5" class="px-6 py-4 text-center text-sm text-gray-500">
                  No tenants with files yet.
                </td>
              </tr>
            </tbody>
          </table>
        </div>
        <div class="px-4 py-4 sm:px-6 border-t border-gray-200">
          <.link navigate={~p"/admin/tenants"} class="text-sm font-medium text-blue-600 hover:text-blue-500">
            View all tenants &rarr;
          </.link>
        </div>
      </div>

      <!-- Recent Activity -->
      <div class="grid grid-cols-1 gap-6 lg:grid-cols-2">
        <!-- Recent Tenants -->
        <div class="bg-white shadow rounded-lg">
          <div class="px-4 py-5 sm:px-6 border-b border-gray-200">
            <h3 class="text-lg font-medium leading-6 text-gray-900">Recent Tenants</h3>
          </div>
          <ul role="list" class="divide-y divide-gray-200">
            <li :for={tenant <- @recent_tenants} class="px-4 py-4 sm:px-6">
              <div class="flex items-center justify-between">
                <div class="flex items-center">
                  <p class="text-sm font-medium text-blue-600 truncate">
                    <.link navigate={~p"/admin/tenants/#{tenant.id}"}>{tenant.name}</.link>
                  </p>
                </div>
                <div class="ml-2 flex-shrink-0 flex">
                  <.badge color={:blue}>{tenant.slug}</.badge>
                </div>
              </div>
              <div class="mt-2 sm:flex sm:justify-between">
                <p class="text-sm text-gray-500">
                  Created {Calendar.strftime(tenant.created_at, "%b %d, %Y")}
                </p>
              </div>
            </li>
            <li :if={@recent_tenants == []} class="px-4 py-4 sm:px-6 text-gray-500 text-sm">
              No tenants yet.
            </li>
          </ul>
          <div class="px-4 py-4 sm:px-6 border-t border-gray-200">
            <.link navigate={~p"/admin/tenants"} class="text-sm font-medium text-blue-600 hover:text-blue-500">
              View all tenants &rarr;
            </.link>
          </div>
        </div>

        <!-- Recent Users -->
        <div class="bg-white shadow rounded-lg">
          <div class="px-4 py-5 sm:px-6 border-b border-gray-200">
            <h3 class="text-lg font-medium leading-6 text-gray-900">Recent Users</h3>
          </div>
          <ul role="list" class="divide-y divide-gray-200">
            <li :for={user <- @recent_users} class="px-4 py-4 sm:px-6">
              <div class="flex items-center justify-between">
                <div class="flex items-center">
                  <p class="text-sm font-medium text-blue-600 truncate">
                    <.link navigate={~p"/admin/users/#{user.id}"}>{user.email}</.link>
                  </p>
                </div>
                <div class="ml-2 flex-shrink-0 flex">
                  <.badge color={status_color(user.status)}>{user.status}</.badge>
                </div>
              </div>
              <div class="mt-2 sm:flex sm:justify-between">
                <p class="text-sm text-gray-500">
                  Joined {Calendar.strftime(user.created_at, "%b %d, %Y")}
                </p>
              </div>
            </li>
            <li :if={@recent_users == []} class="px-4 py-4 sm:px-6 text-gray-500 text-sm">
              No users yet.
            </li>
          </ul>
          <div class="px-4 py-4 sm:px-6 border-t border-gray-200">
            <.link navigate={~p"/admin/users"} class="text-sm font-medium text-blue-600 hover:text-blue-500">
              View all users &rarr;
            </.link>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp status_color(:active), do: :green
  defp status_color(:suspended), do: :red
  defp status_color(:pending_recovery), do: :yellow
  defp status_color(_), do: :gray

  defp format_bytes(bytes) when is_integer(bytes) and bytes >= 1_099_511_627_776 do
    "#{Float.round(bytes / 1_099_511_627_776, 2)} TB"
  end

  defp format_bytes(bytes) when is_integer(bytes) and bytes >= 1_073_741_824 do
    "#{Float.round(bytes / 1_073_741_824, 2)} GB"
  end

  defp format_bytes(bytes) when is_integer(bytes) and bytes >= 1_048_576 do
    "#{Float.round(bytes / 1_048_576, 2)} MB"
  end

  defp format_bytes(bytes) when is_integer(bytes) and bytes >= 1024 do
    "#{Float.round(bytes / 1024, 2)} KB"
  end

  defp format_bytes(bytes) when is_integer(bytes), do: "#{bytes} B"
  defp format_bytes(_), do: "0 B"

  defp storage_bar_color(percentage) when percentage >= 90, do: "bg-red-500"
  defp storage_bar_color(percentage) when percentage >= 75, do: "bg-yellow-500"
  defp storage_bar_color(_), do: "bg-blue-500"
end
