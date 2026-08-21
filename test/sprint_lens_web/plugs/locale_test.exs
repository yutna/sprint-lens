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

  describe "on the API pipelines" do
    # Every message in `SprintLensWeb.ApiError` is wrapped and fully
    # translated, and none of them reached a locale: the public pipeline had
    # no resolution at all, and the authenticated one only switched language
    # after the token had been accepted — which the two refusals a client
    # meets most often never get to.
    @tag req: ["FR-906"]
    test "the token exchange refuses in the caller's language", %{conn: conn} do
      body =
        conn
        |> put_req_header("accept-language", "th")
        |> post(~p"/api/v1/tokens", %{email: "nobody@example.com", password: "wrong-password"})
        |> json_response(401)

      assert body["error"]["message"] =~ ~r/\p{Thai}/u
    end

    @tag req: ["FR-906"]
    test "and in English when that is what the caller asked for", %{conn: conn} do
      body =
        conn
        |> put_req_header("accept-language", "en-GB,en;q=0.9")
        |> post(~p"/api/v1/tokens", %{email: "nobody@example.com", password: "wrong-password"})
        |> json_response(401)

      refute body["error"]["message"] =~ ~r/\p{Thai}/u
    end

    @tag req: ["FR-906"]
    test "a request with no token at all is refused in the caller's language", %{conn: conn} do
      body =
        conn
        |> put_req_header("accept-language", "en")
        |> get(~p"/api/v1/me")
        |> json_response(401)

      refute body["error"]["message"] =~ ~r/\p{Thai}/u
    end

    @tag req: ["FR-907"]
    test "an authenticated caller gets their own language, not the header's", %{conn: conn} do
      user = user_fixture()
      {:ok, user} = Accounts.update_user_profile(user, %{language: "th"})
      token = Accounts.create_api_token(user)

      body =
        conn
        |> put_req_header("authorization", "Bearer " <> token)
        |> put_req_header("accept-language", "en")
        |> get(~p"/api/v1/teams/999999")
        |> json_response(404)

      assert body["error"]["message"] =~ ~r/\p{Thai}/u
    end
  end

  describe "the first paint and the connected render" do
    # The flicker. The plug saw the browser's `accept-language`; the LiveView
    # hook re-resolved without it, because the header is not part of the
    # session. A signed-out visitor whose browser asks for English therefore
    # got an English page that turned Thai the moment the socket connected.
    @tag req: ["FR-906"]
    test "agree for a signed-out visitor whose browser asks for English", %{conn: conn} do
      conn = put_req_header(conn, "accept-language", "en")

      dead = conn |> get(~p"/users/log-in") |> html_response(200)
      assert dead =~ ~s(lang="en")
      refute dead =~ "เข้าสู่ระบบ"

      {:ok, _lv, connected} = Phoenix.LiveViewTest.live(conn, ~p"/users/log-in")

      # Not a blanket check for Thai script: the language switcher's own label
      # for Thai is the word "ไทย" in every language, and always should be.
      assert connected =~ ~s(lang="en")
      refute connected =~ "เข้าสู่ระบบ"
    end

    @tag req: ["FR-906"]
    test "and agree on Thai when the browser asks for nothing", %{conn: conn} do
      dead = conn |> get(~p"/users/log-in") |> html_response(200)
      assert dead =~ ~s(lang="th")
      assert dead =~ "เข้าสู่ระบบ"

      {:ok, _lv, connected} = Phoenix.LiveViewTest.live(conn, ~p"/users/log-in")

      assert connected =~ ~s(lang="th")
      assert connected =~ "เข้าสู่ระบบ"
    end
  end
end
