defmodule SprintLensWeb.Plugs.RequestContextTest do
  use SprintLensWeb.ConnCase

  alias SprintLensWeb.Plugs.RequestContext

  setup do
    Logger.reset_metadata()
    on_exit(&Logger.reset_metadata/0)
    :ok
  end

  describe "call/2" do
    @tag req: ["NFR-502"]
    test "lifts the correlation id set by Plug.RequestId into logger metadata" do
      Phoenix.ConnTest.build_conn(:get, "/api/v1/health")
      |> Plug.Conn.put_resp_header("x-request-id", "F9-abc123")
      |> RequestContext.call([])

      assert Logger.metadata()[:request_id] == "F9-abc123"
    end

    @tag req: ["NFR-502"]
    test "records the route so a log line can be placed without a stack trace" do
      Phoenix.ConnTest.build_conn(:post, "/api/v1/sessions/1/cards")
      |> RequestContext.call([])

      metadata = Logger.metadata()
      assert metadata[:method] == "POST"
      assert metadata[:path] == "/api/v1/sessions/1/cards"
    end

    @tag req: ["NFR-502"]
    test "falls back to existing metadata when no header has been set yet" do
      Logger.metadata(request_id: "already-set")

      Phoenix.ConnTest.build_conn(:get, "/") |> RequestContext.call([])

      assert Logger.metadata()[:request_id] == "already-set"
    end

    @tag req: ["NFR-502"]
    test "records the response status once the response is sent" do
      Phoenix.ConnTest.build_conn(:get, "/")
      |> RequestContext.call([])
      |> Plug.Conn.send_resp(204, "")

      assert Logger.metadata()[:status] == 204
    end

    @tag req: ["NFR-502"]
    test "init/1 passes its options through untouched" do
      assert RequestContext.init(:anything) == :anything
    end
  end

  describe "put_user/1" do
    @tag req: ["NFR-502"]
    test "records the acting user's id from a struct" do
      RequestContext.put_user(%{id: 42})

      assert Logger.metadata()[:user_id] == 42
    end

    @tag req: ["NFR-502"]
    test "records a bare id" do
      RequestContext.put_user(42)

      assert Logger.metadata()[:user_id] == 42
    end

    @tag req: ["NFR-502"]
    test "records nothing for an anonymous request" do
      assert RequestContext.put_user(nil) == :ok
      assert Logger.metadata()[:user_id] == nil
    end

    @tag req: ["NFR-502"]
    test "never records personal data alongside the id" do
      RequestContext.put_user(%{id: 42, email: "nok@example.com", display_name: "Nok"})

      metadata = Logger.metadata()
      assert metadata[:user_id] == 42
      refute Keyword.has_key?(metadata, :email)
      refute Keyword.has_key?(metadata, :display_name)
    end
  end

  describe "in the router pipeline" do
    @tag req: ["NFR-502"]
    test "every response carries a correlation id header", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/health")

      assert [request_id] = Plug.Conn.get_resp_header(conn, "x-request-id")
      assert request_id != ""
    end
  end
end
