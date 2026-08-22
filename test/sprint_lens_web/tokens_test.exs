defmodule SprintLensWeb.TokensTest do
  @moduledoc """
  The design tokens, read from the stylesheet that defines them.

  Same reasoning as `SprintLensWeb.ContrastTest`: these are properties of the
  values themselves, so the test computes them from the values themselves
  rather than opening one page at a time and hoping the right one was
  remembered.

  What it is really guarding is the reduced-motion contract. Every animation
  in the interface reads a duration token, which is what lets the preference
  be honoured once here instead of at each animation — and which means one
  token added later without its reduced-motion counterpart would silently opt
  a whole component out of it.
  """

  use SprintLens.UnitCase, async: true

  @stylesheet "assets/css/tokens.css"

  defp source, do: File.read!(@stylesheet)

  defp block(pattern) do
    [[body]] = Regex.scan(pattern, source(), capture: :all_but_first)

    body
  end

  defp tokens(body, prefix) do
    ~r/--(#{prefix}[a-z-]+):/
    |> Regex.scan(body, capture: :all_but_first)
    |> Enum.map(&hd/1)
    |> MapSet.new()
  end

  describe "motion" do
    @tag req: ["FR-916"]
    test "every duration is collapsed under a reduced motion preference" do
      defined = ~r/^:root \{(.*?)^\}/ms |> block() |> tokens("sl-duration-")

      collapsed =
        ~r/@media \(prefers-reduced-motion: reduce\) \{(.*?)^\}/ms
        |> block()
        |> tokens("sl-duration-")

      assert MapSet.size(defined) > 0, "no duration tokens found at all"

      assert MapSet.difference(defined, collapsed) |> MapSet.to_list() == [],
             """
             A duration token is not overridden under `prefers-reduced-motion`.

             Anything animating with it would keep moving for somebody who
             asked it not to, and nothing else in the interface checks.
             """
    end

    # Collapsed, not removed. FR-916's reduced variant is an instant state
    # change rather than the absence of feedback: a card still has to land.
    @tag req: ["FR-916"]
    test "and collapsed to something instant rather than to nothing" do
      reduced = block(~r/@media \(prefers-reduced-motion: reduce\) \{(.*?)^\}/ms)

      for [value] <-
            Regex.scan(~r/--sl-duration-[a-z]+: ([^;]+);/, reduced, capture: :all_but_first) do
        assert value == "1ms", "expected an instant duration, got #{value}"
      end
    end
  end

  describe "elevation" do
    # A shadow the same colour as the surface behind it is not a shadow.
    @tag req: ["FR-912"]
    test "is redefined for the dark theme" do
      light = ~r/^:root \{(.*?)^\}/ms |> block() |> tokens("sl-shadow-")
      dark = ~r/^\[data-theme="dark"\] \{(.*?)^\}/ms |> block() |> tokens("sl-shadow-")

      assert MapSet.equal?(light, dark),
             "the two themes define different shadow tokens: #{inspect(light)} vs #{inspect(dark)}"
    end
  end

  describe "focus" do
    # It currently inherits whatever daisyUI provides, which disappears when
    # daisyUI does. FR-914 wants every action keyboard operable, and a control
    # whose focus nobody can see is only half of that.
    @tag req: ["FR-914"]
    test "is the project's own, and only for a keyboard" do
      css = source()

      assert css =~ ":focus-visible"
      assert css =~ "outline: var(--sl-focus-width)"
      refute css =~ ~r/[^-]:focus\b(?!-visible)/, "focus styling should not apply to mouse clicks"
    end
  end
end
