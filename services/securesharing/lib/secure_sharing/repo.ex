defmodule SecureSharing.Repo do
  use Ecto.Repo,
    otp_app: :secure_sharing,
    adapter: Ecto.Adapters.Postgres
end
