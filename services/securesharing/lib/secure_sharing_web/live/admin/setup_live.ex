defmodule SecureSharingWeb.Admin.SetupLive do
  @moduledoc """
  LiveView for initial admin bootstrap setup.

  This page is only accessible when no admin users exist in the system.
  It allows creating the first admin user during initial deployment.
  """
  use SecureSharingWeb, :live_view

  alias SecureSharing.Accounts

  @impl true
  def mount(_params, _session, socket) do
    # Redirect to login if admin already exists
    if Accounts.admin_exists?() do
      {:ok,
       socket
       |> put_flash(:info, "Admin account already exists. Please log in.")
       |> push_navigate(to: ~p"/admin/login"), layout: {SecureSharingWeb.Layouts, :auth}}
    else
      setup_token_required = setup_token_configured?()

      {:ok,
       socket
       |> assign(:page_title, "Admin Setup")
       |> assign(
         :form,
         to_form(
           %{"email" => "", "password" => "", "password_confirmation" => "", "setup_token" => ""},
           as: :admin
         )
       )
       |> assign(:error, nil)
       |> assign(:setup_token_required, setup_token_required)
       |> assign(:submitting, false)
       |> assign(:show_password, false), layout: {SecureSharingWeb.Layouts, :auth}}
    end
  end

  @impl true
  def handle_event("toggle_password", _params, socket) do
    {:noreply, assign(socket, show_password: !socket.assigns.show_password)}
  end

  @impl true
  def handle_event("validate", %{"admin" => params}, socket) do
    form = to_form(params, as: :admin)
    {:noreply, assign(socket, form: form, error: nil)}
  end

  @impl true
  def handle_event("create", %{"admin" => params}, socket) do
    # Preserve form values first
    form = to_form(params, as: :admin)
    socket = assign(socket, form: form, submitting: true, error: nil)

    # Validate setup token if configured
    result =
      with :ok <- validate_setup_token(params["setup_token"]),
           :ok <-
             validate_password_confirmation(params["password"], params["password_confirmation"]),
           {:ok, _user} <- create_admin(params) do
        :ok
      end

    case result do
      :ok ->
        {:noreply,
         socket
         |> put_flash(:info, "Admin account created successfully! Please log in.")
         |> push_navigate(to: ~p"/admin/login")}

      {:error, :invalid_setup_token} ->
        {:noreply, assign(socket, error: "Invalid setup token.", submitting: false)}

      {:error, :password_mismatch} ->
        {:noreply, assign(socket, error: "Passwords do not match.", submitting: false)}

      {:error, %Ecto.Changeset{} = changeset} ->
        error = format_changeset_errors(changeset)
        {:noreply, assign(socket, error: error, submitting: false)}

      {:error, reason} ->
        {:noreply,
         assign(socket, error: "Failed to create admin: #{inspect(reason)}", submitting: false)}
    end
  end

  defp validate_setup_token(provided_token) do
    case get_configured_token() do
      nil ->
        :ok

      "" ->
        :ok

      configured_token ->
        if Plug.Crypto.secure_compare(configured_token, provided_token || "") do
          :ok
        else
          {:error, :invalid_setup_token}
        end
    end
  end

  defp validate_password_confirmation(password, confirmation) do
    if password == confirmation do
      :ok
    else
      {:error, :password_mismatch}
    end
  end

  defp create_admin(params) do
    Accounts.create_admin_user(%{
      email: params["email"],
      password: params["password"]
    })
  end

  defp format_changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
    |> Enum.map(fn {field, errors} -> "#{field}: #{Enum.join(errors, ", ")}" end)
    |> Enum.join("; ")
  end

  defp setup_token_configured? do
    case get_configured_token() do
      nil -> false
      "" -> false
      _ -> true
    end
  end

  defp get_configured_token do
    Application.get_env(:secure_sharing, :admin_setup, [])
    |> Keyword.get(:setup_token)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen flex items-center justify-center bg-gray-100 py-12 px-4 sm:px-6 lg:px-8">
      <div class="max-w-md w-full space-y-8">
        <div>
          <h2 class="mt-6 text-center text-3xl font-extrabold text-gray-900">
            SecureSharing Admin Setup
          </h2>
          <p class="mt-2 text-center text-sm text-gray-600">
            Create the first administrator account
          </p>
        </div>

        <!-- Security Notice -->
        <div class="rounded-md bg-blue-50 p-4">
          <div class="flex">
            <div class="flex-shrink-0">
              <svg class="h-5 w-5 text-blue-400" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor">
                <path fill-rule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7-4a1 1 0 11-2 0 1 1 0 012 0zM9 9a1 1 0 000 2v3a1 1 0 001 1h1a1 1 0 100-2v-3a1 1 0 00-1-1H9z" clip-rule="evenodd" />
              </svg>
            </div>
            <div class="ml-3">
              <p class="text-sm text-blue-700">
                This is a one-time setup. After creating the admin account, this page will no longer be accessible.
              </p>
            </div>
          </div>
        </div>

        <!-- Error Message -->
        <div :if={@error} class="rounded-md bg-red-50 p-4">
          <div class="flex">
            <div class="flex-shrink-0">
              <svg class="h-5 w-5 text-red-400" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor">
                <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.707 7.293a1 1 0 00-1.414 1.414L8.586 10l-1.293 1.293a1 1 0 101.414 1.414L10 11.414l1.293 1.293a1 1 0 001.414-1.414L11.414 10l1.293-1.293a1 1 0 00-1.414-1.414L10 8.586 8.707 7.293z" clip-rule="evenodd" />
              </svg>
            </div>
            <div class="ml-3">
              <p class="text-sm font-medium text-red-800">{@error}</p>
            </div>
          </div>
        </div>

        <form class="mt-8 space-y-6" phx-change="validate" phx-submit="create" novalidate>
          <div class="space-y-4">
            <!-- Setup Token (if required) -->
            <div :if={@setup_token_required}>
              <label for="setup_token" class="block text-sm font-medium text-gray-700">
                Setup Token
              </label>
              <input
                id="setup_token"
                name="admin[setup_token]"
                type="password"
                required
                value={@form[:setup_token].value}
                class="mt-1 appearance-none relative block w-full px-3 py-2 border border-gray-300 placeholder-gray-500 text-gray-900 rounded-md focus:outline-none focus:ring-blue-500 focus:border-blue-500 sm:text-sm"
                placeholder="Enter setup token"
              />
              <p class="mt-1 text-xs text-gray-500">
                The setup token is required for security. Contact your system administrator.
              </p>
            </div>

            <!-- Email -->
            <div>
              <label for="email" class="block text-sm font-medium text-gray-700">
                Email Address
              </label>
              <input
                id="email"
                name="admin[email]"
                type="email"
                autocomplete="email"
                required
                value={@form[:email].value}
                class="mt-1 appearance-none relative block w-full px-3 py-2 border border-gray-300 placeholder-gray-500 text-gray-900 rounded-md focus:outline-none focus:ring-blue-500 focus:border-blue-500 sm:text-sm"
                placeholder="admin@example.com"
              />
            </div>

            <!-- Password -->
            <div>
              <label for="password" class="block text-sm font-medium text-gray-700">
                Password
              </label>
              <div class="mt-1 relative">
                <input
                  id="password"
                  name="admin[password]"
                  type={if @show_password, do: "text", else: "password"}
                  autocomplete="new-password"
                  value={@form[:password].value}
                  class="appearance-none relative block w-full px-3 py-2 pr-10 border border-gray-300 placeholder-gray-500 text-gray-900 rounded-md focus:outline-none focus:ring-blue-500 focus:border-blue-500 sm:text-sm"
                  placeholder="Minimum 12 characters"
                />
                <button
                  type="button"
                  phx-click="toggle_password"
                  class="absolute inset-y-0 right-0 pr-3 flex items-center text-gray-400 hover:text-gray-600"
                >
                  <!-- Eye icon (show password) -->
                  <svg :if={!@show_password} class="h-5 w-5" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor">
                    <path d="M10 12a2 2 0 100-4 2 2 0 000 4z" />
                    <path fill-rule="evenodd" d="M.458 10C1.732 5.943 5.522 3 10 3s8.268 2.943 9.542 7c-1.274 4.057-5.064 7-9.542 7S1.732 14.057.458 10zM14 10a4 4 0 11-8 0 4 4 0 018 0z" clip-rule="evenodd" />
                  </svg>
                  <!-- Eye-off icon (hide password) -->
                  <svg :if={@show_password} class="h-5 w-5" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor">
                    <path fill-rule="evenodd" d="M3.707 2.293a1 1 0 00-1.414 1.414l14 14a1 1 0 001.414-1.414l-1.473-1.473A10.014 10.014 0 0019.542 10C18.268 5.943 14.478 3 10 3a9.958 9.958 0 00-4.512 1.074l-1.78-1.781zm4.261 4.26l1.514 1.515a2.003 2.003 0 012.45 2.45l1.514 1.514a4 4 0 00-5.478-5.478z" clip-rule="evenodd" />
                    <path d="M12.454 16.697L9.75 13.992a4 4 0 01-3.742-3.741L2.335 6.578A9.98 9.98 0 00.458 10c1.274 4.057 5.065 7 9.542 7 .847 0 1.669-.105 2.454-.303z" />
                  </svg>
                </button>
              </div>
              <p class="mt-1 text-xs text-gray-500">
                Use a strong password with at least 12 characters
              </p>
            </div>

            <!-- Password Confirmation -->
            <div>
              <label for="password_confirmation" class="block text-sm font-medium text-gray-700">
                Confirm Password
              </label>
              <div class="mt-1 relative">
                <input
                  id="password_confirmation"
                  name="admin[password_confirmation]"
                  type={if @show_password, do: "text", else: "password"}
                  autocomplete="new-password"
                  value={@form[:password_confirmation].value}
                  class="appearance-none relative block w-full px-3 py-2 pr-10 border border-gray-300 placeholder-gray-500 text-gray-900 rounded-md focus:outline-none focus:ring-blue-500 focus:border-blue-500 sm:text-sm"
                  placeholder="Confirm your password"
                />
                <button
                  type="button"
                  phx-click="toggle_password"
                  class="absolute inset-y-0 right-0 pr-3 flex items-center text-gray-400 hover:text-gray-600"
                >
                  <!-- Eye icon (show password) -->
                  <svg :if={!@show_password} class="h-5 w-5" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor">
                    <path d="M10 12a2 2 0 100-4 2 2 0 000 4z" />
                    <path fill-rule="evenodd" d="M.458 10C1.732 5.943 5.522 3 10 3s8.268 2.943 9.542 7c-1.274 4.057-5.064 7-9.542 7S1.732 14.057.458 10zM14 10a4 4 0 11-8 0 4 4 0 018 0z" clip-rule="evenodd" />
                  </svg>
                  <!-- Eye-off icon (hide password) -->
                  <svg :if={@show_password} class="h-5 w-5" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor">
                    <path fill-rule="evenodd" d="M3.707 2.293a1 1 0 00-1.414 1.414l14 14a1 1 0 001.414-1.414l-1.473-1.473A10.014 10.014 0 0019.542 10C18.268 5.943 14.478 3 10 3a9.958 9.958 0 00-4.512 1.074l-1.78-1.781zm4.261 4.26l1.514 1.515a2.003 2.003 0 012.45 2.45l1.514 1.514a4 4 0 00-5.478-5.478z" clip-rule="evenodd" />
                    <path d="M12.454 16.697L9.75 13.992a4 4 0 01-3.742-3.741L2.335 6.578A9.98 9.98 0 00.458 10c1.274 4.057 5.065 7 9.542 7 .847 0 1.669-.105 2.454-.303z" />
                  </svg>
                </button>
              </div>
            </div>
          </div>

          <div>
            <button
              type="submit"
              disabled={@submitting}
              class="group relative w-full flex justify-center py-2 px-4 border border-transparent text-sm font-medium rounded-md text-white bg-blue-600 hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500 disabled:opacity-50 disabled:cursor-not-allowed"
            >
              <svg
                :if={@submitting}
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
              {if @submitting, do: "Creating Account...", else: "Create Admin Account"}
            </button>
          </div>
        </form>

        <div class="text-center">
          <.link navigate={~p"/admin/login"} class="text-sm text-blue-600 hover:text-blue-500">
            Already have an admin account? Sign in
          </.link>
        </div>
      </div>
    </div>
    """
  end
end
