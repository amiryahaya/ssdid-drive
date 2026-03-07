defmodule SecureSharingWeb.Admin.AuditLive do
  @moduledoc """
  LiveView for viewing audit logs with search, filtering, and export capabilities.
  """
  use SecureSharingWeb, :live_view

  alias SecureSharing.Accounts
  alias SecureSharing.Audit
  alias SecureSharing.Audit.AuditEvent

  @per_page 25

  @impl true
  def mount(_params, session, socket) do
    tenant_id = session["tenant_id"]

    socket =
      socket
      |> assign(:tenant_id, tenant_id)
      |> assign(:tenants, Accounts.list_tenants())
      |> assign(:selected_tenant, nil)
      |> assign(:filters, default_filters())
      |> assign(:page, 1)
      |> assign(:total_count, 0)
      |> assign(:events, [])
      |> assign(:statistics, nil)

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    tenant_id = params["tenant_id"] || socket.assigns.selected_tenant

    socket =
      socket
      |> assign(:page_title, "Audit Log")
      |> assign(:selected_tenant, tenant_id)
      |> maybe_load_events()

    {:noreply, socket}
  end

  @impl true
  def handle_event("select_tenant", %{"tenant_id" => tenant_id}, socket) do
    tenant_id = if tenant_id == "", do: nil, else: tenant_id

    socket =
      socket
      |> assign(:selected_tenant, tenant_id)
      |> assign(:page, 1)
      |> maybe_load_events()

    {:noreply, socket}
  end

  @impl true
  def handle_event("filter", %{"filters" => filter_params}, socket) do
    filters = parse_filters(filter_params)

    socket =
      socket
      |> assign(:filters, filters)
      |> assign(:page, 1)
      |> maybe_load_events()

    {:noreply, socket}
  end

  @impl true
  def handle_event("clear_filters", _, socket) do
    socket =
      socket
      |> assign(:filters, default_filters())
      |> assign(:page, 1)
      |> maybe_load_events()

    {:noreply, socket}
  end

  @impl true
  def handle_event("page", %{"page" => page}, socket) do
    page = String.to_integer(page)

    socket =
      socket
      |> assign(:page, page)
      |> maybe_load_events()

    {:noreply, socket}
  end

  @impl true
  def handle_event("refresh", _, socket) do
    {:noreply, maybe_load_events(socket)}
  end

  @impl true
  def handle_event("export_csv", _, socket) do
    if socket.assigns.selected_tenant do
      events =
        Audit.export_events(
          socket.assigns.selected_tenant,
          build_filter_opts(socket.assigns.filters)
        )

      csv = build_csv(events)

      {:noreply,
       push_event(socket, "download", %{
         content: csv,
         filename: "audit_log_#{Date.utc_today()}.csv",
         type: "text/csv"
       })}
    else
      {:noreply, put_flash(socket, :error, "Please select a tenant first")}
    end
  end

  @impl true
  def handle_event("export_json", _, socket) do
    if socket.assigns.selected_tenant do
      events =
        Audit.export_events(
          socket.assigns.selected_tenant,
          build_filter_opts(socket.assigns.filters)
        )

      json = Jason.encode!(events, pretty: true)

      {:noreply,
       push_event(socket, "download", %{
         content: json,
         filename: "audit_log_#{Date.utc_today()}.json",
         type: "application/json"
       })}
    else
      {:noreply, put_flash(socket, :error, "Please select a tenant first")}
    end
  end

  defp default_filters do
    %{
      action: nil,
      resource_type: nil,
      status: nil,
      user_id: nil,
      from: nil,
      to: nil,
      ip_address: nil
    }
  end

  defp parse_filters(params) do
    %{
      action: blank_to_nil(params["action"]),
      resource_type: blank_to_nil(params["resource_type"]),
      status: blank_to_nil(params["status"]),
      user_id: blank_to_nil(params["user_id"]),
      from: parse_datetime(params["from"]),
      to: parse_datetime(params["to"]),
      ip_address: blank_to_nil(params["ip_address"])
    }
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp parse_datetime(nil), do: nil
  defp parse_datetime(""), do: nil

  defp parse_datetime(string) do
    case DateTime.from_iso8601(string <> ":00Z") do
      {:ok, dt, _} -> dt
      _ -> nil
    end
  end

  defp build_filter_opts(filters) do
    filters
    |> Enum.reject(fn {_, v} -> is_nil(v) end)
    |> Enum.into([])
  end

  defp maybe_load_events(%{assigns: %{selected_tenant: nil}} = socket) do
    socket
    |> assign(:events, [])
    |> assign(:total_count, 0)
    |> assign(:statistics, nil)
  end

  defp maybe_load_events(
         %{assigns: %{selected_tenant: tenant_id, filters: filters, page: page}} = socket
       ) do
    opts = build_filter_opts(filters)
    offset = (page - 1) * @per_page

    events = Audit.list_events(tenant_id, opts ++ [limit: @per_page, offset: offset])
    total_count = Audit.count_events(tenant_id, opts)
    statistics = Audit.get_statistics(tenant_id, opts)

    socket
    |> assign(:events, events)
    |> assign(:total_count, total_count)
    |> assign(:statistics, statistics)
  end

  defp total_pages(total_count) do
    ceil(total_count / @per_page)
  end

  defp build_csv(events) do
    headers =
      "ID,Timestamp,User Email,Action,Resource Type,Resource ID,IP Address,User Agent,Status,Error Message,Metadata\n"

    rows =
      Enum.map(events, fn event ->
        [
          event.id,
          event.timestamp,
          event.user_email || "",
          event.action,
          event.resource_type,
          event.resource_id || "",
          event.ip_address || "",
          csv_escape(event.user_agent || ""),
          event.status,
          csv_escape(event.error_message || ""),
          csv_escape(event.metadata)
        ]
        |> Enum.join(",")
      end)
      |> Enum.join("\n")

    headers <> rows
  end

  defp csv_escape(value) when is_binary(value) do
    if String.contains?(value, [",", "\"", "\n"]) do
      "\"" <> String.replace(value, "\"", "\"\"") <> "\""
    else
      value
    end
  end

  defp csv_escape(value), do: inspect(value)

  @impl true
  def render(assigns) do
    ~H"""
    <.header>
      Audit Log
      <:subtitle>Security audit trail and system activity</:subtitle>
      <:actions>
        <.button phx-click="refresh" class="mr-2">Refresh</.button>
        <.button :if={@selected_tenant} phx-click="export_csv" class="mr-2">Export CSV</.button>
        <.button :if={@selected_tenant} phx-click="export_json">Export JSON</.button>
      </:actions>
    </.header>

    <div class="mt-6 space-y-6">
      <!-- Tenant Selector -->
      <div class="bg-white shadow rounded-lg p-4">
        <label class="block text-sm font-medium text-gray-700 mb-2">Select Tenant</label>
        <select
          phx-change="select_tenant"
          name="tenant_id"
          class="block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
        >
          <option value="">-- Select a tenant --</option>
          <option :for={tenant <- @tenants} value={tenant.id} selected={tenant.id == @selected_tenant}>
            {tenant.name} ({tenant.slug})
          </option>
        </select>
      </div>

      <!-- Filters -->
      <div :if={@selected_tenant} class="bg-white shadow rounded-lg p-4">
        <h3 class="text-lg font-medium text-gray-900 mb-4">Filters</h3>
        <.form for={%{}} phx-change="filter" phx-submit="filter" class="space-y-4">
          <div class="grid grid-cols-1 md:grid-cols-3 lg:grid-cols-4 gap-4">
            <div>
              <label class="block text-sm font-medium text-gray-700">Action</label>
              <select name="filters[action]" class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm">
                <option value="">All Actions</option>
                <option :for={action <- AuditEvent.valid_actions()} value={action} selected={@filters.action == action}>
                  {action}
                </option>
              </select>
            </div>
            <div>
              <label class="block text-sm font-medium text-gray-700">Resource Type</label>
              <select name="filters[resource_type]" class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm">
                <option value="">All Resources</option>
                <option :for={type <- AuditEvent.valid_resource_types()} value={type} selected={@filters.resource_type == type}>
                  {type}
                </option>
              </select>
            </div>
            <div>
              <label class="block text-sm font-medium text-gray-700">Status</label>
              <select name="filters[status]" class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm">
                <option value="">All Statuses</option>
                <option value="success" selected={@filters.status == "success"}>Success</option>
                <option value="failure" selected={@filters.status == "failure"}>Failure</option>
              </select>
            </div>
            <div>
              <label class="block text-sm font-medium text-gray-700">IP Address</label>
              <input
                type="text"
                name="filters[ip_address]"
                value={@filters.ip_address}
                placeholder="e.g., 192.168.1.1"
                class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
              />
            </div>
            <div>
              <label class="block text-sm font-medium text-gray-700">From Date</label>
              <input
                type="datetime-local"
                name="filters[from]"
                value={format_datetime_local(@filters.from)}
                class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
              />
            </div>
            <div>
              <label class="block text-sm font-medium text-gray-700">To Date</label>
              <input
                type="datetime-local"
                name="filters[to]"
                value={format_datetime_local(@filters.to)}
                class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
              />
            </div>
          </div>
          <div class="flex justify-end">
            <.button type="button" phx-click="clear_filters" class="mr-2">Clear Filters</.button>
            <.button type="submit">Apply Filters</.button>
          </div>
        </.form>
      </div>

      <!-- Statistics -->
      <div :if={@statistics} class="grid grid-cols-1 md:grid-cols-4 gap-4">
        <div class="bg-white shadow rounded-lg p-4">
          <h4 class="text-sm font-medium text-gray-500">Total Events</h4>
          <p class="mt-1 text-2xl font-semibold text-gray-900">{@statistics.total}</p>
        </div>
        <div class="bg-white shadow rounded-lg p-4">
          <h4 class="text-sm font-medium text-gray-500">Success Rate</h4>
          <p class="mt-1 text-2xl font-semibold text-green-600">
            {calculate_success_rate(@statistics)}%
          </p>
        </div>
        <div class="bg-white shadow rounded-lg p-4">
          <h4 class="text-sm font-medium text-gray-500">Top Action</h4>
          <p class="mt-1 text-lg font-semibold text-gray-900">{top_action(@statistics)}</p>
        </div>
        <div class="bg-white shadow rounded-lg p-4">
          <h4 class="text-sm font-medium text-gray-500">Top Resource</h4>
          <p class="mt-1 text-lg font-semibold text-gray-900">{top_resource(@statistics)}</p>
        </div>
      </div>

      <!-- Events Table -->
      <div :if={@selected_tenant} class="bg-white shadow rounded-lg overflow-hidden">
        <div class="px-4 py-5 sm:px-6 border-b border-gray-200">
          <h3 class="text-lg font-medium leading-6 text-gray-900">Audit Events</h3>
          <p class="mt-1 text-sm text-gray-500">
            Showing {length(@events)} of {@total_count} events
          </p>
        </div>

        <div class="overflow-x-auto">
          <table class="min-w-full divide-y divide-gray-200">
            <thead class="bg-gray-50">
              <tr>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Timestamp</th>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">User</th>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Action</th>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Resource</th>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">IP Address</th>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Status</th>
              </tr>
            </thead>
            <tbody class="bg-white divide-y divide-gray-200">
              <tr :for={event <- @events} class="hover:bg-gray-50">
                <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                  {format_timestamp(event.inserted_at)}
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                  {if event.user, do: event.user.email, else: "System"}
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-sm">
                  <span class={action_badge_class(event.action)}>
                    {event.action}
                  </span>
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                  <span class="font-medium">{event.resource_type}</span>
                  <span :if={event.resource_id} class="text-gray-400 text-xs ml-1">
                    ({truncate_id(event.resource_id)})
                  </span>
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                  {event.ip_address || "-"}
                </td>
                <td class="px-6 py-4 whitespace-nowrap">
                  <span class={status_badge_class(event.status)}>
                    {event.status}
                  </span>
                </td>
              </tr>
              <tr :if={@events == []}>
                <td colspan="6" class="px-6 py-8 text-center text-gray-500">
                  No audit events found
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <!-- Pagination -->
        <div :if={@total_count > 25} class="px-4 py-3 bg-gray-50 border-t border-gray-200 sm:px-6">
          <div class="flex items-center justify-between">
            <div class="text-sm text-gray-700">
              Page {@page} of {total_pages(@total_count)}
            </div>
            <div class="flex space-x-2">
              <.button
                :if={@page > 1}
                phx-click="page"
                phx-value-page={@page - 1}
              >
                Previous
              </.button>
              <.button
                :if={@page < total_pages(@total_count)}
                phx-click="page"
                phx-value-page={@page + 1}
              >
                Next
              </.button>
            </div>
          </div>
        </div>
      </div>

      <!-- No Tenant Selected -->
      <div :if={!@selected_tenant} class="bg-gray-50 border border-gray-200 rounded-lg p-8 text-center">
        <p class="text-gray-500">Please select a tenant to view audit logs.</p>
      </div>
    </div>

    <script>
      window.addEventListener("phx:download", (e) => {
        const {content, filename, type} = e.detail;
        const blob = new Blob([content], {type: type});
        const url = URL.createObjectURL(blob);
        const a = document.createElement("a");
        a.href = url;
        a.download = filename;
        document.body.appendChild(a);
        a.click();
        document.body.removeChild(a);
        URL.revokeObjectURL(url);
      });
    </script>
    """
  end

  defp format_timestamp(timestamp) do
    Calendar.strftime(timestamp, "%Y-%m-%d %H:%M:%S")
  end

  defp format_datetime_local(nil), do: ""

  defp format_datetime_local(datetime) do
    Calendar.strftime(datetime, "%Y-%m-%dT%H:%M")
  end

  defp action_badge_class(action) do
    base = "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium"

    cond do
      String.starts_with?(action, "user.login") -> "#{base} bg-blue-100 text-blue-800"
      String.starts_with?(action, "user.") -> "#{base} bg-green-100 text-green-800"
      String.starts_with?(action, "file.") -> "#{base} bg-purple-100 text-purple-800"
      String.starts_with?(action, "folder.") -> "#{base} bg-indigo-100 text-indigo-800"
      String.starts_with?(action, "share.") -> "#{base} bg-yellow-100 text-yellow-800"
      String.starts_with?(action, "recovery.") -> "#{base} bg-red-100 text-red-800"
      String.starts_with?(action, "admin.") -> "#{base} bg-gray-100 text-gray-800"
      true -> "#{base} bg-gray-100 text-gray-800"
    end
  end

  defp status_badge_class("success") do
    "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-green-100 text-green-800"
  end

  defp status_badge_class("failure") do
    "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-red-100 text-red-800"
  end

  defp status_badge_class(_) do
    "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-gray-100 text-gray-800"
  end

  defp truncate_id(id) when is_binary(id) do
    String.slice(id, 0, 8) <> "..."
  end

  defp truncate_id(_), do: ""

  defp calculate_success_rate(%{by_status: status_counts, total: total}) when total > 0 do
    success = Map.get(status_counts, "success", 0)
    round(success / total * 100)
  end

  defp calculate_success_rate(_), do: 0

  defp top_action(%{by_action: action_counts}) when map_size(action_counts) > 0 do
    {action, _count} = Enum.max_by(action_counts, fn {_k, v} -> v end)
    action
  end

  defp top_action(_), do: "-"

  defp top_resource(%{by_resource_type: resource_counts}) when map_size(resource_counts) > 0 do
    {resource, _count} = Enum.max_by(resource_counts, fn {_k, v} -> v end)
    resource
  end

  defp top_resource(_), do: "-"
end
