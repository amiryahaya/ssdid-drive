defmodule SecureSharingWeb.Plugs.RateLimit do
  @moduledoc """
  Rate limiting plug using Hammer.

  Limits requests based on IP address or user ID (if authenticated).

  ## Usage

      # In router pipeline - 5 requests per minute
      plug SecureSharingWeb.Plugs.RateLimit, scale: 60_000, limit: 5

      # 100 requests per minute
      plug SecureSharingWeb.Plugs.RateLimit, scale: 60_000, limit: 100

  ## Options

  - `:scale` - Time window in milliseconds (default: 60_000 = 1 minute)
  - `:limit` - Maximum requests in the time window (default: 100)
  - `:by` - Rate limit key strategy: `:ip` or `:user` (default: `:ip`)

  On rate limit exceeded, returns 429 Too Many Requests.
  """

  import Plug.Conn

  @behaviour Plug

  # 1 minute
  @default_scale 60_000
  @default_limit 100

  @impl true
  def init(opts) do
    %{
      scale: Keyword.get(opts, :scale, @default_scale),
      limit: Keyword.get(opts, :limit, @default_limit),
      by: Keyword.get(opts, :by, :ip)
    }
  end

  @impl true
  def call(conn, opts) do
    # Skip rate limiting if disabled (e.g., in tests)
    if Application.get_env(:secure_sharing, :rate_limit_enabled, true) do
      key = build_key(conn, opts)

      case Hammer.check_rate(key, opts.scale, opts.limit) do
        {:allow, _count} ->
          conn

        {:deny, _limit} ->
          conn
          |> put_status(:too_many_requests)
          |> put_resp_header("retry-after", to_string(div(opts.scale, 1000)))
          |> Phoenix.Controller.put_view(json: SecureSharingWeb.ErrorJSON)
          |> Phoenix.Controller.render("429.json")
          |> halt()
      end
    else
      conn
    end
  end

  defp build_key(conn, %{by: :user}) do
    user_id = conn.assigns[:current_user] && conn.assigns.current_user.id
    ip = get_ip(conn)
    "rate_limit:#{user_id || ip}:#{conn.request_path}"
  end

  defp build_key(conn, %{by: :ip}) do
    ip = get_ip(conn)
    "rate_limit:#{ip}:#{conn.request_path}"
  end

  defp get_ip(conn) do
    # Check for forwarded IP (behind proxy/load balancer)
    forwarded = get_req_header(conn, "x-forwarded-for")

    case forwarded do
      [ip | _] ->
        ip |> String.split(",") |> List.first() |> String.trim()

      [] ->
        conn.remote_ip |> :inet.ntoa() |> to_string()
    end
  end
end
