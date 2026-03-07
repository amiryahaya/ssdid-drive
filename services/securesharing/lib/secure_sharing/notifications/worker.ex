defmodule SecureSharing.Notifications.Worker do
  @moduledoc """
  Oban worker for sending push notifications.

  Notifications are queued and processed asynchronously for:
  - Reliability: Failed notifications are automatically retried
  - Performance: API response time isn't blocked by push delivery
  - Monitoring: Oban dashboard shows notification status

  ## Job Arguments

  - `:type` - Notification type atom (for logging/metrics)
  - `:user_ids` - List of user IDs to notify
  - `:title` - Notification title
  - `:body` - Notification body text
  - `:data` - Additional data payload (optional)
  """

  use Oban.Worker,
    queue: :notifications,
    max_attempts: 3,
    priority: 1

  alias SecureSharing.Notifications.OneSignal

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    type = args["type"]
    user_ids = args["user_ids"]
    title = args["title"]
    body = args["body"]
    data = args["data"]

    Logger.info("Sending #{type} notification to #{length(user_ids)} users")

    opts = %{
      user_ids: user_ids,
      title: title,
      body: body
    }

    opts = if data, do: Map.put(opts, :data, data), else: opts

    case OneSignal.send(opts) do
      {:ok, response} ->
        Logger.info("Notification sent successfully: id=#{response["id"]}")
        :ok

      {:error, {:api_error, 400, %{"errors" => errors}}} when is_list(errors) ->
        # Check if all recipients have no valid player_ids
        # This is not a failure, just means no devices are registered
        if Enum.any?(errors, &String.contains?(&1, "No subscribed players")) do
          Logger.info("No subscribed players for notification, skipping")
          :ok
        else
          Logger.warning("OneSignal API error: #{inspect(errors)}")
          {:error, {:api_error, errors}}
        end

      {:error, reason} ->
        Logger.error("Failed to send notification: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
