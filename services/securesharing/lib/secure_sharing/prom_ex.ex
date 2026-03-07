defmodule SecureSharing.PromEx do
  @moduledoc """
  Prometheus metrics exporter using PromEx.

  Exposes BEAM, Phoenix, Ecto, and Oban metrics on a dedicated HTTP server
  (default port 4021) for Prometheus scraping.
  """

  use PromEx, otp_app: :secure_sharing

  alias PromEx.Plugins

  @impl true
  def plugins do
    [
      Plugins.Beam,
      {Plugins.Phoenix,
       router: SecureSharingWeb.Router,
       endpoint: SecureSharingWeb.Endpoint},
      {Plugins.Ecto, repos: [SecureSharing.Repo]},
      {Plugins.Oban, oban_supervisors: [Oban]},
      {Plugins.Application, otp_app: :secure_sharing}
    ]
  end

  @impl true
  def dashboard_assigns do
    [
      datasource_id: "prometheus",
      default_selected_interval: "30s"
    ]
  end

  @impl true
  def dashboards do
    [
      {:prom_ex, "beam.json"},
      {:prom_ex, "phoenix.json"},
      {:prom_ex, "ecto.json"},
      {:prom_ex, "oban.json"}
    ]
  end
end
