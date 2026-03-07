defmodule SecureSharingWeb.Admin.TenantLive.Show do
  @moduledoc """
  LiveView for showing tenant details with member and invitation management.
  """
  use SecureSharingWeb, :live_view

  alias SecureSharing.{Accounts, Files}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:invite_email, "")
     |> assign(:invite_role, "member")
     |> assign(:invite_error, nil)
     |> assign(:invite_success, nil)}
  end

  @impl true
  def handle_params(%{"id" => id}, _url, socket) do
    tenant = Accounts.get_tenant(id)
    members = Accounts.list_tenant_members(tenant.id)
    pending_invitations = Accounts.list_tenant_members(tenant.id, status: "pending")
    file_stats = Files.get_tenant_file_stats(tenant.id)

    {:noreply,
     socket
     |> assign(:page_title, tenant.name)
     |> assign(:tenant, tenant)
     |> assign(:members, members)
     |> assign(:pending_invitations, pending_invitations)
     |> assign(:member_count, length(members))
     |> assign(:file_count, file_stats.file_count)
     |> assign(:storage_used, file_stats.storage_bytes)}
  end

  @impl true
  def handle_event("invite_member", %{"email" => email, "role" => role}, socket) do
    tenant_id = socket.assigns.tenant.id
    # Use current admin as inviter (from session)
    inviter_id = socket.assigns.current_user.id
    role_atom = String.to_existing_atom(role)

    case invite_user(email, tenant_id, inviter_id, role_atom) do
      {:ok, _user_tenant} ->
        pending = Accounts.list_tenant_members(tenant_id, status: "pending")

        {:noreply,
         socket
         |> assign(:pending_invitations, pending)
         |> assign(:invite_email, "")
         |> assign(:invite_error, nil)
         |> assign(:invite_success, "Invitation sent to #{email}")}

      {:error, message} ->
        {:noreply,
         socket
         |> assign(:invite_error, message)
         |> assign(:invite_success, nil)}
    end
  end

  def handle_event("update_role", %{"user_id" => user_id, "role" => role}, socket) do
    tenant_id = socket.assigns.tenant.id
    role_atom = String.to_existing_atom(role)

    case Accounts.update_user_role_in_tenant(user_id, tenant_id, role_atom) do
      {:ok, _} ->
        members = Accounts.list_tenant_members(tenant_id)
        {:noreply, assign(socket, :members, members)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to update role")}
    end
  end

  def handle_event("remove_member", %{"user_id" => user_id}, socket) do
    tenant_id = socket.assigns.tenant.id

    case Accounts.remove_user_from_tenant(user_id, tenant_id) do
      {:ok, _} ->
        members = Accounts.list_tenant_members(tenant_id)
        {:noreply, assign(socket, :members, members)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to remove member")}
    end
  end

  def handle_event("cancel_invitation", %{"user_id" => user_id}, socket) do
    tenant_id = socket.assigns.tenant.id

    case Accounts.remove_user_from_tenant(user_id, tenant_id) do
      {:ok, _} ->
        pending = Accounts.list_tenant_members(tenant_id, status: "pending")
        {:noreply, assign(socket, :pending_invitations, pending)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to cancel invitation")}
    end
  end

  def handle_event("update_invite_email", %{"value" => email}, socket) do
    {:noreply, assign(socket, :invite_email, email)}
  end

  def handle_event("update_invite_role", %{"value" => role}, socket) do
    {:noreply, assign(socket, :invite_role, role)}
  end

  defp invite_user(email, tenant_id, inviter_id, role) do
    case Accounts.get_user_by_email(email) do
      nil ->
        {:error, "User not found with email: #{email}"}

      user ->
        case Accounts.get_user_tenant(user.id, tenant_id) do
          nil ->
            Accounts.invite_user_to_tenant(user.id, tenant_id, inviter_id, role)

          %{status: "pending"} ->
            {:error, "User already has a pending invitation"}

          _ ->
            {:error, "User is already a member of this tenant"}
        end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.header>
      Tenant: {@tenant.name}
      <:subtitle>Slug: {@tenant.slug}</:subtitle>
      <:actions>
        <.link patch={~p"/admin/tenants/#{@tenant}/edit"} phx-click={JS.push_focus()}>
          <.button>Edit tenant</.button>
        </.link>
      </:actions>
    </.header>

    <div class="mt-6 grid grid-cols-1 gap-6 lg:grid-cols-2">
      <!-- Tenant Details -->
      <div class="bg-white shadow rounded-lg">
        <div class="px-4 py-5 sm:px-6 border-b border-gray-200">
          <h3 class="text-lg font-medium leading-6 text-gray-900">Details</h3>
        </div>
        <div class="px-4 py-5 sm:p-6">
          <dl class="grid grid-cols-1 gap-x-4 gap-y-6 sm:grid-cols-2">
            <div>
              <dt class="text-sm font-medium text-gray-500">Name</dt>
              <dd class="mt-1 text-sm text-gray-900">{@tenant.name}</dd>
            </div>
            <div>
              <dt class="text-sm font-medium text-gray-500">Slug</dt>
              <dd class="mt-1 text-sm text-gray-900">{@tenant.slug}</dd>
            </div>
            <div>
              <dt class="text-sm font-medium text-gray-500">Storage Quota</dt>
              <dd class="mt-1 text-sm text-gray-900">{format_bytes(@tenant.storage_quota_bytes)}</dd>
            </div>
            <div>
              <dt class="text-sm font-medium text-gray-500">Storage Used</dt>
              <dd class="mt-1 text-sm text-gray-900">
                {format_bytes(@storage_used)}
                <span class="text-gray-500">
                  ({Float.round(@storage_used / max(@tenant.storage_quota_bytes, 1) * 100, 1)}%)
                </span>
              </dd>
            </div>
            <div>
              <dt class="text-sm font-medium text-gray-500">Total Files</dt>
              <dd class="mt-1 text-sm text-gray-900">{@file_count}</dd>
            </div>
            <div>
              <dt class="text-sm font-medium text-gray-500">Max Users</dt>
              <dd class="mt-1 text-sm text-gray-900">{@tenant.max_users}</dd>
            </div>
            <div>
              <dt class="text-sm font-medium text-gray-500">Current Members</dt>
              <dd class="mt-1 text-sm text-gray-900">{@member_count}</dd>
            </div>
            <div>
              <dt class="text-sm font-medium text-gray-500">Created</dt>
              <dd class="mt-1 text-sm text-gray-900">
                {Calendar.strftime(@tenant.created_at, "%B %d, %Y at %H:%M")}
              </dd>
            </div>
            <div>
              <dt class="text-sm font-medium text-gray-500">PQC Algorithm</dt>
              <dd class="mt-1 text-sm text-gray-900">{@tenant.pqc_algorithm || "Default (kaz)"}</dd>
            </div>
          </dl>
        </div>
      </div>

      <!-- Invite Member -->
      <div class="bg-white shadow rounded-lg">
        <div class="px-4 py-5 sm:px-6 border-b border-gray-200">
          <h3 class="text-lg font-medium leading-6 text-gray-900">Invite Member</h3>
        </div>
        <div class="px-4 py-5 sm:p-6">
          <form phx-submit="invite_member" class="space-y-4">
            <div>
              <label for="email" class="block text-sm font-medium text-gray-700">Email</label>
              <input
                type="email"
                name="email"
                id="email"
                value={@invite_email}
                phx-change="update_invite_email"
                class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
                placeholder="user@example.com"
                required
              />
            </div>
            <div>
              <label for="role" class="block text-sm font-medium text-gray-700">Role</label>
              <select
                name="role"
                id="role"
                phx-change="update_invite_role"
                class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
              >
                <option value="member" selected={@invite_role == "member"}>Member</option>
                <option value="admin" selected={@invite_role == "admin"}>Admin</option>
                <option value="owner" selected={@invite_role == "owner"}>Owner</option>
              </select>
            </div>
            <div>
              <.button type="submit">Send Invitation</.button>
            </div>
            <div :if={@invite_error} class="text-sm text-red-600">{@invite_error}</div>
            <div :if={@invite_success} class="text-sm text-green-600">{@invite_success}</div>
          </form>
        </div>
      </div>
    </div>

    <!-- Members Section -->
    <div class="mt-6 bg-white shadow rounded-lg">
      <div class="px-4 py-5 sm:px-6 border-b border-gray-200">
        <h3 class="text-lg font-medium leading-6 text-gray-900">Members ({@member_count})</h3>
      </div>
      <div class="overflow-x-auto">
        <table class="min-w-full divide-y divide-gray-200">
          <thead class="bg-gray-50">
            <tr>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">User</th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Role</th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Joined</th>
              <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">Actions</th>
            </tr>
          </thead>
          <tbody class="bg-white divide-y divide-gray-200">
            <tr :for={member <- @members}>
              <td class="px-6 py-4 whitespace-nowrap">
                <div class="flex items-center">
                  <div>
                    <div class="text-sm font-medium text-gray-900">
                      <.link navigate={~p"/admin/users/#{member.user_id}"} class="text-blue-600 hover:text-blue-500">
                        {member.email || "Unknown"}
                      </.link>
                    </div>
                    <div class="text-sm text-gray-500">{member.display_name || ""}</div>
                  </div>
                </div>
              </td>
              <td class="px-6 py-4 whitespace-nowrap">
                <form phx-change="update_role" phx-value-user_id={member.user_id}>
                  <select
                    name="role"
                    class="rounded-md border-gray-300 text-sm focus:border-blue-500 focus:ring-blue-500"
                  >
                    <option value="member" selected={member.role == :member}>Member</option>
                    <option value="admin" selected={member.role == :admin}>Admin</option>
                    <option value="owner" selected={member.role == :owner}>Owner</option>
                  </select>
                </form>
              </td>
              <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                {format_date(member.joined_at || member.inserted_at)}
              </td>
              <td class="px-6 py-4 whitespace-nowrap text-right text-sm font-medium">
                <button
                  :if={member.role != :owner}
                  phx-click="remove_member"
                  phx-value-user_id={member.user_id}
                  data-confirm="Are you sure you want to remove this member?"
                  class="text-red-600 hover:text-red-900"
                >
                  Remove
                </button>
                <span :if={member.role == :owner} class="text-gray-400">Owner</span>
              </td>
            </tr>
            <tr :if={@members == []}>
              <td colspan="4" class="px-6 py-4 text-center text-gray-500 text-sm">
                No members in this tenant.
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>

    <!-- Pending Invitations Section -->
    <div :if={@pending_invitations != []} class="mt-6 bg-white shadow rounded-lg">
      <div class="px-4 py-5 sm:px-6 border-b border-gray-200">
        <h3 class="text-lg font-medium leading-6 text-gray-900">
          Pending Invitations ({length(@pending_invitations)})
        </h3>
      </div>
      <ul role="list" class="divide-y divide-gray-200">
        <li :for={invitation <- @pending_invitations} class="px-4 py-4 sm:px-6">
          <div class="flex items-center justify-between">
            <div>
              <span class="text-sm font-medium text-gray-900">{invitation.email || "Unknown"}</span>
              <span class="ml-2"><.badge color={role_color(invitation.role)}>{invitation.role}</.badge></span>
            </div>
            <div class="flex items-center space-x-4">
              <span class="text-sm text-gray-500">
                Invited {format_date(invitation.inserted_at)}
              </span>
              <button
                phx-click="cancel_invitation"
                phx-value-user_id={invitation.user_id}
                data-confirm="Are you sure you want to cancel this invitation?"
                class="text-red-600 hover:text-red-900 text-sm"
              >
                Cancel
              </button>
            </div>
          </div>
        </li>
      </ul>
    </div>

    <div class="mt-6">
      <.back navigate={~p"/admin/tenants"}>Back to tenants</.back>
    </div>

    <.modal :if={@live_action == :edit} id="tenant-modal" show on_cancel={JS.patch(~p"/admin/tenants/#{@tenant}")}>
      <.live_component
        module={SecureSharingWeb.Admin.TenantLive.FormComponent}
        id={@tenant.id}
        title="Edit Tenant"
        action={@live_action}
        tenant={@tenant}
        patch={~p"/admin/tenants/#{@tenant}"}
      />
    </.modal>
    """
  end

  defp role_color(:owner), do: :blue
  defp role_color(:admin), do: :yellow
  defp role_color(:member), do: :gray
  defp role_color(_), do: :gray

  defp format_date(nil), do: "N/A"

  defp format_date(%DateTime{} = datetime) do
    Calendar.strftime(datetime, "%b %d, %Y")
  end

  defp format_date(%NaiveDateTime{} = datetime) do
    Calendar.strftime(datetime, "%b %d, %Y")
  end

  defp format_date(_), do: "N/A"

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
