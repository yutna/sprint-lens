defmodule SprintLensWeb.TemplateText do
  @moduledoc """
  Renders template and column wording in the viewer's language (FR-906),
  without ever translating a team's own words (FR-909).

  The distinction is the whole point. `SprintLens.Teams.BuiltinTemplates`
  holds the text the product ships; a team can also write its own template,
  and a column called "งานที่ค้าง" typed by a team must appear exactly as
  typed, in every language, forever. So translation is gated on a fact about
  the record — `is_builtin` on a template, `from_builtin` on a board column —
  and never on what the string happens to say. A team is perfectly entitled to
  call a column "Actions"; that is their word, not ours.

  The `templates` gettext domain keeps this wording out of `default`, so it
  can be reviewed as a set. The clauses below are generated from the canonical
  list, which is what makes `mix gettext.extract` see every string: a
  migration is never scanned, so the list cannot live only there.
  """

  use Gettext, backend: SprintLensWeb.Gettext

  alias SprintLens.Retro.Column
  alias SprintLens.Teams.BuiltinTemplates
  alias SprintLens.Teams.Template

  @doc """
  A template's name, translated when the template is one of the built-ins.
  """
  @spec template_name(Template.t()) :: String.t()
  def template_name(%Template{is_builtin: true, name: name}), do: translate(name)
  def template_name(%Template{name: name}), do: name

  @doc """
  A template's column names, in order, translated when it is a built-in.
  """
  @spec template_column_names(Template.t()) :: [String.t()]
  def template_column_names(%Template{is_builtin: builtin?} = template) do
    template
    |> Template.column_names()
    |> Enum.map(&maybe_translate(&1, builtin?))
  end

  @doc """
  A board column's heading, translated when the column came from the product
  rather than from the team.

  Matches on the shape rather than on `%Column{}`: the live board renders the
  projection `SprintLens.Retro.snapshot/2` builds, while the recap and the
  search results render the schema struct, and both need the same answer.
  """
  @spec column_name(Column.t() | map()) :: String.t()
  def column_name(%{name: name, from_builtin: builtin?}) do
    maybe_translate(name, builtin?)
  end

  @doc """
  A board column's hint, which may be absent.
  """
  @spec column_hint(Column.t() | map()) :: String.t() | nil
  def column_hint(%{hint: nil}), do: nil

  def column_hint(%{hint: hint, from_builtin: builtin?}) do
    maybe_translate(hint, builtin?)
  end

  defp maybe_translate(text, true), do: translate(text)
  defp maybe_translate(text, _not_builtin), do: text

  @doc """
  Translates one of the product's own strings, leaving anything else alone.

  Public so its test can walk `SprintLens.Teams.BuiltinTemplates.strings/0`
  and prove that every shipped string has a clause. A string that quietly lost
  one would fall through to the catch-all and render in English forever, which
  is exactly the defect this module exists to fix.
  """
  @spec translate(String.t() | nil) :: String.t() | nil
  for string <- BuiltinTemplates.strings() do
    def translate(unquote(string)), do: dgettext("templates", unquote(string))
  end

  def translate(text), do: text
end
