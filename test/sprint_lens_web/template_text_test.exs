defmodule SprintLensWeb.TemplateTextTest do
  use SprintLens.UnitCase, async: false

  alias SprintLens.Retro.Column
  alias SprintLens.Teams.BuiltinTemplates
  alias SprintLens.Teams.Template
  alias SprintLensWeb.Locale
  alias SprintLensWeb.TemplateText

  # Acronyms the product ships and deliberately does not translate: "4Ls" and
  # "KPT" are the names these formats are known by, in Thai as in English.
  @untranslated ~w(4Ls KPT)

  setup do
    on_exit(fn -> Locale.put(Locale.default()) end)
    :ok
  end

  describe "translate/1" do
    # The defect this module exists to prevent. A shipped string with no
    # clause falls through to the catch-all and renders in English forever,
    # with nothing failing and nothing warning — which is precisely how the
    # forty-odd strings in the seed migration came to be English on a Thai
    # board despite a comment claiming they were translated at render time.
    @tag req: ["FR-906"]
    test "every string the product ships is actually translated" do
      Locale.put("th")

      still_english =
        for string <- BuiltinTemplates.strings(),
            string not in @untranslated,
            TemplateText.translate(string) == string,
            do: string

      assert still_english == [],
             "no Thai translation reached these:\n" <> Enum.join(still_english, "\n")
    end

    @tag req: ["FR-906"]
    test "the English catalogue gives back the English" do
      Locale.put("en")

      assert TemplateText.translate("Start") == "Start"

      assert TemplateText.translate("What should we begin doing?") ==
               "What should we begin doing?"
    end

    @tag req: ["FR-909"]
    test "anything the product does not ship is returned untouched" do
      Locale.put("th")

      assert TemplateText.translate("Blocked on review") == "Blocked on review"
      assert TemplateText.translate(nil) == nil
    end
  end

  describe "template_name/1" do
    @tag req: ["FR-906"]
    test "a built-in is translated" do
      Locale.put("th")

      name = TemplateText.template_name(%Template{is_builtin: true, name: "Sailboat"})

      refute name == "Sailboat"
    end

    # A team is entitled to call their template "Sailboat". The gate is the
    # record, never the string.
    @tag req: ["FR-909"]
    test "a team's own template keeps the name the team typed" do
      Locale.put("th")

      assert TemplateText.template_name(%Template{is_builtin: false, name: "Sailboat"}) ==
               "Sailboat"
    end
  end

  describe "template_column_names/1" do
    @tag req: ["FR-906"]
    test "a built-in's columns are translated" do
      Locale.put("th")

      template = %Template{
        is_builtin: true,
        columns: [%{"name" => "Wind"}, %{"name" => "Anchor"}]
      }

      assert [wind, anchor] = TemplateText.template_column_names(template)
      refute wind == "Wind"
      refute anchor == "Anchor"
    end

    @tag req: ["FR-909"]
    test "a team's own columns are not" do
      Locale.put("th")

      template = %Template{is_builtin: false, columns: [%{"name" => "Wind"}]}

      assert TemplateText.template_column_names(template) == ["Wind"]
    end
  end

  describe "column_name/1 and column_hint/1" do
    @tag req: ["FR-906"]
    test "a board column copied from a built-in is translated" do
      Locale.put("th")

      column = %Column{name: "Keep", hint: "What is worth keeping?", from_builtin: true}

      refute TemplateText.column_name(column) == "Keep"
      refute TemplateText.column_hint(column) == "What is worth keeping?"
    end

    @tag req: ["FR-909"]
    test "a board column the team wrote is left exactly as typed" do
      Locale.put("th")

      column = %Column{name: "Keep", hint: "What is worth keeping?", from_builtin: false}

      assert TemplateText.column_name(column) == "Keep"
      assert TemplateText.column_hint(column) == "What is worth keeping?"
    end

    @tag req: ["FR-906"]
    test "a column with no hint has nothing to translate" do
      assert TemplateText.column_hint(%Column{hint: nil, from_builtin: true}) == nil
    end

    # The live board renders the snapshot projection rather than the schema
    # struct, so both shapes have to work.
    @tag req: ["FR-906"]
    test "the snapshot projection is accepted as well as the struct" do
      Locale.put("th")

      projected = %{id: 1, name: "Rocks", hint: nil, position: 0, from_builtin: true}

      refute TemplateText.column_name(projected) == "Rocks"
    end
  end
end
