defmodule SprintLensWeb.ContrastTest do
  @moduledoc """
  Text contrast in both themes (FR-912, FR-913).

  ## Why this reads the stylesheet

  FR-913 asks for "at least 4.5 to 1 in both themes" and FR-912 says both
  themes must meet it. That is a property of the colours themselves, so the
  test computes it from the colours themselves — parsing the two daisyUI
  theme blocks out of `assets/css/app.css` and doing the WCAG arithmetic.

  A browser-based audit would test the same thing more slowly, on one page at
  a time, and would pass or fail depending on which page somebody remembered
  to include. Reading the palette tests every page at once, including the
  ones nobody has written yet.

  ## What the arithmetic is

  WCAG 2.1's contrast ratio is `(L1 + 0.05) / (L2 + 0.05)` over relative
  luminance. The colours are in OKLCH, so they are converted to linear sRGB
  first — the conversion is the published one, and its own correctness is
  checked against known values below.
  """

  use SprintLens.UnitCase, async: true

  @stylesheet "assets/css/app.css"

  # The project's own layer, where the colours that are not daisyUI's live.
  @tokens "assets/css/tokens.css"

  # WCAG 2.1 AA for body text (FR-913).
  @minimum 4.5

  describe "the palette" do
    @tag req: ["FR-912", "FR-913"]
    test "body text on every surface passes AA, in both themes" do
      for {theme, colors} <- themes() do
        text = colors["base-content"]

        for surface <- ~w(base-100 base-200 base-300) do
          ratio = contrast(text, colors[surface])

          assert ratio >= @minimum,
                 "#{theme}: base-content on #{surface} is #{Float.round(ratio, 2)}:1"
        end
      end
    end

    @tag req: ["FR-912", "FR-913"]
    test "and so does the text on every coloured button" do
      pairs = ~w(primary secondary accent neutral info success warning error)

      for {theme, colors} <- themes(), role <- pairs do
        ratio = contrast(colors["#{role}-content"], colors[role])

        assert ratio >= @minimum,
               "#{theme}: #{role}-content on #{role} is #{Float.round(ratio, 2)}:1"
      end
    end

    # The hole this test used to have. It checked `base-content` on surfaces
    # and `{role}-content` on `{role}`, which is every pair a *filled* thing
    # uses — and none of the pairs a coloured *word* uses. `text-primary` was
    # 2.60:1 on the dark theme's own background, in six places including the
    # sign-in page, and nothing here objected.
    @tag req: ["FR-912", "FR-913"]
    test "and so does a link, which is a colour on a surface rather than a fill" do
      for {theme, colors} <- themes(), surface <- ~w(base-100 base-200 base-300) do
        ratio = contrast(link_color(theme), colors[surface])

        assert ratio >= @minimum,
               "#{theme}: the link colour on #{surface} is #{Float.round(ratio, 2)}:1"
      end
    end

    @tag req: ["FR-910", "FR-912"]
    test "there are exactly two themes, and they are the ones the app offers" do
      assert themes() |> Map.keys() |> Enum.sort() == ["dark", "light"]
    end
  end

  describe "the arithmetic itself" do
    @tag req: ["FR-913"]
    test "black on white is 21 to 1, the maximum there is" do
      assert_in_delta contrast("oklch(0% 0 0)", "oklch(100% 0 0)"), 21.0, 0.3
    end

    @tag req: ["FR-913"]
    test "a colour against itself is 1 to 1" do
      assert_in_delta contrast("oklch(58% 0.233 277.117)", "oklch(58% 0.233 277.117)"), 1.0, 0.001
    end

    @tag req: ["FR-913"]
    test "and the ratio does not care which way round the pair is" do
      a = "oklch(21% 0.006 285.885)"
      b = "oklch(98% 0 0)"

      assert_in_delta contrast(a, b), contrast(b, a), 0.001
    end
  end

  ## The stylesheet

  # Each `daisyui-theme` block, as a map of role to colour.
  defp themes do
    source = File.read!(@stylesheet)

    ~r/@plugin "[^"]*daisyui-theme"\s*\{(?<body>[^}]*)\}/
    |> Regex.scan(source, capture: :all_names)
    |> Map.new(fn [body] -> {theme_name(body), colors(body)} end)
  end

  defp theme_name(body) do
    [[name]] = Regex.scan(~r/name:\s*"([^"]+)"/, body, capture: :all_but_first)

    name
  end

  # `--sl-color-link` at the top of `tokens.css` is the light theme, and the
  # `[data-theme="dark"]` block below it overrides it. Read positionally, the
  # same way the cascade reads it.
  defp link_color(theme) do
    source = File.read!(@tokens)

    [light, dark] =
      ~r/--sl-color-link:\s*(oklch\([^)]*\))/
      |> Regex.scan(source, capture: :all_but_first)
      |> Enum.map(fn [value] -> value end)

    if theme == "dark", do: dark, else: light
  end

  defp colors(body) do
    ~r/--color-([a-z0-9-]+):\s*(oklch\([^)]*\))/
    |> Regex.scan(body, capture: :all_but_first)
    |> Map.new(fn [role, value] -> {role, value} end)
  end

  ## WCAG 2.1

  defp contrast(one, two) do
    [lighter, darker] = Enum.sort([luminance(one), luminance(two)], :desc)

    (lighter + 0.05) / (darker + 0.05)
  end

  defp luminance(color) do
    {r, g, b} = color |> parse_oklch() |> oklch_to_linear_rgb()

    0.2126 * r + 0.7152 * g + 0.0722 * b
  end

  defp parse_oklch("oklch(" <> rest) do
    [lightness, chroma, hue] =
      rest
      |> String.trim_trailing(")")
      |> String.split(~r/\s+/, trim: true)
      |> Enum.map(&to_number/1)

    {lightness, chroma, hue}
  end

  defp to_number(value) do
    case Float.parse(String.trim_trailing(value, "%")) do
      {number, _rest} -> number
    end
  end

  # OKLab to linear sRGB, from the published conversion. Percentages are
  # lightness on 0..100 and the hue is in degrees.
  defp oklch_to_linear_rgb({lightness, chroma, hue}) do
    l = lightness / 100
    radians = hue * :math.pi() / 180
    a = chroma * :math.cos(radians)
    b = chroma * :math.sin(radians)

    l_ = l + 0.3963377774 * a + 0.2158037573 * b
    m_ = l - 0.1055613458 * a - 0.0638541728 * b
    s_ = l - 0.0894841775 * a - 1.2914855480 * b

    {lc, mc, sc} = {l_ * l_ * l_, m_ * m_ * m_, s_ * s_ * s_}

    {
      clamp(4.0767416621 * lc - 3.3077115913 * mc + 0.2309699292 * sc),
      clamp(-1.2684380046 * lc + 2.6097574011 * mc - 0.3413193965 * sc),
      clamp(-0.0041960863 * lc - 0.7034186147 * mc + 1.7076147010 * sc)
    }
  end

  # A colour outside the sRGB gamut clips to it, which is what a screen does.
  defp clamp(value) when value < 0.0, do: 0.0
  defp clamp(value) when value > 1.0, do: 1.0
  defp clamp(value), do: value
end
