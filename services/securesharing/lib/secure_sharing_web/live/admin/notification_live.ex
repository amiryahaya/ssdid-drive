defmodule SecureSharingWeb.Admin.NotificationLive do
  @moduledoc """
  Admin LiveView for managing push notifications.

  Features:
  - Send broadcast notifications to all users
  - Send targeted notifications to specific users
  - Send test notifications to yourself
  - View notification history
  """
  use SecureSharingWeb, :live_view

  alias SecureSharing.{Accounts, Notifications}

  @impl true
  def mount(_params, session, socket) do
    current_admin_id = session["admin_user_id"]

    socket =
      socket
      |> assign(:current_admin_id, current_admin_id)
      |> assign(:form, to_form(%{"title" => "", "body" => "", "type" => "broadcast"}))
      |> assign(:selected_users, [])
      |> assign(:user_search, "")
      |> assign(:user_search_results, [])
      |> assign(:sending, false)
      |> assign(:flash_message, nil)
      |> assign(:logs_empty, Notifications.list_notification_logs(limit: 1) == [])
      |> stream(:logs, Notifications.list_notification_logs(limit: 20))

    {:ok, socket}
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, assign(socket, page_title: "Notifications")}
  end

  @impl true
  def handle_event("validate", %{"title" => title, "body" => body, "type" => type}, socket) do
    form = to_form(%{"title" => title, "body" => body, "type" => type})
    {:noreply, assign(socket, :form, form)}
  end

  @impl true
  def handle_event("search_users", %{"query" => query}, socket) do
    results =
      if String.length(query) >= 2 do
        Accounts.search_users(query, limit: 10)
      else
        []
      end

    {:noreply, assign(socket, user_search: query, user_search_results: results)}
  end

  @impl true
  def handle_event("select_user", %{"id" => user_id}, socket) do
    user = Accounts.get_user!(user_id)

    selected =
      if Enum.any?(socket.assigns.selected_users, &(&1.id == user_id)) do
        socket.assigns.selected_users
      else
        [user | socket.assigns.selected_users]
      end

    {:noreply, assign(socket, selected_users: selected, user_search: "", user_search_results: [])}
  end

  @impl true
  def handle_event("remove_user", %{"id" => user_id}, socket) do
    selected = Enum.reject(socket.assigns.selected_users, &(&1.id == user_id))
    {:noreply, assign(socket, selected_users: selected)}
  end

  @impl true
  def handle_event("send", %{"title" => title, "body" => body, "type" => type}, socket) do
    socket = assign(socket, :sending, true)

    result =
      case type do
        "broadcast" ->
          Notifications.broadcast_notification(
            %{title: title, body: body},
            socket.assigns.current_admin_id
          )

        "targeted" ->
          user_ids = Enum.map(socket.assigns.selected_users, & &1.id)

          if user_ids == [] do
            {:error, "Please select at least one user"}
          else
            Notifications.send_targeted_notification(
              %{title: title, body: body},
              user_ids,
              socket.assigns.current_admin_id
            )
          end

        "test" ->
          Notifications.send_test_notification(
            %{title: title, body: body},
            socket.assigns.current_admin_id
          )
      end

    socket =
      case result do
        {:ok, log} ->
          socket
          |> stream_insert(:logs, log, at: 0)
          |> assign(:logs_empty, false)
          |> assign(:form, to_form(%{"title" => "", "body" => "", "type" => type}))
          |> assign(:selected_users, [])
          |> put_flash(:info, "Notification sent successfully!")

        {:error, message} when is_binary(message) ->
          put_flash(socket, :error, message)

        {:error, reason} ->
          put_flash(socket, :error, "Failed to send notification: #{inspect(reason)}")
      end

    {:noreply, assign(socket, :sending, false)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <.header>
        Push Notifications
        <:subtitle>Send push notifications to app users</:subtitle>
      </.header>

      <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <!-- Send Notification Form -->
        <div class="bg-white shadow rounded-lg p-6">
          <h3 class="text-lg font-medium text-gray-900 mb-4">Send Notification</h3>

          <.form for={@form} phx-change="validate" phx-submit="send" class="space-y-4">
            <!-- Notification Type -->
            <div>
              <label class="block text-sm font-medium text-gray-700 mb-2">Type</label>
              <div class="flex space-x-4">
                <label class="inline-flex items-center">
                  <input
                    type="radio"
                    name="type"
                    value="broadcast"
                    checked={@form[:type].value == "broadcast"}
                    class="form-radio h-4 w-4 text-blue-600"
                  />
                  <span class="ml-2 text-sm text-gray-700">Broadcast (All Users)</span>
                </label>
                <label class="inline-flex items-center">
                  <input
                    type="radio"
                    name="type"
                    value="targeted"
                    checked={@form[:type].value == "targeted"}
                    class="form-radio h-4 w-4 text-blue-600"
                  />
                  <span class="ml-2 text-sm text-gray-700">Targeted</span>
                </label>
                <label class="inline-flex items-center">
                  <input
                    type="radio"
                    name="type"
                    value="test"
                    checked={@form[:type].value == "test"}
                    class="form-radio h-4 w-4 text-blue-600"
                  />
                  <span class="ml-2 text-sm text-gray-700">Test (Me Only)</span>
                </label>
              </div>
            </div>

            <!-- User Selection (for targeted) -->
            <div :if={@form[:type].value == "targeted"} class="space-y-2">
              <label class="block text-sm font-medium text-gray-700">Recipients</label>

              <!-- Selected Users -->
              <div :if={@selected_users != []} class="flex flex-wrap gap-2 mb-2">
                <span
                  :for={user <- @selected_users}
                  class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-blue-100 text-blue-800"
                >
                  {user.email}
                  <button
                    type="button"
                    phx-click="remove_user"
                    phx-value-id={user.id}
                    class="ml-1 inline-flex items-center justify-center w-4 h-4 text-blue-400 hover:text-blue-600"
                  >
                    &times;
                  </button>
                </span>
              </div>

              <!-- User Search -->
              <div class="relative">
                <input
                  type="text"
                  placeholder="Search users by email..."
                  value={@user_search}
                  phx-keyup="search_users"
                  phx-value-query={@user_search}
                  phx-debounce="300"
                  class="block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
                />

                <!-- Search Results Dropdown -->
                <div
                  :if={@user_search_results != []}
                  class="absolute z-10 mt-1 w-full bg-white shadow-lg rounded-md border border-gray-200 max-h-60 overflow-auto"
                >
                  <ul class="py-1">
                    <li
                      :for={user <- @user_search_results}
                      phx-click="select_user"
                      phx-value-id={user.id}
                      class="px-4 py-2 hover:bg-gray-100 cursor-pointer text-sm"
                    >
                      {user.email}
                      <span :if={user.display_name} class="text-gray-500 ml-2">
                        ({user.display_name})
                      </span>
                    </li>
                  </ul>
                </div>
              </div>
            </div>

            <!-- Title -->
            <div>
              <label class="block text-sm font-medium text-gray-700">Title</label>
              <input
                type="text"
                name="title"
                value={@form[:title].value}
                required
                maxlength="200"
                placeholder="Notification title"
                class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
              />
            </div>

            <!-- Body -->
            <div>
              <label class="block text-sm font-medium text-gray-700">Message</label>
              <textarea
                name="body"
                required
                maxlength="1000"
                rows="4"
                placeholder="Notification message"
                class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
              >{@form[:body].value}</textarea>
            </div>

            <!-- Submit -->
            <div class="pt-4">
              <button
                type="submit"
                disabled={@sending}
                class="w-full inline-flex justify-center items-center px-4 py-2 border border-transparent text-sm font-medium rounded-md shadow-sm text-white bg-blue-600 hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500 disabled:opacity-50 disabled:cursor-not-allowed"
              >
                <svg
                  :if={@sending}
                  class="animate-spin -ml-1 mr-2 h-4 w-4 text-white"
                  fill="none"
                  viewBox="0 0 24 24"
                >
                  <circle
                    class="opacity-25"
                    cx="12"
                    cy="12"
                    r="10"
                    stroke="currentColor"
                    stroke-width="4"
                  />
                  <path
                    class="opacity-75"
                    fill="currentColor"
                    d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"
                  />
                </svg>
                {if @sending, do: "Sending...", else: "Send Notification"}
              </button>
            </div>
          </.form>
        </div>

        <!-- Notification History -->
        <div class="bg-white shadow rounded-lg">
          <div class="px-6 py-4 border-b border-gray-200">
            <h3 class="text-lg font-medium text-gray-900">Recent Notifications</h3>
          </div>

          <div class="divide-y divide-gray-200 max-h-[600px] overflow-y-auto">
            <div
              :for={{dom_id, log} <- @streams.logs}
              id={dom_id}
              class="px-6 py-4 hover:bg-gray-50"
            >
              <div class="flex items-start justify-between">
                <div class="flex-1 min-w-0">
                  <p class="text-sm font-medium text-gray-900 truncate">{log.title}</p>
                  <p class="text-sm text-gray-500 line-clamp-2">{log.body}</p>
                </div>
                <div class="ml-4 flex-shrink-0">
                  <.badge color={status_color(log.status)}>{log.status}</.badge>
                </div>
              </div>
              <div class="mt-2 flex items-center text-xs text-gray-500 space-x-4">
                <span class="inline-flex items-center mr-2">
                  <.badge color={type_color(log.notification_type)}>
                    {log.notification_type}
                  </.badge>
                </span>
                <span :if={log.recipient_count > 0}>
                  {log.recipient_count} recipient(s)
                </span>
                <span>
                  {Calendar.strftime(log.inserted_at, "%b %d, %Y %H:%M")}
                </span>
              </div>
            </div>

            <div
              :if={@logs_empty}
              class="px-6 py-8 text-center text-gray-500"
            >
              No notifications sent yet.
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp status_color(:sent), do: :green
  defp status_color(:pending), do: :yellow
  defp status_color(:failed), do: :red
  defp status_color(_), do: :gray

  defp type_color(:broadcast), do: :blue
  defp type_color(:targeted), do: :purple
  defp type_color(:test), do: :gray
  defp type_color(_), do: :gray
end
