defmodule SprintLensWeb.LocaleControllerTest do
  use SprintLensWeb.ConnCase

  import Ecto.Query

  alias SprintLens.Accounts

  describe "the switcher on a page with no live process" do
    # This is the defect. The landing page is a plain controller, the switcher
    # pushed a LiveView event, and the click had nowhere to go. Nothing in the
    # old suite could have caught it: every test that exercised the switcher
    # reached its page through `live/2`, so a live process existed by
    # construction.
    @tag req: ["FR-907"]
    test "renders a real link carrying the page to come back to", %{conn: conn} do
      html = conn |> get(~p"/") |> html_response(200)

      assert html =~ ~s(href="/locale/en?return_to=%2F")
      assert html =~ ~s(href="/locale/th?return_to=%2F")
    end

    @tag req: ["FR-907"]
    test "following that link changes the language and comes back", %{conn: conn} do
      conn = get(conn, ~p"/locale/en?return_to=%2F")

      assert redirected_to(conn) == "/"

      html = conn |> recycle() |> get(~p"/") |> html_response(200)

      assert html =~ ~s(lang="en")
      assert html =~ "Log in"
      refute html =~ "เข้าสู่ระบบ"
    end

    @tag req: ["FR-907"]
    test "the choice survives a reload", %{conn: conn} do
      conn = conn |> get(~p"/locale/en?return_to=%2F") |> recycle()

      assert conn |> get(~p"/") |> html_response(200) =~ ~s(lang="en")
    end
  end

  describe "storing the choice" do
    setup :register_and_log_in_user

    @tag req: ["FR-907"]
    test "a signed-in visitor gets it written to their profile", %{conn: conn, user: user} do
      conn |> get(~p"/locale/en?return_to=%2Fhome") |> redirected_to()

      assert Accounts.get_user!(user.id).language == "en"
    end

    @tag req: ["FR-906"]
    test "an unsupported language is ignored rather than stored", %{conn: conn, user: user} do
      assert conn |> get(~p"/locale/fr?return_to=%2F") |> redirected_to() == "/"
      assert Accounts.get_user!(user.id).language == "th"
    end

    @tag req: ["FR-919"]
    test "a profile that cannot be written gives up quietly", %{conn: conn, user: user} do
      # A profile row that no longer satisfies its own validations — the shape
      # a bad data migration leaves behind. Changing the language must not
      # turn into an error page.
      SprintLens.Repo.update_all(
        from(u in SprintLens.Accounts.User, where: u.id == ^user.id),
        set: [display_name: ""]
      )

      assert conn |> get(~p"/locale/en?return_to=%2F") |> redirected_to() == "/"
      assert Accounts.get_user!(user.id).language == "th"
    end
  end

  describe "without an account" do
    @tag req: ["FR-906"]
    test "an unsupported language is not stored in the session", %{conn: conn} do
      conn = conn |> get(~p"/locale/fr?return_to=%2F") |> recycle()

      assert conn |> get(~p"/") |> html_response(200) =~ ~s(lang="th")
    end

    @tag req: ["NFR-203"]
    test "the return path cannot be pointed at another host", %{conn: conn} do
      assert conn |> get(~p"/locale/en?return_to=//evil.example.com") |> redirected_to() == "/"
    end

    @tag req: ["FR-907"]
    test "with no return path it lands on the home page", %{conn: conn} do
      assert conn |> get(~p"/locale/en") |> redirected_to() == "/"
    end
  end
end
