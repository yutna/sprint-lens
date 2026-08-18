defmodule SprintLensWeb.FallbackControllerTest do
  use SprintLensWeb.ConnCase

  @moduletag locale: "en"

  alias SprintLens.Accounts.User
  alias SprintLensWeb.FallbackController

  defp fallback(result) do
    :get
    |> Phoenix.ConnTest.build_conn("/api/v1/anything")
    |> Plug.Conn.put_private(:phoenix_format, "json")
    |> FallbackController.call(result)
  end

  defp body(conn), do: conn.resp_body |> Jason.decode!()

  describe "call/2" do
    @tag req: ["FR-919"]
    test "turns a changeset into a 422 with per-field messages" do
      changeset = User.profile_changeset(%User{}, %{display_name: "", language: "fr"})

      conn = fallback({:error, changeset})

      assert conn.status == 422
      assert body(conn)["error"]["code"] == "validation_failed"
      assert body(conn)["error"]["details"]["fields"]["language"] == ["is invalid"]
    end

    @tag req: ["FR-919"]
    test "turns :not_found into a 404" do
      conn = fallback({:error, :not_found})

      assert conn.status == 404
      assert body(conn)["error"]["code"] == "not_found"
    end

    @tag req: ["NFR-201"]
    test "turns :unauthorized into a 403, not a 404" do
      conn = fallback({:error, :unauthorized})

      assert conn.status == 403
      assert body(conn)["error"]["code"] == "forbidden"
    end

    @tag req: ["FR-401"]
    test "carries details when a context supplies them" do
      conn = fallback({:error, :vote_budget_exceeded, %{budget: 5, used: 5}})

      assert conn.status == 422
      assert body(conn)["error"]["details"] == %{"budget" => 5, "used" => 5}
    end

    @tag req: ["FR-919"]
    test "turns a bare error code into its status" do
      conn = fallback({:error, :session_closed})

      assert conn.status == 422
      assert body(conn)["error"]["code"] == "session_closed"
    end

    @tag req: ["FR-919"]
    test "treats a nil result as not found rather than crashing" do
      conn = fallback(nil)

      assert conn.status == 404
    end
  end

  describe "changeset_errors/1" do
    @tag req: ["FR-906"]
    test "translates the messages" do
      changeset = User.profile_changeset(%User{}, %{display_name: ""})

      assert %{display_name: ["can't be blank"]} = FallbackController.changeset_errors(changeset)
    end

    @tag req: ["FR-906"]
    test "interpolates counted messages" do
      changeset =
        User.profile_changeset(%User{}, %{
          display_name: "Nok",
          avatar_url: String.duplicate("x", 501)
        })

      assert [message] = FallbackController.changeset_errors(changeset).avatar_url
      assert message =~ "500"
    end
  end
end
