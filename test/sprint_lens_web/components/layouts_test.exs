defmodule SprintLensWeb.LayoutsTest do
  use SprintLens.UnitCase, async: true

  # Asserts on English copy, so it says so rather than reading the Thai
  # translation table back to itself.
  @moduletag locale: "en"

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

  describe "logo/1" do
    @tag req: ["FR-911"]
    test "draws the mark inline so it can take the colour beside it" do
      html = render_component(&Layouts.logo/1, %{})

      assert html =~ ~s(fill="currentColor")
      assert html =~ ~s(fill-rule="evenodd")
      # The two cards, as one path with the overlap knocked out.
      assert html =~ "<path"
      refute html =~ "<img"
    end

    # Decorative: the wordmark beside it is real text, and describing the image
    # would make a screen reader say the name twice.
    @tag req: ["FR-913"]
    test "is hidden from assistive technology" do
      assert render_component(&Layouts.logo/1, %{}) =~ ~s(aria-hidden="true")
    end

    @tag req: ["FR-911"]
    test "takes the size and colour it is given" do
      html = render_component(&Layouts.logo/1, %{class: "size-10 text-primary"})

      assert html =~ ~s(class="size-10 text-primary")
    end

    # The drawing is read from the file at compile time; a component that
    # rendered an empty path would still look like valid markup.
    @tag req: ["FR-911"]
    test "carries the same path data as the file the icons are built from" do
      [_whole, from_file] =
        Regex.run(~r/\sd="([^"]+)"/, File.read!("priv/static/images/logo-mark.svg"))

      assert render_component(&Layouts.logo/1, %{}) =~
               from_file |> String.split() |> Enum.join(" ")
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
    test "every option is a link, so it is keyboard operable and works without JavaScript" do
      html = render_component(&Layouts.theme_toggle/1, %{})

      assert html |> String.split("<a ") |> length() == 4
    end

    @tag req: ["FR-910"]
    test "each option navigates to the controller that stores the choice" do
      html = render_component(&Layouts.theme_toggle/1, %{current_path: "/teams/7"})

      assert html =~ ~s(href="/theme/light?return_to=%2Fteams%2F7")
      assert html =~ ~s(href="/theme/dark?return_to=%2Fteams%2F7")
      assert html =~ ~s(href="/theme/system?return_to=%2Fteams%2F7")
    end

    # Not `aria-current`: the phase bar and the discussion focus already use
    # it, and both suites find the active phase by taking the first
    # `[aria-current="true"]` in the document. This sits above them.
    @tag req: ["FR-910"]
    test "the active option says so in text rather than only in colour" do
      html = render_component(&Layouts.theme_toggle/1, %{theme: "dark"})

      assert html =~ ~s(aria-label="Dark theme, current")
      refute html =~ "aria-current"
    end
  end

  describe "language_switcher/1" do
    @tag req: ["FR-907"]
    test "offers every supported language as a link back to the current page" do
      html = render_component(&Layouts.language_switcher/1, %{current_path: "/sessions/3"})

      assert html =~ ~s(href="/locale/th?return_to=%2Fsessions%2F3")
      assert html =~ ~s(href="/locale/en?return_to=%2Fsessions%2F3")
    end

    # The whole point of the change: a link works on a controller-rendered
    # page, and `JS.push` did not.
    @tag req: ["FR-907"]
    test "pushes no LiveView event, so it works where there is no live process" do
      html = render_component(&Layouts.language_switcher/1, %{})

      refute html =~ "phx-click"
      refute html =~ "set_language"
    end

    @tag req: ["FR-907"]
    test "the active language is announced, not only highlighted" do
      html = render_component(&Layouts.language_switcher/1, %{locale: "en"})

      assert html =~ ~s(class="sr-only">current</span>)
      refute html =~ "aria-current"
    end
  end
end
