defmodule SprintLensWeb.Plugs.LocaleTest do
  use SprintLensWeb.ConnCase

  import SprintLens.AccountsFixtures

  alias SprintLens.Accounts
  alias SprintLens.Accounts.Scope
  alias SprintLensWeb.Locale
  alias SprintLensWeb.Plugs.Locale, as: LocalePlug

  setup do
    on_exit(fn -> Locale.put(Locale.default()) end)
    :ok
  end

  defp call(conn), do: LocalePlug.call(conn, LocalePlug.init([]))

  describe "call/2" do
    @tag req: ["FR-906"]
    test "defaults a visitor with no preferences to Thai" do
      conn = :get |> Phoenix.ConnTest.build_conn("/") |> call()

      assert conn.assigns.locale == "th"
      assert Locale.current() == "th"
    end

    @tag req: ["FR-906"]
    test "honours the browser's accept-language for a signed-out visitor" do
      conn =
        :get
        |> Phoenix.ConnTest.build_conn("/")
        |> Plug.Conn.put_req_header("accept-language", "en-GB,en;q=0.9")
        |> call()

      assert conn.assigns.locale == "en"
    end

    @tag req: ["FR-907"]
    test "a signed-in user's saved language beats the browser header" do
      user = user_fixture()
      {:ok, user} = Accounts.update_user_profile(user, %{language: "en"})

      conn =
        :get
        |> Phoenix.ConnTest.build_conn("/")
        |> Plug.Conn.assign(:current_scope, Scope.for_user(user))
        |> Plug.Conn.put_req_header("accept-language", "th")
        |> call()

      assert conn.assigns.locale == "en"
    end

    @tag req: ["FR-906"]
    test "works before the auth pipeline has assigned a scope" do
      conn = :get |> Phoenix.ConnTest.build_conn("/") |> call()

      assert conn.assigns.locale == "th"
    end

    @tag req: ["FR-906"]
    test "init/1 passes its options through" do
      assert LocalePlug.init(:opts) == :opts
    end
  end

  describe "in the router pipeline" do
    @tag req: ["FR-906"]
    test "the page renders in Thai for a fresh visitor", %{conn: conn} do
      html = conn |> get(~p"/") |> html_response(200)

      assert html =~ ~s(lang="th")
      assert html =~ "เข้าสู่ระบบ"
    end

    @tag req: ["FR-907"]
    test "the page renders in English for a user who chose it", %{conn: conn} do
      user = user_fixture()
      {:ok, user} = Accounts.update_user_profile(user, %{language: "en"})

      html = conn |> log_in_user(user) |> get(~p"/") |> html_response(200)

      assert html =~ ~s(lang="en")
      assert html =~ "Log out"
    end

    @tag req: ["FR-911"]
    test "a saved theme is stamped on the html element before any script runs", %{conn: conn} do
      user = user_fixture()
      {:ok, user} = Accounts.update_user_profile(user, %{theme: "dark"})

      html = conn |> log_in_user(user) |> get(~p"/") |> html_response(200)

      assert html =~ ~s(data-theme="dark")
      assert html =~ ~s(data-theme-source="user")
    end

    @tag req: ["FR-910"]
    test "a user following the system leaves the theme for the client to resolve", %{conn: conn} do
      html = conn |> log_in_user(user_fixture()) |> get(~p"/") |> html_response(200)

      assert html =~ ~s(data-theme-source="system")
      refute html =~ ~s(data-theme="dark")
    end
  end
end
