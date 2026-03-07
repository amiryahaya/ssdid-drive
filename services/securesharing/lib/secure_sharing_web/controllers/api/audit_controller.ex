defmodule SecureSharingWeb.API.AuditController do
  @moduledoc """
  Controller for viewing audit logs.

  Provides endpoints to query audit events for files, folders,
  and all resources owned by the current user.
  """

  use SecureSharingWeb, :controller

  alias SecureSharing.Audit
  alias SecureSharing.Files
  alias SecureSharing.Sharing

  action_fallback SecureSharingWeb.FallbackController

  @doc """
  List all audit events for the current user's resources.

  GET /api/audit-log

  Query params:
  - page: Page number (default: 1)
  - page_size: Items per page (default: 50, max: 100)
  - action: Filter by action (e.g., "file.create", "share.*")
  - resource_type: Filter by resource type
  - status: Filter by status ("success" or "failure")
  - from: Filter events after this ISO 8601 datetime
  - to: Filter events before this ISO 8601 datetime
  """
  def index(conn, params) do
    user = conn.assigns.current_user
    tenant_id = conn.assigns.tenant_id
    opts = build_filter_opts(params, user_id: user.id)

    events = Audit.list_events(tenant_id, opts)
    total = Audit.count_events(tenant_id, Keyword.delete(opts, :limit) |> Keyword.delete(:offset))

    render(conn, :index, events: events, meta: pagination_meta(params, total))
  end

  @doc """
  List audit events for a specific file.

  GET /api/files/:id/audit-log

  Requires :admin or :owner permission on the file.
  """
  def file_audit_log(conn, %{"id" => file_id} = params) do
    user = conn.assigns.current_user
    tenant_id = conn.assigns.tenant_id

    with {:ok, file} <- get_file(file_id),
         :ok <- verify_audit_access(user, :file, file) do
      opts = build_filter_opts(params, resource_type: "file", resource_id: file_id)

      events = Audit.list_events(tenant_id, opts)

      total =
        Audit.count_events(
          tenant_id,
          Keyword.delete(opts, :limit) |> Keyword.delete(:offset)
        )

      render(conn, :index, events: events, meta: pagination_meta(params, total))
    end
  end

  @doc """
  List audit events for a specific folder.

  GET /api/folders/:id/audit-log

  Requires :admin or :owner permission on the folder.
  """
  def folder_audit_log(conn, %{"id" => folder_id} = params) do
    user = conn.assigns.current_user
    tenant_id = conn.assigns.tenant_id

    with {:ok, folder} <- get_folder(folder_id),
         :ok <- verify_audit_access(user, :folder, folder) do
      opts = build_filter_opts(params, resource_type: "folder", resource_id: folder_id)

      events = Audit.list_events(tenant_id, opts)

      total =
        Audit.count_events(
          tenant_id,
          Keyword.delete(opts, :limit) |> Keyword.delete(:offset)
        )

      render(conn, :index, events: events, meta: pagination_meta(params, total))
    end
  end

  # Private functions

  defp get_file(id) do
    case Files.get_file(id) do
      nil -> {:error, :not_found}
      file -> {:ok, file}
    end
  end

  defp get_folder(id) do
    case Files.get_folder(id) do
      nil -> {:error, :not_found}
      folder -> {:ok, folder}
    end
  end

  defp verify_audit_access(user, :file, file) do
    case Sharing.get_file_permission(user, file) do
      perm when perm in [:owner, :admin] -> :ok
      _ -> {:error, :forbidden}
    end
  end

  defp verify_audit_access(user, :folder, folder) do
    case Sharing.get_folder_permission(user, folder) do
      perm when perm in [:owner, :admin] -> :ok
      _ -> {:error, :forbidden}
    end
  end

  defp build_filter_opts(params, defaults) do
    pagination = parse_pagination(params)

    defaults
    |> Keyword.merge(
      limit: pagination.limit,
      offset: pagination.offset
    )
    |> maybe_add_filter(:action, params["action"])
    |> maybe_add_filter(:resource_type, params["resource_type"])
    |> maybe_add_filter(:status, params["status"])
    |> maybe_add_datetime_filter(:from, params["from"])
    |> maybe_add_datetime_filter(:to, params["to"])
  end

  defp maybe_add_filter(opts, _key, nil), do: opts
  defp maybe_add_filter(opts, _key, ""), do: opts
  defp maybe_add_filter(opts, key, value), do: Keyword.put(opts, key, value)

  defp maybe_add_datetime_filter(opts, _key, nil), do: opts
  defp maybe_add_datetime_filter(opts, _key, ""), do: opts

  defp maybe_add_datetime_filter(opts, key, value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _offset} -> Keyword.put(opts, key, dt)
      {:error, _} -> opts
    end
  end

  defp parse_pagination(params) do
    page = max(String.to_integer(params["page"] || "1"), 1)
    page_size = params["page_size"] || "50"
    page_size = page_size |> String.to_integer() |> max(1) |> min(100)

    %{
      page: page,
      limit: page_size,
      offset: (page - 1) * page_size
    }
  end

  defp pagination_meta(params, total) do
    pagination = parse_pagination(params)
    total_pages = if pagination.limit > 0, do: ceil(total / pagination.limit), else: 1

    %{
      page: pagination.page,
      page_size: pagination.limit,
      total_count: total,
      total_pages: total_pages
    }
  end
end
