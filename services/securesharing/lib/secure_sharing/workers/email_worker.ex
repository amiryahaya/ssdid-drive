defmodule SecureSharing.Workers.EmailWorker do
  @moduledoc """
  Oban worker for asynchronous email delivery.

  Replaces fire-and-forget Task.start calls for email sending,
  ensuring reliable delivery with retry logic on failures.

  ## Usage

      # Send a new device login email
      SecureSharing.Workers.EmailWorker.enqueue_new_device_login(user, device_info, login_metadata)

      # Send a recovery complete email
      SecureSharing.Workers.EmailWorker.enqueue_recovery_complete(user)

  ## Retry Logic

  - Max attempts: 5
  - Backoff: Exponential (Oban default)
  - Discards after final failure with error log
  """

  use Oban.Worker,
    queue: :mailers,
    max_attempts: 5,
    tags: ["email", "notifications"]

  alias SecureSharing.Mailer
  alias SecureSharing.Emails.NotificationEmail

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"type" => "new_device_login"} = args}) do
    user = deserialize_user(args["user"])
    device_info = args["device_info"]
    login_metadata = deserialize_login_metadata(args["login_metadata"])

    case NotificationEmail.new_device_login_email(user, device_info, login_metadata)
         |> Mailer.deliver() do
      {:ok, _} ->
        Logger.info("EmailWorker: Sent new_device_login email to #{user.email}")
        :ok

      {:error, reason} ->
        Logger.warning("EmailWorker: Failed to send new_device_login email: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"type" => "recovery_complete"} = args}) do
    user = deserialize_user(args["user"])

    case NotificationEmail.recovery_complete_email(user)
         |> Mailer.deliver() do
      {:ok, _} ->
        Logger.info("EmailWorker: Sent recovery_complete email to #{user.email}")
        :ok

      {:error, reason} ->
        Logger.warning("EmailWorker: Failed to send recovery_complete email: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    Logger.error("EmailWorker: Unknown email type: #{inspect(args)}")
    {:error, :unknown_email_type}
  end

  # ============================================================================
  # Enqueuers
  # ============================================================================

  @doc """
  Enqueue a new device login notification email.
  """
  @spec enqueue_new_device_login(map(), map(), map()) :: {:ok, Oban.Job.t()} | {:error, term()}
  def enqueue_new_device_login(user, device_info, login_metadata) do
    %{
      "type" => "new_device_login",
      "user" => serialize_user(user),
      "device_info" => device_info,
      "login_metadata" => serialize_login_metadata(login_metadata)
    }
    |> new()
    |> Oban.insert()
  end

  @doc """
  Enqueue a recovery complete notification email.
  """
  @spec enqueue_recovery_complete(map()) :: {:ok, Oban.Job.t()} | {:error, term()}
  def enqueue_recovery_complete(user) do
    %{
      "type" => "recovery_complete",
      "user" => serialize_user(user)
    }
    |> new()
    |> Oban.insert()
  end

  # ============================================================================
  # Serialization Helpers
  # ============================================================================

  # Serialize user struct to map for JSON storage
  defp serialize_user(user) do
    %{
      "id" => user.id,
      "email" => user.email,
      "tenant_id" => user.tenant_id,
      "display_name" => Map.get(user, :display_name)
    }
  end

  # Deserialize user from stored map
  defp deserialize_user(map) do
    %{
      id: map["id"],
      email: map["email"],
      tenant_id: map["tenant_id"],
      display_name: map["display_name"]
    }
  end

  # Serialize login metadata (convert DateTime to ISO8601)
  defp serialize_login_metadata(metadata) do
    %{
      "login_at" => serialize_datetime(metadata[:login_at] || metadata["login_at"]),
      "ip_address" => metadata[:ip_address] || metadata["ip_address"],
      "location" => metadata[:location] || metadata["location"]
    }
  end

  # Deserialize login metadata
  defp deserialize_login_metadata(metadata) do
    %{
      login_at: deserialize_datetime(metadata["login_at"]),
      ip_address: metadata["ip_address"],
      location: metadata["location"]
    }
  end

  defp serialize_datetime(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp serialize_datetime(nil), do: DateTime.to_iso8601(DateTime.utc_now())
  defp serialize_datetime(other), do: other

  defp deserialize_datetime(nil), do: DateTime.utc_now()

  defp deserialize_datetime(string) when is_binary(string) do
    case DateTime.from_iso8601(string) do
      {:ok, dt, _offset} -> dt
      {:error, _} -> DateTime.utc_now()
    end
  end
end
