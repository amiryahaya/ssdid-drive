defmodule SecureSharing.Notifications.OneSignal do
  @moduledoc """
  OneSignal push notification client.

  Provides a unified interface to send push notifications across Android, iOS,
  and Windows platforms via OneSignal's REST API.

  ## Configuration

  Add to your config:

      config :secure_sharing, SecureSharing.Notifications.OneSignal,
        app_id: "YOUR_ONESIGNAL_APP_ID",
        api_key: "YOUR_ONESIGNAL_REST_API_KEY"

  ## Usage

      # Send to specific users
      OneSignal.send(%{
        user_ids: ["user-uuid-1", "user-uuid-2"],
        title: "New Share",
        body: "John shared a file with you",
        data: %{type: "share", share_id: "xxx"}
      })

      # Send to specific player IDs
      OneSignal.send_to_players(%{
        player_ids: ["player-id-1", "player-id-2"],
        title: "File Ready",
        body: "Your download is ready"
      })
  """

  require Logger

  @base_url "https://onesignal.com/api/v1"

  @doc """
  Sends a push notification to users identified by external_user_id.

  OneSignal uses external_user_id to target specific users across devices.

  ## Options

  - `:user_ids` - List of user IDs (external_user_id in OneSignal)
  - `:title` - Notification title (required)
  - `:body` - Notification body text (required)
  - `:data` - Additional data payload (optional)
  - `:url` - URL to open on click (optional)
  - `:android_channel_id` - Android notification channel (optional)
  - `:ios_sound` - iOS sound file name (optional)
  """
  @spec send(map()) :: {:ok, map()} | {:error, term()}
  def send(opts) when is_map(opts) do
    user_ids = Map.fetch!(opts, :user_ids)
    title = Map.fetch!(opts, :title)
    body = Map.fetch!(opts, :body)

    payload = %{
      "app_id" => app_id(),
      "include_aliases" => %{
        "external_id" => user_ids
      },
      "target_channel" => "push",
      "headings" => %{"en" => title},
      "contents" => %{"en" => body}
    }

    payload =
      payload
      |> maybe_add_data(opts)
      |> maybe_add_url(opts)
      |> maybe_add_android_channel(opts)
      |> maybe_add_ios_sound(opts)

    do_send(payload)
  end

  @doc """
  Sends a push notification to specific player IDs.

  Use this when you have the OneSignal player_id directly.

  ## Options

  Same as `send/1` but with `:player_ids` instead of `:user_ids`.
  """
  @spec send_to_players(map()) :: {:ok, map()} | {:error, term()}
  def send_to_players(opts) when is_map(opts) do
    player_ids = Map.fetch!(opts, :player_ids)
    title = Map.fetch!(opts, :title)
    body = Map.fetch!(opts, :body)

    payload = %{
      "app_id" => app_id(),
      "include_player_ids" => player_ids,
      "headings" => %{"en" => title},
      "contents" => %{"en" => body}
    }

    payload =
      payload
      |> maybe_add_data(opts)
      |> maybe_add_url(opts)
      |> maybe_add_android_channel(opts)
      |> maybe_add_ios_sound(opts)

    do_send(payload)
  end

  @doc """
  Sends a silent/data-only notification.

  Use this for background sync or to trigger app actions without showing
  a visible notification.

  ## Options

  - `:user_ids` or `:player_ids` - Target recipients
  - `:data` - Data payload (required)
  """
  @spec send_silent(map()) :: {:ok, map()} | {:error, term()}
  def send_silent(opts) when is_map(opts) do
    data = Map.fetch!(opts, :data)

    payload = %{
      "app_id" => app_id(),
      "data" => data,
      "content_available" => true,
      "android_background_layout" => %{}
    }

    payload =
      cond do
        Map.has_key?(opts, :user_ids) ->
          Map.put(payload, "include_aliases", %{"external_id" => opts.user_ids})
          |> Map.put("target_channel", "push")

        Map.has_key?(opts, :player_ids) ->
          Map.put(payload, "include_player_ids", opts.player_ids)

        true ->
          raise ArgumentError, "must provide :user_ids or :player_ids"
      end

    do_send(payload)
  end

  @doc """
  Sets the external_user_id for a player.

  Call this when user logs in to associate their OneSignal player_id
  with your user ID.
  """
  @spec set_external_user_id(String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  def set_external_user_id(player_id, user_id) do
    url = "#{@base_url}/players/#{player_id}"

    body = %{
      "app_id" => app_id(),
      "external_user_id" => user_id
    }

    case Req.put(url, json: body, headers: headers()) do
      {:ok, %Req.Response{status: 200, body: response}} ->
        {:ok, response}

      {:ok, %Req.Response{status: status, body: body}} ->
        Logger.warning(
          "OneSignal set_external_user_id failed: status=#{status} body=#{inspect(body)}"
        )

        {:error, {:api_error, status, body}}

      {:error, reason} ->
        Logger.error("OneSignal request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Clears the external_user_id for a player.

  Call this when user logs out to disassociate the device.
  """
  @spec clear_external_user_id(String.t()) :: {:ok, map()} | {:error, term()}
  def clear_external_user_id(player_id) do
    url = "#{@base_url}/players/#{player_id}"

    body = %{
      "app_id" => app_id(),
      "external_user_id" => ""
    }

    case Req.put(url, json: body, headers: headers()) do
      {:ok, %Req.Response{status: 200, body: response}} ->
        {:ok, response}

      {:ok, %Req.Response{status: status, body: body}} ->
        Logger.warning("OneSignal clear_external_user_id failed: status=#{status}")
        {:error, {:api_error, status, body}}

      {:error, reason} ->
        Logger.error("OneSignal request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Gets information about a specific player.
  """
  @spec get_player(String.t()) :: {:ok, map()} | {:error, term()}
  def get_player(player_id) do
    url = "#{@base_url}/players/#{player_id}?app_id=#{app_id()}"

    case Req.get(url, headers: headers()) do
      {:ok, %Req.Response{status: 200, body: response}} ->
        {:ok, response}

      {:ok, %Req.Response{status: 404}} ->
        {:error, :not_found}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:api_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Deletes a player from OneSignal.

  Use this when a user completely removes the app or revokes their enrollment.
  """
  @spec delete_player(String.t()) :: :ok | {:error, term()}
  def delete_player(player_id) do
    url = "#{@base_url}/players/#{player_id}?app_id=#{app_id()}"

    case Req.delete(url, headers: headers()) do
      {:ok, %Req.Response{status: 200}} ->
        :ok

      {:ok, %Req.Response{status: 404}} ->
        # Already deleted
        :ok

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:api_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Private functions

  defp do_send(payload) do
    url = "#{@base_url}/notifications"

    case Req.post(url, json: payload, headers: headers()) do
      {:ok, %Req.Response{status: 200, body: %{"id" => _} = response}} ->
        Logger.debug("OneSignal notification sent: #{inspect(response)}")
        {:ok, response}

      {:ok, %Req.Response{status: status, body: body}} ->
        Logger.warning("OneSignal send failed: status=#{status} body=#{inspect(body)}")
        {:error, {:api_error, status, body}}

      {:error, reason} ->
        Logger.error("OneSignal request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp headers do
    [
      {"Authorization", "Basic #{api_key()}"},
      {"Content-Type", "application/json; charset=utf-8"}
    ]
  end

  defp app_id do
    config()[:app_id] || raise "OneSignal app_id not configured"
  end

  defp api_key do
    config()[:api_key] || raise "OneSignal api_key not configured"
  end

  defp config do
    Application.get_env(:secure_sharing, __MODULE__, [])
  end

  defp maybe_add_data(payload, opts) do
    case Map.get(opts, :data) do
      nil -> payload
      data when is_map(data) -> Map.put(payload, "data", data)
    end
  end

  defp maybe_add_url(payload, opts) do
    case Map.get(opts, :url) do
      nil -> payload
      url -> Map.put(payload, "url", url)
    end
  end

  defp maybe_add_android_channel(payload, opts) do
    case Map.get(opts, :android_channel_id) do
      nil -> payload
      channel -> Map.put(payload, "android_channel_id", channel)
    end
  end

  defp maybe_add_ios_sound(payload, opts) do
    case Map.get(opts, :ios_sound) do
      nil -> payload
      sound -> Map.put(payload, "ios_sound", sound)
    end
  end
end
