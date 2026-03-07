defmodule SecureSharing.Workers.AuditWorker do
  @moduledoc """
  Oban worker for asynchronous audit logging.

  Replaces fire-and-forget Task.start calls for audit events,
  ensuring reliable logging with retry logic on failures.

  ## Usage

      # Log an audit event asynchronously
      SecureSharing.Workers.AuditWorker.enqueue(%{
        tenant_id: tenant_id,
        user_id: user_id,
        action: "user.login",
        resource_type: "user",
        resource_id: user.id,
        ip_address: "192.168.1.1",
        user_agent: "Mozilla/5.0...",
        metadata: %{email: "user@example.com"},
        status: "success",
        error_message: nil
      })
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 3,
    tags: ["audit", "logging"]

  alias SecureSharing.Repo
  alias SecureSharing.Audit.AuditEvent

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    attrs = %{
      tenant_id: args["tenant_id"],
      user_id: args["user_id"],
      action: args["action"],
      resource_type: args["resource_type"],
      resource_id: args["resource_id"],
      ip_address: args["ip_address"],
      user_agent: args["user_agent"],
      metadata: args["metadata"] || %{},
      status: args["status"] || "success",
      error_message: args["error_message"]
    }

    case create_event(attrs) do
      {:ok, _event} ->
        :ok

      {:error, changeset} ->
        Logger.warning("AuditWorker: Failed to create audit event: #{inspect(changeset.errors)}")
        {:error, :audit_insert_failed}
    end
  end

  @doc """
  Enqueue an audit event for asynchronous processing.

  Returns {:ok, job} on success.
  """
  @spec enqueue(map()) :: {:ok, Oban.Job.t()} | {:error, term()}
  def enqueue(attrs) when is_map(attrs) do
    attrs
    |> stringify_keys()
    |> new()
    |> Oban.insert()
  end

  defp create_event(attrs) do
    %AuditEvent{}
    |> AuditEvent.changeset(attrs)
    |> Repo.insert()
  end

  # Convert atom keys to strings for JSON serialization
  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), stringify_keys(v)}
      {k, v} -> {k, stringify_keys(v)}
    end)
  end

  defp stringify_keys(value), do: value
end
