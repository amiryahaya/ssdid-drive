defmodule SecureSharing.Audit do
  @moduledoc """
  Context module for audit logging.

  Provides functions to:
  - Log audit events for all security-relevant actions
  - Query and filter audit events
  - Export audit logs for compliance
  """

  import Ecto.Query, warn: false

  alias SecureSharing.Repo
  alias SecureSharing.Audit.AuditEvent

  @doc """
  Logs an audit event asynchronously via Oban.

  This is the primary function for logging audit events. It enqueues a job
  to avoid blocking the main request flow, with retry logic for reliability.

  ## Examples

      iex> log(conn, "user.login", "user", user.id)
      :ok

      iex> log(conn, "file.create", "file", file.id, %{filename: "doc.pdf"})
      :ok
  """
  def log(
        conn,
        action,
        resource_type,
        resource_id \\ nil,
        metadata \\ %{},
        status \\ "success",
        error_message \\ nil
      ) do
    alias SecureSharing.Workers.AuditWorker

    AuditWorker.enqueue(%{
      tenant_id: get_tenant_id(conn),
      user_id: get_user_id(conn),
      action: action,
      resource_type: resource_type,
      resource_id: resource_id,
      ip_address: get_ip_address(conn),
      user_agent: get_user_agent(conn),
      metadata: metadata,
      status: status,
      error_message: error_message
    })

    :ok
  end

  @doc """
  Logs a successful audit event.
  """
  def log_success(conn, action, resource_type, resource_id \\ nil, metadata \\ %{}) do
    log(conn, action, resource_type, resource_id, metadata, "success", nil)
  end

  @doc """
  Logs a failed audit event with an error message.
  """
  def log_failure(conn, action, resource_type, resource_id \\ nil, metadata \\ %{}, error_message) do
    log(conn, action, resource_type, resource_id, metadata, "failure", error_message)
  end

  @doc """
  Creates an audit event synchronously.

  Use this when you need to ensure the event is recorded before proceeding.
  """
  def create_event(attrs) do
    %AuditEvent{}
    |> AuditEvent.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Lists audit events for a tenant with optional filters.

  ## Options

    * `:user_id` - Filter by user ID
    * `:action` - Filter by action (exact match or prefix with wildcard)
    * `:resource_type` - Filter by resource type
    * `:resource_id` - Filter by resource ID
    * `:status` - Filter by status ("success" or "failure")
    * `:from` - Filter events after this datetime
    * `:to` - Filter events before this datetime
    * `:limit` - Maximum number of events to return (default: 100)
    * `:offset` - Number of events to skip (default: 0)
    * `:order` - :asc or :desc (default: :desc)

  ## Examples

      iex> list_events(tenant_id, user_id: user.id, action: "file.*")
      [%AuditEvent{}, ...]
  """
  def list_events(tenant_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)
    offset = Keyword.get(opts, :offset, 0)
    order = Keyword.get(opts, :order, :desc)

    base_query(tenant_id)
    |> apply_filters(opts)
    |> order_by([e], [{^order, e.inserted_at}, {^order, e.id}])
    |> limit(^limit)
    |> offset(^offset)
    |> Repo.all()
    |> Repo.preload(:user)
  end

  @doc """
  Counts audit events for a tenant with optional filters.

  Accepts the same filter options as `list_events/2`.
  """
  def count_events(tenant_id, opts \\ []) do
    base_query(tenant_id)
    |> apply_filters(opts)
    |> Repo.aggregate(:count)
  end

  @doc """
  Gets a single audit event by ID.
  """
  def get_event(tenant_id, event_id) do
    AuditEvent
    |> where([e], e.tenant_id == ^tenant_id and e.id == ^event_id)
    |> Repo.one()
    |> Repo.preload(:user)
  end

  @doc """
  Lists events for a specific resource.
  """
  def list_resource_events(tenant_id, resource_type, resource_id, opts \\ []) do
    opts = Keyword.merge(opts, resource_type: resource_type, resource_id: resource_id)
    list_events(tenant_id, opts)
  end

  @doc """
  Lists events for a specific user.
  """
  def list_user_events(tenant_id, user_id, opts \\ []) do
    opts = Keyword.put(opts, :user_id, user_id)
    list_events(tenant_id, opts)
  end

  @doc """
  Gets statistics for audit events.

  Returns a map with counts grouped by action and status.
  """
  def get_statistics(tenant_id, opts \\ []) do
    from_date = Keyword.get(opts, :from)
    to_date = Keyword.get(opts, :to)

    query =
      base_query(tenant_id)
      |> maybe_filter_date_range(from_date, to_date)

    action_counts =
      query
      |> group_by([e], e.action)
      |> select([e], {e.action, count(e.id)})
      |> Repo.all()
      |> Map.new()

    status_counts =
      query
      |> group_by([e], e.status)
      |> select([e], {e.status, count(e.id)})
      |> Repo.all()
      |> Map.new()

    resource_counts =
      query
      |> group_by([e], e.resource_type)
      |> select([e], {e.resource_type, count(e.id)})
      |> Repo.all()
      |> Map.new()

    %{
      total: Repo.aggregate(query, :count),
      by_action: action_counts,
      by_status: status_counts,
      by_resource_type: resource_counts
    }
  end

  @doc """
  Exports audit events as a list of maps suitable for CSV/JSON export.
  """
  def export_events(tenant_id, opts \\ []) do
    list_events(tenant_id, opts)
    |> Enum.map(&format_event_for_export/1)
  end

  @doc """
  Deletes audit events older than the specified number of days.

  Used for compliance with data retention policies.
  """
  def delete_old_events(tenant_id, days_to_keep) do
    cutoff = DateTime.utc_now() |> DateTime.add(-days_to_keep * 24 * 60 * 60, :second)

    {count, _} =
      from(e in AuditEvent,
        where: e.tenant_id == ^tenant_id and e.inserted_at < ^cutoff
      )
      |> Repo.delete_all()

    {:ok, count}
  end

  # Private functions

  defp base_query(tenant_id) do
    from(e in AuditEvent, where: e.tenant_id == ^tenant_id)
  end

  defp apply_filters(query, opts) do
    query
    |> maybe_filter_user(Keyword.get(opts, :user_id))
    |> maybe_filter_action(Keyword.get(opts, :action))
    |> maybe_filter_resource_type(Keyword.get(opts, :resource_type))
    |> maybe_filter_resource_id(Keyword.get(opts, :resource_id))
    |> maybe_filter_status(Keyword.get(opts, :status))
    |> maybe_filter_date_range(Keyword.get(opts, :from), Keyword.get(opts, :to))
    |> maybe_filter_ip(Keyword.get(opts, :ip_address))
  end

  defp maybe_filter_user(query, nil), do: query

  defp maybe_filter_user(query, user_id) do
    where(query, [e], e.user_id == ^user_id)
  end

  defp maybe_filter_action(query, nil), do: query

  defp maybe_filter_action(query, action) do
    if String.ends_with?(action, ".*") do
      prefix = String.replace_suffix(action, ".*", "")
      where(query, [e], like(e.action, ^"#{prefix}%"))
    else
      where(query, [e], e.action == ^action)
    end
  end

  defp maybe_filter_resource_type(query, nil), do: query

  defp maybe_filter_resource_type(query, resource_type) do
    where(query, [e], e.resource_type == ^resource_type)
  end

  defp maybe_filter_resource_id(query, nil), do: query

  defp maybe_filter_resource_id(query, resource_id) do
    where(query, [e], e.resource_id == ^resource_id)
  end

  defp maybe_filter_status(query, nil), do: query

  defp maybe_filter_status(query, status) do
    where(query, [e], e.status == ^status)
  end

  defp maybe_filter_date_range(query, nil, nil), do: query

  defp maybe_filter_date_range(query, from, nil) do
    where(query, [e], e.inserted_at >= ^from)
  end

  defp maybe_filter_date_range(query, nil, to) do
    where(query, [e], e.inserted_at <= ^to)
  end

  defp maybe_filter_date_range(query, from, to) do
    where(query, [e], e.inserted_at >= ^from and e.inserted_at <= ^to)
  end

  defp maybe_filter_ip(query, nil), do: query

  defp maybe_filter_ip(query, ip_address) do
    where(query, [e], e.ip_address == ^ip_address)
  end

  defp get_tenant_id(%{assigns: %{tenant_id: tenant_id}}), do: tenant_id
  defp get_tenant_id(%{assigns: %{current_user: %{tenant_id: tenant_id}}}), do: tenant_id
  defp get_tenant_id(_), do: nil

  defp get_user_id(%{assigns: %{user_id: user_id}}), do: user_id
  defp get_user_id(%{assigns: %{current_user: %{id: user_id}}}), do: user_id
  defp get_user_id(_), do: nil

  defp get_ip_address(conn) do
    case Plug.Conn.get_req_header(conn, "x-forwarded-for") do
      [forwarded | _] -> forwarded |> String.split(",") |> List.first() |> String.trim()
      [] -> conn.remote_ip |> :inet.ntoa() |> to_string()
    end
  end

  defp get_user_agent(conn) do
    case Plug.Conn.get_req_header(conn, "user-agent") do
      [ua | _] -> String.slice(ua, 0, 500)
      [] -> nil
    end
  end

  defp format_event_for_export(event) do
    %{
      id: event.id,
      timestamp: event.inserted_at,
      user_id: event.user_id,
      user_email: if(event.user, do: event.user.email, else: nil),
      action: event.action,
      resource_type: event.resource_type,
      resource_id: event.resource_id,
      ip_address: event.ip_address,
      user_agent: event.user_agent,
      status: event.status,
      error_message: event.error_message,
      metadata: Jason.encode!(event.metadata || %{})
    }
  end
end
