defmodule SprintLensWeb.UserLive.PreferencesTest do
  use SprintLensWeb.ConnCase

  import Ecto.Query
  import Phoenix.LiveViewTest

  alias SprintLens.Accounts

  setup :register_and_log_in_user

  describe "SCR-13 Preferences" do
    @tag req: ["FR-003"]
    test "shows the profile form", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/users/preferences")

      assert html =~ "preferences_form"
      assert html =~ "ชื่อที่แสดง"
    end

    @tag req: ["FR-003"]
    test "saves the display name and avatar", %{conn: conn, user: user} do
      {:ok, lv, _html} = live(conn, ~p"/users/preferences")

      lv
      |> form("#preferences_form",
        user: %{display_name: "นก", avatar_url: "https://example.com/n.png"}
      )
      |> render_submit()

      updated = Accounts.get_user!(user.id)
      assert updated.display_name == "นก"
      assert updated.avatar_url == "https://example.com/n.png"
    end

    @tag req: ["FR-907"]
    test "switching to English re-renders in English by live navigation", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/preferences")

      {:ok, _lv, html} =
        lv
        |> form("#preferences_form", user: %{language: "en"})
        |> render_submit()
        |> follow_redirect(conn, ~p"/users/preferences")

      assert html =~ "Display name"
      refute html =~ "ชื่อที่แสดง"
    end

    @tag req: ["FR-907"]
    test "the language choice persists to the profile", %{conn: conn, user: user} do
      {:ok, lv, _html} = live(conn, ~p"/users/preferences")

      lv |> form("#preferences_form", user: %{language: "en"}) |> render_submit()

      assert Accounts.get_user!(user.id).language == "en"
    end

    @tag req: ["FR-910", "FR-911"]
    test "the theme choice persists to the profile", %{conn: conn, user: user} do
      {:ok, lv, _html} = live(conn, ~p"/users/preferences")

      lv |> form("#preferences_form", user: %{theme: "dark"}) |> render_submit()

      assert Accounts.get_user!(user.id).theme == "dark"
    end

    @tag req: ["FR-919"]
    test "shows an error rather than saving an empty display name", %{conn: conn, user: user} do
      {:ok, lv, _html} = live(conn, ~p"/users/preferences")

      html = lv |> form("#preferences_form", user: %{display_name: ""}) |> render_submit()

      assert html =~ "input-error" or html =~ "ต้องไม่เว้นว่าง"
      assert Accounts.get_user!(user.id).display_name == user.display_name
    end

    @tag req: ["FR-919"]
    test "validates as the user types", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/preferences")

      html = lv |> form("#preferences_form", user: %{display_name: ""}) |> render_change()

      assert html =~ "input-error"
    end

    @tag req: ["FR-003"]
    test "requires a session", %{conn: _conn} do
      assert {:error, {:redirect, %{to: "/users/log-in"}}} =
               live(build_conn(), ~p"/users/preferences")
    end

    @tag req: ["FR-003"]
    test "does not demand a recent authentication, unlike account settings", %{user: user} do
      # Simulate a session from days ago: sudo mode has long lapsed.
      conn = log_in_user(build_conn(), user, token_authenticated_at: days_ago(3))
      assert {:ok, _lv, _html} = live(conn, ~p"/users/preferences")

      assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/users/settings")
    end
  end

  describe "live switchers in the layout" do
    @tag req: ["FR-907"]
    test "the language switcher applies immediately and persists", %{conn: conn, user: user} do
      {:ok, lv, _html} = live(conn, ~p"/users/preferences")

      {:ok, _lv, html} =
        lv
        |> render_click("set_language", %{"language" => "en"})
        |> follow_redirect(conn, ~p"/users/preferences")

      assert html =~ "Display name"
      assert Accounts.get_user!(user.id).language == "en"
    end

    @tag req: ["FR-910", "FR-911"]
    test "the theme switcher persists to the profile", %{conn: conn, user: user} do
      {:ok, lv, _html} = live(conn, ~p"/users/preferences")

      render_click(lv, "set_theme", %{"theme" => "dark"})

      assert Accounts.get_user!(user.id).theme == "dark"
    end

    @tag req: ["FR-906"]
    test "an unsupported language is ignored rather than stored", %{conn: conn, user: user} do
      {:ok, lv, _html} = live(conn, ~p"/users/preferences")

      render_click(lv, "set_language", %{"language" => "fr"})

      assert Accounts.get_user!(user.id).language == "th"
    end

    @tag req: ["FR-910"]
    test "an unsupported theme is ignored rather than stored", %{conn: conn, user: user} do
      {:ok, lv, _html} = live(conn, ~p"/users/preferences")

      render_click(lv, "set_theme", %{"theme" => "neon"})

      assert Accounts.get_user!(user.id).theme == "system"
    end

    @tag req: ["FR-907"]
    test "a signed-out visitor switches through the session, since they have no profile" do
      conn = build_conn()
      {:ok, lv, _html} = live(conn, ~p"/users/log-in")

      # No profile to write to, so the choice goes into the session cookie.
      assert {:error, {:redirect, %{to: to}}} =
               render_click(lv, "set_language", %{"language" => "en"})

      assert to =~ "/locale/en"
      assert to =~ "return_to=%2Fusers%2Flog-in"

      html = conn |> get(to) |> follow_redirect_html(~p"/users/log-in")

      assert html =~ "Log in"
      refute html =~ "เข้าสู่ระบบ"
    end

    @tag req: ["FR-907"]
    test "the session choice survives the next request", %{conn: _conn} do
      conn = build_conn() |> get(~p"/locale/en?return_to=%2F")

      assert conn |> recycle() |> get(~p"/") |> html_response(200) =~ ~s(lang="en")
    end

    @tag req: ["NFR-203"]
    test "the return path cannot be pointed at another host" do
      conn = build_conn() |> get(~p"/locale/en?return_to=//evil.example.com")

      assert redirected_to(conn) == "/"
    end

    @tag req: ["FR-907"]
    test "with no return path it lands on the home page" do
      assert build_conn() |> get(~p"/locale/en") |> redirected_to() == "/"
    end

    @tag req: ["FR-910"]
    test "a signed-out visitor can change the theme, with nothing to persist to" do
      {:ok, lv, _html} = live(build_conn(), ~p"/users/log-in")

      # The client repaints from the dispatched event; there is no profile to
      # write to, and that must not be an error.
      assert render_click(lv, "set_theme", %{"theme" => "dark"}) =~ "login_form_magic"
    end

    @tag req: ["FR-906"]
    test "an unsupported language is not stored in the session" do
      conn = build_conn() |> get(~p"/locale/fr?return_to=%2F")

      assert conn |> recycle() |> get(~p"/") |> html_response(200) =~ ~s(lang="th")
    end
  end

  describe "when the profile cannot be written" do
    @tag req: ["FR-919"]
    test "the switcher gives up quietly instead of crashing the page", %{
      conn: conn,
      user: user
    } do
      # A profile row that no longer satisfies its own validations — the shape
      # a bad data migration leaves behind. Changing the theme must not take
      # the page down with it.
      SprintLens.Repo.update_all(
        from(u in SprintLens.Accounts.User, where: u.id == ^user.id),
        set: [display_name: ""]
      )

      {:ok, lv, _html} = live(conn, ~p"/users/preferences")

      assert render_click(lv, "set_theme", %{"theme" => "dark"}) =~ "preferences_form"
      assert Accounts.get_user!(user.id).theme == "system"
    end
  end

  defp follow_redirect_html(conn, to) do
    assert redirected_to(conn) == to

    conn |> recycle() |> get(to) |> html_response(200)
  end

  defp days_ago(days) do
    DateTime.utc_now(:second) |> DateTime.add(-days, :day)
  end
end
