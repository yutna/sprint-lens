defmodule SprintLensWeb.UserLive.PreferencesTest do
  use SprintLensWeb.ConnCase

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

  defp days_ago(days) do
    DateTime.utc_now(:second) |> DateTime.add(-days, :day)
  end
end
