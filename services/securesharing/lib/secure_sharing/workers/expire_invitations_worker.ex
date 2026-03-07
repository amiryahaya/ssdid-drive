defmodule SecureSharing.Workers.ExpireInvitationsWorker do
  @moduledoc """
  Oban worker for expiring old invitations.

  Runs hourly to mark pending invitations as expired if they are past
  their expiration date. This ensures that expired invitations cannot
  be accepted even if the token is somehow still known.

  ## Scheduling

  This worker is configured as a cron job in the application config:

      config :secure_sharing, Oban,
        plugins: [
          {Oban.Plugins.Cron, crontab: [
            {"0 * * * *", SecureSharing.Workers.ExpireInvitationsWorker}
          ]}
        ]
  """

  use Oban.Worker,
    queue: :maintenance,
    max_attempts: 3,
    tags: ["invitations", "maintenance"]

  alias SecureSharing.Invitations

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    {:ok, count} = Invitations.expire_old_invitations()

    if count > 0 do
      Logger.info("ExpireInvitationsWorker: Expired #{count} invitation(s)")
    end

    :ok
  end
end
