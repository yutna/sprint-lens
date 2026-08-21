defmodule SprintLensWeb.Plugs.ThemeTest do
  use SprintLensWeb.ConnCase

  import SprintLens.AccountsFixtures

  alias SprintLens.Accounts
  alias SprintLens.Accounts.Scope
  alias SprintLensWeb.Plugs.Theme, as: ThemePlug

  defp call(conn), do: ThemePlug.call(conn, ThemePlug.init([]))

  describe "call/2" do
    # Not a contrived case: the plug runs before the session is fetched in
    # some pipelines, and is exercised directly here. Neither is a reason to
    # fail a request.
    @tag req: ["FR-910"]
    test "a request with no session at all resolves to system" do
      conn = :get |> Phoenix.ConnTest.build_conn("/") |> call()

      assert conn.assigns.theme == "system"
    end

    @tag req: ["FR-910"]
    test "a signed-out visitor gets the choice stored in their session", %{conn: conn} do
      conn =
        conn
        |> Plug.Test.init_test_session(theme: "dark")
        |> call()

      assert conn.assigns.theme == "dark"
    end

    @tag req: ["FR-911"]
    test "a signed-in user's profile wins over the session", %{conn: conn} do
      {:ok, user} = Accounts.update_user_profile(user_fixture(), %{theme: "light"})

      conn =
        conn
        |> Plug.Test.init_test_session(theme: "dark")
        |> Plug.Conn.assign(:current_scope, Scope.for_user(user))
        |> call()

      assert conn.assigns.theme == "light"
    end
  end
end
