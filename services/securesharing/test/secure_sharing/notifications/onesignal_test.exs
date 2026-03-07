defmodule SecureSharing.Notifications.OneSignalTest do
  @moduledoc """
  Tests for the OneSignal push notification client.

  Tests marked with :external_service require real OneSignal credentials
  and are excluded by default. Run with: mix test --include external_service
  """

  use ExUnit.Case, async: false

  alias SecureSharing.Notifications.OneSignal

  setup do
    # Store original config
    original_config = Application.get_env(:secure_sharing, OneSignal)

    on_exit(fn ->
      if original_config do
        Application.put_env(:secure_sharing, OneSignal, original_config)
      else
        Application.delete_env(:secure_sharing, OneSignal)
      end
    end)

    :ok
  end

  describe "configuration" do
    test "raises when app_id is not configured" do
      Application.put_env(:secure_sharing, OneSignal, api_key: "test-key")

      assert_raise RuntimeError, "OneSignal app_id not configured", fn ->
        OneSignal.send(%{
          user_ids: ["user1"],
          title: "Test",
          body: "Test message"
        })
      end
    end

    test "raises when api_key is not configured" do
      Application.put_env(:secure_sharing, OneSignal, app_id: "test-app")

      # This will raise when trying to build headers
      assert_raise RuntimeError, "OneSignal api_key not configured", fn ->
        OneSignal.send(%{
          user_ids: ["user1"],
          title: "Test",
          body: "Test message"
        })
      end
    end

    test "raises when neither app_id nor api_key are configured" do
      Application.delete_env(:secure_sharing, OneSignal)

      assert_raise RuntimeError, "OneSignal app_id not configured", fn ->
        OneSignal.send(%{
          user_ids: ["user1"],
          title: "Test",
          body: "Test message"
        })
      end
    end
  end

  describe "send/1 argument validation" do
    setup do
      Application.put_env(:secure_sharing, OneSignal,
        app_id: "test-app-id",
        api_key: "test-api-key"
      )

      :ok
    end

    test "requires user_ids" do
      assert_raise KeyError, ~r/user_ids/, fn ->
        OneSignal.send(%{
          title: "Test",
          body: "Test message"
        })
      end
    end

    test "requires title" do
      assert_raise KeyError, ~r/title/, fn ->
        OneSignal.send(%{
          user_ids: ["user1"],
          body: "Test message"
        })
      end
    end

    test "requires body" do
      assert_raise KeyError, ~r/body/, fn ->
        OneSignal.send(%{
          user_ids: ["user1"],
          title: "Test"
        })
      end
    end
  end

  describe "send_to_players/1 argument validation" do
    setup do
      Application.put_env(:secure_sharing, OneSignal,
        app_id: "test-app-id",
        api_key: "test-api-key"
      )

      :ok
    end

    test "requires player_ids" do
      assert_raise KeyError, ~r/player_ids/, fn ->
        OneSignal.send_to_players(%{
          title: "Test",
          body: "Test message"
        })
      end
    end

    test "requires title" do
      assert_raise KeyError, ~r/title/, fn ->
        OneSignal.send_to_players(%{
          player_ids: ["player1"],
          body: "Test message"
        })
      end
    end

    test "requires body" do
      assert_raise KeyError, ~r/body/, fn ->
        OneSignal.send_to_players(%{
          player_ids: ["player1"],
          title: "Test"
        })
      end
    end
  end

  describe "send_silent/1 argument validation" do
    setup do
      Application.put_env(:secure_sharing, OneSignal,
        app_id: "test-app-id",
        api_key: "test-api-key"
      )

      :ok
    end

    test "requires data" do
      assert_raise KeyError, ~r/data/, fn ->
        OneSignal.send_silent(%{
          user_ids: ["user1"]
        })
      end
    end

    test "requires user_ids or player_ids" do
      assert_raise ArgumentError, "must provide :user_ids or :player_ids", fn ->
        OneSignal.send_silent(%{
          data: %{type: "sync"}
        })
      end
    end

    test "accepts user_ids with data" do
      # This will fail the HTTP request but pass validation
      result =
        OneSignal.send_silent(%{
          user_ids: ["user1"],
          data: %{type: "sync"}
        })

      # Should return an error (network/HTTP error, not validation)
      assert {:error, _reason} = result
    end

    test "accepts player_ids with data" do
      # This will fail the HTTP request but pass validation
      result =
        OneSignal.send_silent(%{
          player_ids: ["player1"],
          data: %{type: "sync"}
        })

      # Should return an error (network/HTTP error, not validation)
      assert {:error, _reason} = result
    end
  end

  describe "player management argument handling" do
    setup do
      Application.put_env(:secure_sharing, OneSignal,
        app_id: "test-app-id",
        api_key: "test-api-key"
      )

      :ok
    end

    test "set_external_user_id accepts player_id and user_id" do
      # This will fail the HTTP request but validates the function accepts arguments
      result = OneSignal.set_external_user_id("player-id-123", "user-uuid")

      # Should return an error (network/HTTP error, not validation)
      assert {:error, _reason} = result
    end

    test "clear_external_user_id accepts player_id" do
      # This will fail the HTTP request but validates the function accepts arguments
      result = OneSignal.clear_external_user_id("player-id-123")

      # Should return an error (network/HTTP error, not validation)
      assert {:error, _reason} = result
    end

    test "get_player accepts player_id" do
      result = OneSignal.get_player("player-id-123")

      # Should return an error (network/HTTP error)
      assert {:error, _reason} = result
    end

    test "delete_player accepts player_id" do
      result = OneSignal.delete_player("player-id-123")

      # Should return an error (network/HTTP error)
      assert {:error, _reason} = result
    end
  end
end
