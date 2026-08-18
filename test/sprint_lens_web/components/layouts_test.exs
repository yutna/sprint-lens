defmodule SprintLensWeb.LayoutsTest do
  use SprintLens.UnitCase, async: true

  import Phoenix.LiveViewTest

  alias SprintLensWeb.Layouts

  defp inner(text) do
    [%{__slot__: :inner_block, inner_block: fn _assigns, _ -> text end}]
  end

  describe "app/1" do
    @tag req: ["FR-917"]
    test "wraps the page content" do
      html =
        render_component(&Layouts.app/1, %{flash: %{}, inner_block: inner("Board goes here")})

      assert html =~ "Board goes here"
      assert html =~ "<main"
    end

    @tag req: ["FR-910"]
    test "includes the theme toggle on every page" do
      html = render_component(&Layouts.app/1, %{flash: %{}, inner_block: inner("x")})

      assert html =~ ~s(data-phx-theme="system")
    end

    @tag req: ["FR-919"]
    test "surfaces flash messages" do
      html =
        render_component(&Layouts.app/1, %{
          flash: %{"info" => "Session closed"},
          inner_block: inner("x")
        })

      assert html =~ "Session closed"
    end
  end

  describe "flash_group/1" do
    @tag req: ["FR-915"]
    test "is a polite live region, so notices reach assistive technology" do
      html = render_component(&Layouts.flash_group/1, flash: %{})

      assert html =~ ~s(aria-live="polite")
    end

    @tag req: ["FR-918"]
    test "carries a persistent reconnecting banner driven by socket state" do
      html = render_component(&Layouts.flash_group/1, flash: %{})

      assert html =~ ~s(id="client-error")
      assert html =~ ~s(id="server-error")
      assert html =~ "phx-disconnected"
      assert html =~ "phx-connected"
      assert html =~ "Attempting to reconnect"
    end

    @tag req: ["FR-919"]
    test "renders both info and error flashes" do
      html =
        render_component(&Layouts.flash_group/1, flash: %{"info" => "Saved", "error" => "Nope"})

      assert html =~ "Saved"
      assert html =~ "Nope"
    end

    @tag req: ["FR-919"]
    test "accepts a custom container id" do
      assert render_component(&Layouts.flash_group/1, flash: %{}, id: "my-flashes") =~
               ~s(id="my-flashes")
    end
  end

  describe "theme_toggle/1" do
    @tag req: ["FR-910"]
    test "offers exactly light, dark and system" do
      html = render_component(&Layouts.theme_toggle/1, %{})

      assert html =~ ~s(data-phx-theme="system")
      assert html =~ ~s(data-phx-theme="light")
      assert html =~ ~s(data-phx-theme="dark")
    end

    @tag req: ["FR-914"]
    test "every option is a real button, so it is keyboard operable" do
      html = render_component(&Layouts.theme_toggle/1, %{})

      assert html |> String.split("<button") |> length() == 4
    end

    @tag req: ["FR-910"]
    test "dispatches the theme event the client script listens for" do
      assert render_component(&Layouts.theme_toggle/1, %{}) =~ "phx:set-theme"
    end
  end
end
