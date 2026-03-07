defmodule SecureSharingWeb.HealthControllerTest do
  use SecureSharingWeb.ConnCase, async: true

  describe "GET /health" do
    test "returns ok status", %{conn: conn} do
      conn = get(conn, ~p"/health")

      response = json_response(conn, 200)
      assert response["status"] == "ok"
      assert response["timestamp"]
      assert response["version"]
    end
  end

  describe "GET /health/ready" do
    test "returns ok status when all dependencies are healthy", %{conn: conn} do
      conn = get(conn, ~p"/health/ready")

      response = json_response(conn, 200)
      assert response["status"] == "ok"
      assert response["timestamp"]
      assert response["version"]
      assert is_list(response["checks"])

      # All checks should pass
      Enum.each(response["checks"], fn check ->
        assert check["status"] == "ok", "Check #{check["name"]} failed: #{check["error"]}"
      end)
    end

    test "includes database check", %{conn: conn} do
      conn = get(conn, ~p"/health/ready")

      response = json_response(conn, 200)
      db_check = Enum.find(response["checks"], &(&1["name"] == "database"))

      assert db_check
      assert db_check["status"] == "ok"
    end

    test "includes cache check", %{conn: conn} do
      conn = get(conn, ~p"/health/ready")

      response = json_response(conn, 200)
      cache_check = Enum.find(response["checks"], &(&1["name"] == "cache"))

      assert cache_check
      assert cache_check["status"] == "ok"
    end

    test "includes oban check", %{conn: conn} do
      conn = get(conn, ~p"/health/ready")

      response = json_response(conn, 200)
      oban_check = Enum.find(response["checks"], &(&1["name"] == "oban"))

      assert oban_check
      assert oban_check["status"] == "ok"
    end
  end
end
