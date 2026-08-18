defmodule SprintLensWeb.UserLive.ForgotPasswordTest do
  use SprintLensWeb.ConnCase

  import Phoenix.LiveViewTest
  import SprintLens.AccountsFixtures

  alias SprintLens.Accounts
  alias SprintLens.Accounts.UserToken
  alias SprintLens.Repo

  @moduletag req: ["FR-004"]

  describe "the password reset page" do
    test "is reachable from the login page", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/users/log-in")

      assert html =~ ~p"/users/reset-password"
    end

    test "renders the form", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/users/reset-password")

      assert html =~ "forgot_password_form"
    end

    test "emails a sign-in link to a registered address", %{conn: conn} do
      user = user_fixture()
      {:ok, lv, _html} = live(conn, ~p"/users/reset-password")

      lv |> form("#forgot_password_form", user: %{email: user.email}) |> render_submit()

      assert Repo.get_by!(UserToken, user_id: user.id, context: "login")
    end

    test "says the same thing for an address with no account", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/reset-password")

      {:ok, _lv, html} =
        lv
        |> form("#forgot_password_form", user: %{email: "ghost@example.com"})
        |> render_submit()
        |> follow_redirect(conn, ~p"/users/log-in")

      assert html =~ "ถ้าอีเมลนี้มีบัญชีอยู่"
      assert Repo.aggregate(UserToken, :count) == 0
    end

    test "the emailed link signs the user in so they can choose a new password", %{conn: conn} do
      user = user_fixture()

      token =
        extract_user_token(fn url ->
          Accounts.deliver_password_reset_instructions(user, url)
        end)

      {:ok, lv, _html} = live(conn, ~p"/users/log-in/#{token}")

      form = form(lv, "#login_form", %{"user" => %{"token" => token}})
      conn = submit_form(form, conn)

      assert get_session(conn, :user_token)
    end
  end
end
