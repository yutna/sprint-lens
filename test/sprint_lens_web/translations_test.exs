defmodule SprintLensWeb.TranslationsTest do
  @moduledoc """
  The translation catalogues themselves (FR-906).

  ## Why this test exists

  `mix gettext.extract --merge` guesses. A new string that looks like an old
  one is copied across and marked `fuzzy`, and Gettext then serves the guess:
  a "Reveal totals" button that reads "Reveal cards", a vote count that reads
  "1 member". Nothing fails, nothing warns, and the screen is quietly wrong in
  both languages.

  It happened here — five entries at once — which is why the catalogues are
  now checked rather than trusted.
  """

  use SprintLens.UnitCase, async: true

  @locales ~w(th en)
  # `templates` carries the wording the product ships inside its five built-in
  # retrospective templates. It is a domain of its own so that text can be
  # reviewed as a set, apart from interface chrome.
  @domains ~w(default errors templates)

  defp catalogues do
    for locale <- @locales, domain <- @domains do
      path = "priv/gettext/#{locale}/LC_MESSAGES/#{domain}.po"

      {locale, domain, path, File.read!(path)}
    end
  end

  # Every `msgid`/`msgstr` pair, and every plural form, as flat text.
  defp entries(source) do
    ~r/^msgid "(?<id>.*)"\n(?:msgid_plural ".*"\n)?(?<body>(?:msgstr(?:\[\d\])? ".*"\n)+)/m
    |> Regex.scan(source, capture: :all_names)
    |> Enum.map(fn [body, id] ->
      forms = ~r/^msgstr(?:\[\d\])? "(.*)"$/m |> Regex.scan(body) |> Enum.map(&List.last/1)

      {id, forms}
    end)
    |> Enum.reject(fn {id, _forms} -> id == "" end)
  end

  @tag req: ["FR-906"]
  test "no translation is a guess left over from a merge" do
    fuzzy =
      for {locale, domain, _path, source} <- catalogues(),
          String.contains?(source, "fuzzy"),
          do: "#{locale}/#{domain}"

    assert fuzzy == [],
           """
           These catalogues contain fuzzy entries: #{Enum.join(fuzzy, ", ")}.

           A fuzzy entry is `mix gettext.extract --merge` guessing that a new
           string means the same as an old one. Read each one, write the real
           translation, and delete the `fuzzy` flag.
           """
  end

  @tag req: ["FR-906"]
  test "every string is available in both languages" do
    missing =
      for {locale, domain, _path, source} <- catalogues(),
          # The source language legitimately leaves Ecto's built-in messages
          # empty: the msgid is already the English text.
          not (locale == "en" and domain == "errors"),
          {id, forms} <- entries(source),
          Enum.any?(forms, &(&1 == "")),
          do: "#{locale}/#{domain}: #{id}"

    assert missing == [], "Untranslated:\n" <> Enum.join(missing, "\n")
  end

  @tag req: ["FR-906"]
  test "a translation keeps the placeholders its message needs" do
    # A dropped `%{count}` renders as a sentence with a hole in it, which no
    # compiler catches and no reviewer reading only English would notice.
    wrong =
      for {locale, domain, _path, source} <- catalogues(),
          {id, forms} <- entries(source),
          form <- forms,
          form != "",
          placeholders(form) != placeholders(id),
          do: "#{locale}/#{domain}: #{id} -> #{form}"

    assert wrong == [], "Placeholders do not match:\n" <> Enum.join(wrong, "\n")
  end

  defp placeholders(text) do
    ~r/%\{(\w+)\}/ |> Regex.scan(text) |> Enum.map(&List.last/1) |> Enum.sort()
  end
end
