defmodule SprintLensWeb.ThemeControllerTest do
  use SprintLensWeb.ConnCase

  import Ecto.Query

  alias SprintLens.Accounts

  describe "the toggle on a page with no live process" do
    @tag req: ["FR-910"]
    test "renders a real link per theme", %{conn: conn} do
      html = conn |> get(~p"/") |> html_response(200)

      assert html =~ ~s(href="/theme/light?return_to=%2F")
      assert html =~ ~s(href="/theme/dark?return_to=%2F")
      assert html =~ ~s(href="/theme/system?return_to=%2F")
    end

    # The half that used to be lost. The client repainted, nothing was stored,
    # and the next request handed back the operating system's preference.
    @tag req: ["FR-911"]
    test "a signed-out choice is stamped on the next page before it paints", %{conn: conn} do
      conn = conn |> get(~p"/theme/dark?return_to=%2F") |> recycle()

      html = conn |> get(~p"/") |> html_response(200)

      assert html =~ ~s(data-theme="dark")
      assert html =~ ~s(data-theme-source="user")
    end

    @tag req: ["FR-910"]
    test "system leaves the resolution to the browser", %{conn: conn} do
      conn = conn |> get(~p"/theme/system?return_to=%2F") |> recycle()

      html = conn |> get(~p"/") |> html_response(200)

      assert html =~ ~s(data-theme-source="system")
      refute html =~ ~s(data-theme=")
    end

    @tag req: ["FR-910"]
    test "an unsupported theme is not stored in the session", %{conn: conn} do
      conn = conn |> get(~p"/theme/neon?return_to=%2F") |> recycle()

      assert conn |> get(~p"/") |> html_response(200) =~ ~s(data-theme-source="system")
    end

    @tag req: ["NFR-203"]
    test "the return path cannot be pointed at another host", %{conn: conn} do
      assert conn |> get(~p"/theme/dark?return_to=//evil.example.com") |> redirected_to() == "/"
    end

    @tag req: ["FR-910"]
    test "with no return path it lands on the home page", %{conn: conn} do
      assert conn |> get(~p"/theme/dark") |> redirected_to() == "/"
    end
  end

  describe "storing the choice" do
    setup :register_and_log_in_user

    @tag req: ["FR-911"]
    test "a signed-in visitor gets it written to their profile", %{conn: conn, user: user} do
      conn |> get(~p"/theme/dark?return_to=%2Fhome") |> redirected_to()

      assert Accounts.get_user!(user.id).theme == "dark"
    end

    @tag req: ["FR-910"]
    test "an unsupported theme is ignored rather than stored", %{conn: conn, user: user} do
      assert conn |> get(~p"/theme/neon?return_to=%2F") |> redirected_to() == "/"
      assert Accounts.get_user!(user.id).theme == "system"
    end

    @tag req: ["FR-919"]
    test "a profile that cannot be written gives up quietly", %{conn: conn, user: user} do
      SprintLens.Repo.update_all(
        from(u in SprintLens.Accounts.User, where: u.id == ^user.id),
        set: [display_name: ""]
      )

      assert conn |> get(~p"/theme/dark?return_to=%2F") |> redirected_to() == "/"
      assert Accounts.get_user!(user.id).theme == "system"
    end
  end
end
