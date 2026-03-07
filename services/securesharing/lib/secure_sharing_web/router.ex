defmodule SecureSharingWeb.Router do
  use SecureSharingWeb, :router

  alias SecureSharingWeb.Plugs.{Authenticate, RateLimit}

  # Base API pipeline
  pipeline :api do
    plug :accepts, ["json"]
    plug SecureSharingWeb.Plugs.SecurityHeaders
  end

  # Authenticated API pipeline (SSDID session token)
  pipeline :api_auth do
    plug :accepts, ["json"]
    plug Authenticate
  end

  # Browser pipeline for admin portal
  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {SecureSharingWeb.Layouts, :root}
    plug :protect_from_forgery

    plug :put_secure_browser_headers, %{
      "x-frame-options" => "DENY",
      "x-content-type-options" => "nosniff",
      "referrer-policy" => "strict-origin-when-cross-origin",
      "permissions-policy" => "camera=(), microphone=(), geolocation=()"
    }
  end

  # Admin authentication pipeline
  pipeline :admin_auth do
    plug :fetch_admin_user
  end

  # Rate limiting for auth endpoints (5 per minute)
  pipeline :rate_limit_auth do
    plug RateLimit, scale: 60_000, limit: 5
  end

  # Rate limiting for general API (100 per minute)
  pipeline :rate_limit_api do
    plug RateLimit, scale: 60_000, limit: 100
  end

  # Landing page
  scope "/", SecureSharingWeb do
    pipe_through [:browser]

    live "/", LandingLive, :index
  end

  # Health check endpoints (no rate limiting for load balancers/K8s probes)
  scope "/health", SecureSharingWeb do
    pipe_through [:api]

    get "/", HealthController, :index
    get "/ready", HealthController, :ready
    get "/cluster", HealthController, :cluster
    get "/detailed", HealthController, :detailed
  end

  # ==========================================================================
  # SSDID Authentication (public — no session required)
  # ==========================================================================
  scope "/api/auth/ssdid", SecureSharingWeb.API do
    pipe_through [:api, :rate_limit_auth]

    # Server identity discovery (for mobile client to get server DID)
    get "/server-info", SsdidAuthController, :server_info

    # Mutual authentication flow
    post "/register", SsdidAuthController, :register
    post "/register/verify", SsdidAuthController, :verify
    post "/authenticate", SsdidAuthController, :authenticate
  end

  # Public invitation endpoints
  scope "/api", SecureSharingWeb.API do
    pipe_through [:api, :rate_limit_auth]

    get "/invite/:token", InviteController, :show
    post "/invite/:token/accept", InviteController, :accept
  end

  # ==========================================================================
  # Protected endpoints (SSDID session token required)
  # ==========================================================================
  scope "/api", SecureSharingWeb.API do
    pipe_through [:api_auth, :rate_limit_api]

    # SSDID session management
    post "/auth/ssdid/logout", SsdidAuthController, :logout
    post "/auth/ssdid/tenant/switch", SsdidAuthController, :switch_tenant

    # Multi-tenant user management
    get "/tenants", TenantController, :index
    delete "/tenants/:id/leave", TenantController, :leave

    # Tenant member management (admin/owner only)
    get "/tenants/:tenant_id/members", TenantController, :list_members
    post "/tenants/:tenant_id/members", TenantController, :invite_member
    put "/tenants/:tenant_id/members/:user_id/role", TenantController, :update_member_role
    delete "/tenants/:tenant_id/members/:user_id", TenantController, :remove_member

    # Invitations (for current user - existing tenant invitations)
    get "/invitations", TenantController, :list_invitations
    post "/invitations/:id/accept", TenantController, :accept_invitation
    post "/invitations/:id/decline", TenantController, :decline_invitation

    # Invitation management (admin - for new user invitations)
    get "/tenant/invitations", InvitationController, :index
    post "/tenant/invitations", InvitationController, :create
    get "/tenant/invitations/:id", InvitationController, :show
    delete "/tenant/invitations/:id", InvitationController, :revoke
    post "/tenant/invitations/:id/resend", InvitationController, :resend

    # Tenant configuration
    get "/tenant/config", TenantController, :config

    # Current user
    get "/me", UserController, :show
    put "/me", UserController, :update
    get "/me/keys", UserController, :key_bundle
    put "/me/keys", UserController, :update_keys

    # Users (for sharing — resolve DID to public key)
    get "/users", UserController, :index
    get "/users/:id/public-key", UserController, :public_key

    # Devices
    post "/devices/enroll", DeviceController, :enroll
    get "/devices", DeviceController, :index
    get "/devices/:id", DeviceController, :show
    put "/devices/:id", DeviceController, :update
    delete "/devices/:id", DeviceController, :delete
    post "/devices/:id/push", DeviceController, :register_push
    delete "/devices/:id/push", DeviceController, :unregister_push
    post "/devices/:id/attest", DeviceController, :attest

    # Folders
    get "/folders/root", FolderController, :root
    get "/folders", FolderController, :index
    post "/folders", FolderController, :create
    get "/folders/:id", FolderController, :show
    put "/folders/:id", FolderController, :update
    delete "/folders/:id", FolderController, :delete
    post "/folders/:id/move", FolderController, :move
    post "/folders/:id/transfer-ownership", FolderController, :transfer_ownership
    get "/folders/:id/audit-log", AuditController, :folder_audit_log
    get "/folders/:folder_id/children", FolderController, :children
    get "/folders/:folder_id/files", FileController, :index

    # Files
    get "/files/accessible", FileController, :accessible
    get "/files/:id", FileController, :show
    put "/files/:id", FileController, :update
    delete "/files/:id", FileController, :delete
    post "/files/upload-url", FileController, :upload_url
    get "/files/:id/download-url", FileController, :download_url
    post "/files/:id/move", FileController, :move
    post "/files/:id/transfer-ownership", FileController, :transfer_ownership
    get "/files/:id/audit-log", AuditController, :file_audit_log

    # Shares
    get "/shares/received", ShareController, :received
    get "/shares/created", ShareController, :created
    post "/shares/file", ShareController, :share_file
    post "/shares/folder", ShareController, :share_folder
    get "/shares/upgrade-requests", AccessRequestController, :pending
    get "/shares/my-upgrade-requests", AccessRequestController, :my_requests
    get "/shares/:id", ShareController, :show
    put "/shares/:id/permission", ShareController, :update_permission
    put "/shares/:id/expiry", ShareController, :set_expiry
    post "/shares/:id/request-upgrade", AccessRequestController, :request_upgrade
    post "/shares/:id/approve-upgrade", AccessRequestController, :approve
    post "/shares/:id/deny-upgrade", AccessRequestController, :deny
    delete "/shares/:id", ShareController, :revoke

    # Recovery configuration
    get "/recovery/config", RecoveryController, :show_config
    post "/recovery/setup", RecoveryController, :setup
    delete "/recovery/config", RecoveryController, :disable

    # Recovery shares (trustee distribution)
    post "/recovery/shares", RecoveryController, :create_share
    get "/recovery/shares/trustee", RecoveryController, :trustee_shares
    get "/recovery/shares/created", RecoveryController, :owner_shares
    post "/recovery/shares/:id/accept", RecoveryController, :accept_share
    post "/recovery/shares/:id/reject", RecoveryController, :reject_share
    delete "/recovery/shares/:id", RecoveryController, :revoke_share

    # Recovery requests
    post "/recovery/request", RecoveryController, :create_request
    get "/recovery/requests", RecoveryController, :list_requests
    get "/recovery/requests/pending", RecoveryController, :pending_for_trustee
    get "/recovery/requests/:id", RecoveryController, :show_request
    post "/recovery/requests/:id/approve", RecoveryController, :approve
    post "/recovery/requests/:id/complete", RecoveryController, :complete
    delete "/recovery/requests/:id", RecoveryController, :cancel

    # Audit log
    get "/audit-log", AuditController, :index

    # Notifications
    get "/notifications", NotificationController, :index
    get "/notifications/unread_count", NotificationController, :unread_count
    post "/notifications/:id/read", NotificationController, :mark_read
    post "/notifications/read_all", NotificationController, :mark_all_read
    delete "/notifications/:id", NotificationController, :delete
  end

  # Admin login and setup (no auth required)
  scope "/admin", SecureSharingWeb.Admin do
    pipe_through [:browser]

    live "/login", LoginLive, :index
    live "/setup", SetupLive, :index
  end

  # Admin portal (authentication required)
  scope "/admin", SecureSharingWeb.Admin do
    pipe_through [:browser, :admin_auth]

    live_session :admin,
      on_mount: [{SecureSharingWeb.AdminAuth, :default}] do
      live "/", DashboardLive, :index

      live "/tenants", TenantLive.Index, :index
      live "/tenants/new", TenantLive.Index, :new
      live "/tenants/:id/edit", TenantLive.Index, :edit
      live "/tenants/:id", TenantLive.Show, :show
      live "/tenants/:id/show/edit", TenantLive.Show, :edit

      live "/users", UserLive.Index, :index
      live "/users/:id", UserLive.Show, :show

      live "/invitations", InvitationLive.Index, :index

      live "/notifications", NotificationLive, :index

      live "/audit", AuditLive, :index
    end
  end

  # Enable LiveDashboard and Swoosh Mailbox in development
  if Application.compile_env(:secure_sharing, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through [:fetch_session, :protect_from_forgery]

      live_dashboard "/dashboard", metrics: SecureSharingWeb.Telemetry

      # Swoosh mailbox preview - view sent emails at /dev/mailbox
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  # Helper function plugs

  defp fetch_admin_user(conn, _opts) do
    user_id = conn.params["user_id"] || get_session(conn, :admin_user_id)

    if user_id do
      case SecureSharing.Accounts.get_user(user_id) do
        nil ->
          redirect_to_login(conn)

        user ->
          if user.is_admin do
            conn
            |> put_session(:admin_user_id, user.id)
            |> assign(:current_user, user)
          else
            redirect_to_login(conn, "You are not authorized to access the admin panel.")
          end
      end
    else
      redirect_to_login(conn)
    end
  end

  defp redirect_to_login(conn, message \\ "Please log in to access the admin panel.") do
    conn
    |> Phoenix.Controller.put_flash(:error, message)
    |> Phoenix.Controller.redirect(to: "/admin/login")
    |> halt()
  end
end
