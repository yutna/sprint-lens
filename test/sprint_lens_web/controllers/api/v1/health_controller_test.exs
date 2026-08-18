defmodule SprintLensWeb.Api.V1.HealthControllerTest do
  use SprintLensWeb.ConnCase

  describe "GET /api/v1/health" do
    @tag req: ["NFR-501"]
    test "answers readiness with 200 and a per-dependency breakdown", %{conn: conn} do
      body = conn |> get(~p"/api/v1/health") |> json_response(200)

      assert body["status"] == "ok"

      names = Enum.map(body["checks"], & &1["name"])
      assert "database" in names
      assert "jobs" in names
    end

    @tag req: ["NFR-501"]
    test "answers liveness without probing dependencies", %{conn: conn} do
      body = conn |> get(~p"/api/v1/health?probe=live") |> json_response(200)

      assert body == %{"status" => "ok", "checks" => []}
    end

    @tag req: ["NFR-501"]
    test "treats an unrecognised probe as a readiness check", %{conn: conn} do
      body = conn |> get(~p"/api/v1/health?probe=nonsense") |> json_response(200)

      assert body["checks"] != []
    end

    @tag req: ["NFR-501"]
    test "needs no authentication, unlike every other API endpoint", %{conn: conn} do
      conn = conn |> delete_req_header("authorization") |> get(~p"/api/v1/health")

      assert conn.status == 200
    end
  end
end
