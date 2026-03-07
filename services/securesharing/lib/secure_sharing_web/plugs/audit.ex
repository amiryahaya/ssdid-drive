defmodule SecureSharingWeb.Plugs.Audit do
  @moduledoc """
  Plug for automatic audit logging of API requests.

  Can be used in controller pipelines to automatically log actions
  based on the controller action being executed.

  ## Usage

  In your controller:

      plug SecureSharingWeb.Plugs.Audit, resource_type: "file"
      plug SecureSharingWeb.Plugs.Audit, resource_type: "folder" when action in [:create, :update, :delete]

  Or in the router:

      pipe_through [:api, :authenticated, {:audit, resource_type: "file"}]
  """

  import Plug.Conn
  alias SecureSharing.Audit

  @action_mapping %{
    # Standard CRUD actions
    create: "create",
    show: "read",
    index: "read",
    update: "update",
    delete: "delete",
    # File-specific actions
    upload_url: "create",
    download_url: "download",
    move: "move",
    # Share actions
    share_file: "create",
    share_folder: "create",
    revoke: "revoke",
    update_permission: "update",
    update_expiry: "update",
    received: "read",
    created: "read",
    # Recovery actions
    setup: "setup",
    accept_share: "share_accept",
    request: "request",
    approve: "approve",
    complete: "complete",
    pending_requests: "read"
  }

  def init(opts), do: opts

  def call(conn, opts) do
    resource_type = Keyword.get(opts, :resource_type, "system")

    register_before_send(conn, fn conn ->
      log_action(conn, resource_type)
      conn
    end)
  end

  defp log_action(conn, resource_type) do
    # Only log if we have a tenant context
    if get_tenant_id(conn) do
      action = build_action(conn, resource_type)
      resource_id = get_resource_id(conn)
      status = if conn.status in 200..299, do: "success", else: "failure"
      error_message = if status == "failure", do: get_error_message(conn), else: nil
      metadata = build_metadata(conn)

      Audit.log(conn, action, resource_type, resource_id, metadata, status, error_message)
    end
  end

  defp build_action(conn, resource_type) do
    controller_action = conn.private[:phoenix_action]
    action_suffix = Map.get(@action_mapping, controller_action, to_string(controller_action))
    "#{resource_type}.#{action_suffix}"
  end

  defp get_resource_id(conn) do
    raw_id =
      conn.params["id"] || conn.params["file_id"] || conn.params["folder_id"] ||
        conn.params["share_id"] || conn.params["request_id"]

    # Validate UUID to prevent crashes and SQL injection attempts
    case validate_uuid(raw_id) do
      {:ok, uuid} -> uuid
      {:error, _} -> nil
    end
  end

  # Validate that a string is a valid UUID format
  defp validate_uuid(nil), do: {:error, :invalid}

  defp validate_uuid(value) when is_binary(value) do
    case SecureSharing.InputSanitizer.validate_uuid(value) do
      {:ok, uuid} -> {:ok, uuid}
      {:error, _} -> {:error, :invalid}
    end
  end

  defp validate_uuid(_), do: {:error, :invalid}

  defp get_tenant_id(%{assigns: %{tenant_id: tenant_id}}), do: tenant_id
  defp get_tenant_id(%{assigns: %{current_user: %{tenant_id: tenant_id}}}), do: tenant_id
  defp get_tenant_id(_), do: nil

  defp get_error_message(conn) do
    case conn.resp_body do
      body when is_binary(body) ->
        case Jason.decode(body) do
          {:ok, %{"errors" => errors}} -> inspect(errors)
          {:ok, %{"error" => error}} -> error
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp build_metadata(conn) do
    base = %{
      method: conn.method,
      path: conn.request_path,
      status_code: conn.status
    }

    # Add relevant params (excluding sensitive data)
    params =
      conn.params
      |> Map.drop([
        "password",
        "password_confirmation",
        "token",
        "refresh_token",
        "encrypted_share",
        "encrypted_private_keys",
        "encrypted_master_key"
      ])
      |> Map.take([
        "filename",
        "folder_id",
        "parent_id",
        "permission",
        "grantee_id",
        "threshold",
        "total_shares",
        "reason"
      ])

    if map_size(params) > 0 do
      Map.put(base, :params, params)
    else
      base
    end
  end
end
