defmodule SecureSharingWeb.Admin.TenantLive.FormComponent do
  @moduledoc """
  LiveComponent for creating/editing tenants.
  """
  use SecureSharingWeb, :live_component

  alias SecureSharing.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        {@title}
        <:subtitle>Use this form to manage tenant records.</:subtitle>
      </.header>

      <.simple_form
        for={@form}
        id="tenant-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <.input field={@form[:name]} type="text" label="Name" />
        <.input field={@form[:slug]} type="text" label="Slug" />
        <.input
          field={@form[:storage_quota_bytes]}
          type="number"
          label="Storage Quota (bytes)"
        />
        <.input field={@form[:max_users]} type="number" label="Max Users" />
        <.input
          field={@form[:pqc_algorithm]}
          type="select"
          label="PQC Algorithm"
          options={[{"Default (kaz)", nil}, {"kaz", "kaz"}, {"ml", "ml"}]}
        />
        <:actions>
          <.button phx-disable-with="Saving...">Save Tenant</.button>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  @impl true
  def update(%{tenant: tenant} = assigns, socket) do
    changeset = Accounts.Tenant.changeset(tenant, %{})

    {:ok,
     socket
     |> assign(assigns)
     |> assign_form(changeset)}
  end

  @impl true
  def handle_event("validate", %{"tenant" => tenant_params}, socket) do
    changeset =
      socket.assigns.tenant
      |> Accounts.Tenant.changeset(tenant_params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"tenant" => tenant_params}, socket) do
    save_tenant(socket, socket.assigns.action, tenant_params)
  end

  defp save_tenant(socket, :edit, tenant_params) do
    case Accounts.update_tenant(socket.assigns.tenant, tenant_params) do
      {:ok, tenant} ->
        notify_parent({:saved, tenant})

        {:noreply,
         socket
         |> put_flash(:info, "Tenant updated successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_tenant(socket, :new, tenant_params) do
    case Accounts.create_tenant(tenant_params) do
      {:ok, tenant} ->
        notify_parent({:saved, tenant})

        {:noreply,
         socket
         |> put_flash(:info, "Tenant created successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset))
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})
end
