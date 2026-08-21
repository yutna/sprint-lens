defmodule SprintLens.Teams.BuiltinTemplatesTest do
  use SprintLens.DataCase

  alias SprintLens.Repo
  alias SprintLens.Teams.BuiltinTemplates
  alias SprintLens.Teams.Template

  describe "all/0" do
    @tag req: ["FR-201"]
    test "is the five templates FR-201 names" do
      names = Enum.map(BuiltinTemplates.all(), fn {name, _columns} -> name end)

      assert names == ["Start-Stop-Continue", "Mad-Sad-Glad", "4Ls", "KPT", "Sailboat"]
    end

    @tag req: ["FR-202"]
    test "every template stays inside the two-to-six column bounds" do
      {min, max} = Template.column_bounds()

      for {name, columns} <- BuiltinTemplates.all() do
        assert length(columns) in min..max, "#{name} has #{length(columns)} columns"
      end
    end
  end

  describe "fallback_columns/0" do
    @tag req: ["FR-917"]
    test "gives a session started without a template somewhere to write" do
      names = Enum.map(BuiltinTemplates.fallback_columns(), & &1["name"])

      assert names == ["Went well", "To improve", "Actions"]
    end
  end

  describe "strings/0" do
    @tag req: ["FR-906"]
    test "is every distinct string the product ships, and nothing else" do
      strings = BuiltinTemplates.strings()

      assert length(strings) == length(Enum.uniq(strings))
      assert "Start-Stop-Continue" in strings
      assert "What should we begin doing?" in strings
      assert "Went well" in strings
    end
  end

  # The migration deliberately carries its own copy of this data — a migration
  # must not depend on a module that may change shape long after it has run
  # everywhere. That freedom is only safe if something notices when the two
  # drift, because the module is what gets translated and the rows are what
  # get rendered. A column renamed in one and not the other would render in
  # English forever with no error anywhere.
  describe "the seeded rows" do
    @tag req: ["FR-201"]
    test "match this module exactly" do
      seeded =
        Template
        |> where([t], t.is_builtin == true)
        |> Repo.all()
        |> Map.new(fn template ->
          {template.name, Enum.map(template.columns, &{&1["name"], &1["hint"]})}
        end)

      assert seeded == Map.new(BuiltinTemplates.all())
    end
  end
end
