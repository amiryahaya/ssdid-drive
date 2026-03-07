defmodule SecureSharing.Workers.NotificationWorker do
  @moduledoc """
  Oban worker for asynchronous push notification operations.

  Replaces fire-and-forget Task.start calls for OneSignal operations,
  ensuring reliable delivery with retry logic on failures.

  ## Usage

      # Set external user ID in OneSignal
      SecureSharing.Workers.NotificationWorker.enqueue_set_external_user_id(player_id, user_id)

      # Clear external user ID in OneSignal
      SecureSharing.Workers.NotificationWorker.enqueue_clear_external_user_id(player_id)

  ## Retry Logic

  - Max attempts: 5
  - Backoff: Exponential (Oban default)
  - External API failures trigger retry
  """

  use Oban.Worker,
    queue: :notifications,
    max_attempts: 5,
    tags: ["push", "onesignal"]

  alias SecureSharing.Notifications.OneSignal

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"type" => "set_external_user_id"} = args}) do
    player_id = args["player_id"]
    user_id = args["user_id"]

    case OneSignal.set_external_user_id(player_id, user_id) do
      {:ok, _response} ->
        Logger.info("NotificationWorker: Set external_user_id for player #{player_id}")
        :ok

      {:error, reason} ->
        Logger.warning(
          "NotificationWorker: Failed to set external_user_id for player #{player_id}: #{inspect(reason)}"
        )

        {:error, reason}
    end
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"type" => "clear_external_user_id"} = args}) do
    player_id = args["player_id"]

    case OneSignal.clear_external_user_id(player_id) do
      {:ok, _response} ->
        Logger.info("NotificationWorker: Cleared external_user_id for player #{player_id}")
        :ok

      {:error, reason} ->
        Logger.warning(
          "NotificationWorker: Failed to clear external_user_id for player #{player_id}: #{inspect(reason)}"
        )

        {:error, reason}
    end
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    Logger.error("NotificationWorker: Unknown notification type: #{inspect(args)}")
    {:error, :unknown_notification_type}
  end

  # ============================================================================
  # Enqueuers
  # ============================================================================

  @doc """
  Enqueue setting external_user_id in OneSignal.

  Links a OneSignal player (device) to a SecureSharing user for targeted notifications.
  """
  @spec enqueue_set_external_user_id(String.t(), String.t()) ::
          {:ok, Oban.Job.t()} | {:error, term()}
  def enqueue_set_external_user_id(player_id, user_id)
      when is_binary(player_id) and is_binary(user_id) do
    %{
      "type" => "set_external_user_id",
      "player_id" => player_id,
      "user_id" => user_id
    }
    |> new()
    |> Oban.insert()
  end

  @doc """
  Enqueue clearing external_user_id in OneSignal.

  Unlinks a OneSignal player from the user (used on logout).
  """
  @spec enqueue_clear_external_user_id(String.t()) :: {:ok, Oban.Job.t()} | {:error, term()}
  def enqueue_clear_external_user_id(player_id) when is_binary(player_id) do
    %{
      "type" => "clear_external_user_id",
      "player_id" => player_id
    }
    |> new()
    |> Oban.insert()
  end
end
