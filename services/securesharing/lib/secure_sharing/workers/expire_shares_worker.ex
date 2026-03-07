defmodule SecureSharing.Workers.ExpireSharesWorker do
  @moduledoc """
  Oban worker for auto-invalidating expired share grants.

  Runs every 15 minutes to find active shares whose `expires_at` has passed,
  updates their status, and emits audit events.

  ## Scheduling

  This worker is configured as a cron job in the application config:

      config :secure_sharing, Oban,
        plugins: [
          {Oban.Plugins.Cron, crontab: [
            {"*/15 * * * *", SecureSharing.Workers.ExpireSharesWorker}
          ]}
        ]
  """

  use Oban.Worker,
    queue: :maintenance,
    max_attempts: 3,
    tags: ["shares", "maintenance"]

  alias SecureSharing.Sharing

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    {:ok, count} = Sharing.expire_stale_shares()

    if count > 0 do
      Logger.info("ExpireSharesWorker: Expired #{count} share(s)")
    end

    :ok
  end
end
