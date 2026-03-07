defmodule SecureSharingWeb.Admin.LoginLive do
  @moduledoc """
  LiveView for admin login.
  """
  use SecureSharingWeb, :live_view

  alias SecureSharing.Accounts

  @impl true
  def mount(_params, _session, socket) do
    # Redirect to setup if no admin exists
    if !Accounts.admin_exists?() do
      {:ok,
       socket
       |> push_navigate(to: ~p"/admin/setup"), layout: {SecureSharingWeb.Layouts, :auth}}
    else
      {:ok,
       socket
       |> assign(:page_title, "Admin Login")
       |> assign(:form, to_form(%{"email" => "", "password" => ""}, as: :user))
       |> assign(:error, nil), layout: {SecureSharingWeb.Layouts, :auth}}
    end
  end

  @impl true
  def handle_event("login", %{"user" => %{"email" => email, "password" => password}}, socket) do
    case Accounts.authenticate_user(email, password) do
      {:ok, user} ->
        if user.is_admin do
          # Put user in session and redirect
          {:noreply,
           socket
           |> put_flash(:info, "Welcome back, #{user.email}!")
           |> push_navigate(to: ~p"/admin?user_id=#{user.id}")}
        else
          {:noreply, assign(socket, :error, "You are not authorized to access the admin panel.")}
        end

      {:error, :invalid_credentials} ->
        {:noreply, assign(socket, :error, "Invalid email or password.")}

      {:error, :ambiguous_tenant} ->
        {:noreply, assign(socket, :error, "Please specify your tenant when logging in.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen flex items-center justify-center bg-gray-100 py-12 px-4 sm:px-6 lg:px-8">
      <div class="max-w-md w-full space-y-8">
        <div>
          <h2 class="mt-6 text-center text-3xl font-extrabold text-gray-900">
            SecureSharing Admin
          </h2>
          <p class="mt-2 text-center text-sm text-gray-600">
            Sign in to access the admin dashboard
          </p>
        </div>

        <div :if={@error} class="rounded-md bg-red-50 p-4">
          <div class="flex">
            <div class="flex-shrink-0">
              <span class="text-red-400">X</span>
            </div>
            <div class="ml-3">
              <p class="text-sm font-medium text-red-800">{@error}</p>
            </div>
          </div>
        </div>

        <form class="mt-8 space-y-6" phx-submit="login">
          <div class="rounded-md shadow-sm -space-y-px">
            <div>
              <label for="email" class="sr-only">Email address</label>
              <input
                id="email"
                name="user[email]"
                type="email"
                autocomplete="email"
                required
                class="appearance-none rounded-none relative block w-full px-3 py-2 border border-gray-300 placeholder-gray-500 text-gray-900 rounded-t-md focus:outline-none focus:ring-blue-500 focus:border-blue-500 focus:z-10 sm:text-sm"
                placeholder="Email address"
              />
            </div>
            <div>
              <label for="password" class="sr-only">Password</label>
              <input
                id="password"
                name="user[password]"
                type="password"
                autocomplete="current-password"
                required
                class="appearance-none rounded-none relative block w-full px-3 py-2 border border-gray-300 placeholder-gray-500 text-gray-900 rounded-b-md focus:outline-none focus:ring-blue-500 focus:border-blue-500 focus:z-10 sm:text-sm"
                placeholder="Password"
              />
            </div>
          </div>

          <div>
            <button
              type="submit"
              class="group relative w-full flex justify-center py-2 px-4 border border-transparent text-sm font-medium rounded-md text-white bg-blue-600 hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500"
            >
              Sign in
            </button>
          </div>
        </form>

      </div>
    </div>
    """
  end
end
