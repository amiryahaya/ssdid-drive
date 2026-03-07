defmodule SecureSharingWeb.Admin.InvitationLive.Index do
  @moduledoc """
  LiveView for managing invitations across all tenants.

  Allows platform admins to:
  - View all invitations with status filtering
  - Create new invitations for any tenant
  - Revoke pending invitations
  - Resend invitation emails
  """
  use SecureSharingWeb, :live_view

  alias SecureSharing.Accounts
  alias SecureSharing.Invitations

  @impl true
  def mount(_params, _session, socket) do
    tenants = Accounts.list_tenants()

    {:ok,
     socket
     |> assign(:page_title, "Invitations")
     |> assign(:tenants, tenants)
     |> assign(:status_filter, nil)
     |> assign(:show_form, false)
     |> assign(
       :form,
       to_form(%{"email" => "", "role" => "member", "tenant_id" => "", "message" => ""},
         as: :invitation
       )
     )
     |> assign(:form_error, nil)
     |> stream(:invitations, Invitations.list_all_invitations())}
  end

  @impl true
  def handle_params(params, _url, socket) do
    status_filter = params["status"]

    invitations =
      if status_filter && status_filter != "" do
        Invitations.list_all_invitations(status: String.to_existing_atom(status_filter))
      else
        Invitations.list_all_invitations()
      end

    {:noreply,
     socket
     |> assign(:status_filter, status_filter)
     |> stream(:invitations, invitations, reset: true)}
  end

  @impl true
  def handle_event("filter", %{"status" => status}, socket) do
    params = if status == "", do: %{}, else: %{"status" => status}
    {:noreply, push_patch(socket, to: ~p"/admin/invitations?#{params}")}
  end

  @impl true
  def handle_event("show_form", _params, socket) do
    {:noreply, assign(socket, :show_form, true)}
  end

  @impl true
  def handle_event("hide_form", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_form, false)
     |> assign(:form_error, nil)
     |> assign(
       :form,
       to_form(%{"email" => "", "role" => "member", "tenant_id" => "", "message" => ""},
         as: :invitation
       )
     )}
  end

  @impl true
  def handle_event("validate", %{"invitation" => params}, socket) do
    {:noreply, assign(socket, :form, to_form(params, as: :invitation))}
  end

  @impl true
  def handle_event("create", %{"invitation" => params}, socket) do
    current_user = socket.assigns.current_user
    tenant_id = params["tenant_id"]

    if tenant_id == "" do
      {:noreply, assign(socket, :form_error, "Please select a tenant")}
    else
      case Invitations.create_invitation(current_user, %{
             email: params["email"],
             role: params["role"],
             message: params["message"],
             tenant_id: tenant_id
           }) do
        {:ok, invitation} ->
          # Reload with preloads
          invitation =
            Invitations.get_invitation(invitation.id)
            |> SecureSharing.Repo.preload([:inviter, :accepted_by, :tenant])

          {:noreply,
           socket
           |> stream_insert(:invitations, invitation, at: 0)
           |> assign(:show_form, false)
           |> assign(:form_error, nil)
           |> assign(
             :form,
             to_form(%{"email" => "", "role" => "member", "tenant_id" => "", "message" => ""},
               as: :invitation
             )
           )
           |> put_flash(:info, "Invitation sent to #{invitation.email}")}

        {:error, :not_authorized} ->
          {:noreply, assign(socket, :form_error, "You are not authorized to send invitations")}

        {:error, :email_already_registered} ->
          {:noreply,
           assign(socket, :form_error, "This email is already registered in the selected tenant")}

        {:error, :pending_invitation_exists} ->
          {:noreply,
           assign(socket, :form_error, "A pending invitation already exists for this email")}

        {:error, %Ecto.Changeset{} = changeset} ->
          error_msg =
            changeset.errors
            |> Enum.map(fn {field, {msg, _}} -> "#{field}: #{msg}" end)
            |> Enum.join(", ")

          {:noreply, assign(socket, :form_error, error_msg)}
      end
    end
  end

  @impl true
  def handle_event("revoke", %{"id" => id}, socket) do
    invitation = Invitations.get_invitation!(id)

    case Invitations.revoke_invitation(invitation) do
      {:ok, updated_invitation} ->
        updated_invitation =
          SecureSharing.Repo.preload(updated_invitation, [:inviter, :accepted_by, :tenant])

        {:noreply,
         socket
         |> stream_insert(:invitations, updated_invitation)
         |> put_flash(:info, "Invitation revoked")}

      {:error, :cannot_revoke} ->
        {:noreply, put_flash(socket, :error, "Cannot revoke this invitation")}
    end
  end

  @impl true
  def handle_event("resend", %{"id" => id}, socket) do
    invitation = Invitations.get_invitation!(id)

    case Invitations.resend_invitation(invitation) do
      {:ok, updated_invitation} ->
        updated_invitation =
          SecureSharing.Repo.preload(updated_invitation, [:inviter, :accepted_by, :tenant])

        {:noreply,
         socket
         |> stream_insert(:invitations, updated_invitation)
         |> put_flash(:info, "Invitation resent to #{invitation.email}")}

      {:error, :cannot_resend} ->
        {:noreply, put_flash(socket, :error, "Cannot resend this invitation")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.header>
      Invitations
      <:subtitle>Manage user invitations across all tenants</:subtitle>
      <:actions>
        <.button phx-click="show_form">
          New Invitation
        </.button>
      </:actions>
    </.header>

    <div class="mt-4 mb-6">
      <form phx-change="filter" class="flex items-center gap-4">
        <label class="text-sm font-medium text-gray-700">Filter by status:</label>
        <select name="status" class="rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm">
          <option value="" selected={@status_filter == nil}>All</option>
          <option value="pending" selected={@status_filter == "pending"}>Pending</option>
          <option value="accepted" selected={@status_filter == "accepted"}>Accepted</option>
          <option value="expired" selected={@status_filter == "expired"}>Expired</option>
          <option value="revoked" selected={@status_filter == "revoked"}>Revoked</option>
        </select>
      </form>
    </div>

    <.table
      id="invitations"
      rows={@streams.invitations}
    >
      <:col :let={{_id, invitation}} label="Email">{invitation.email}</:col>
      <:col :let={{_id, invitation}} label="Tenant">
        <.link :if={invitation.tenant} navigate={~p"/admin/tenants/#{invitation.tenant_id}"} class="text-blue-600 hover:text-blue-500">
          {invitation.tenant.name}
        </.link>
      </:col>
      <:col :let={{_id, invitation}} label="Role">
        <.badge color={role_color(invitation.role)}>{invitation.role}</.badge>
      </:col>
      <:col :let={{_id, invitation}} label="Status">
        <.badge color={status_color(invitation.status)}>{invitation.status}</.badge>
      </:col>
      <:col :let={{_id, invitation}} label="Inviter">
        {invitation.inviter && invitation.inviter.email}
      </:col>
      <:col :let={{_id, invitation}} label="Expires">
        {format_datetime(invitation.expires_at)}
      </:col>
      <:col :let={{_id, invitation}} label="Created">
        {format_datetime(invitation.created_at)}
      </:col>
      <:action :let={{_id, invitation}}>
        <.link
          :if={invitation.status == :pending}
          phx-click={JS.push("resend", value: %{id: invitation.id})}
          class="text-blue-600 hover:text-blue-500"
        >
          Resend
        </.link>
      </:action>
      <:action :let={{_id, invitation}}>
        <.link
          :if={invitation.status == :pending}
          phx-click={JS.push("revoke", value: %{id: invitation.id})}
          data-confirm="Are you sure you want to revoke this invitation?"
          class="text-red-600 hover:text-red-500"
        >
          Revoke
        </.link>
      </:action>
    </.table>

    <.modal :if={@show_form} id="invitation-modal" show on_cancel={JS.push("hide_form")}>
      <.header>
        Send Invitation
        <:subtitle>Invite a new user to join a tenant</:subtitle>
      </.header>

      <.simple_form for={@form} phx-change="validate" phx-submit="create" class="mt-4">
        <.input
          field={@form[:tenant_id]}
          type="select"
          label="Tenant"
          prompt="Select a tenant"
          options={Enum.map(@tenants, &{&1.name, &1.id})}
          required
        />

        <.input
          field={@form[:email]}
          type="email"
          label="Email Address"
          placeholder="user@example.com"
          required
        />

        <.input
          field={@form[:role]}
          type="select"
          label="Role"
          options={[{"Member", "member"}, {"Admin", "admin"}, {"Manager", "manager"}]}
        />

        <.input
          field={@form[:message]}
          type="textarea"
          label="Personal Message (optional)"
          placeholder="Welcome to our team!"
        />

        <div :if={@form_error} class="mt-2 p-3 bg-red-50 rounded-md">
          <p class="text-sm text-red-800">{@form_error}</p>
        </div>

        <:actions>
          <.button type="button" phx-click="hide_form" class="bg-gray-200 text-gray-800 hover:bg-gray-300">
            Cancel
          </.button>
          <.button type="submit" phx-disable-with="Sending...">
            Send Invitation
          </.button>
        </:actions>
      </.simple_form>
    </.modal>
    """
  end

  defp status_color(:pending), do: :yellow
  defp status_color(:accepted), do: :green
  defp status_color(:expired), do: :gray
  defp status_color(:revoked), do: :red
  defp status_color(_), do: :gray

  defp role_color(:admin), do: :blue
  defp role_color(:manager), do: :purple
  defp role_color(:member), do: :gray
  defp role_color(_), do: :gray

  defp format_datetime(nil), do: "-"

  defp format_datetime(datetime) do
    Calendar.strftime(datetime, "%b %d, %Y %H:%M")
  end
end
