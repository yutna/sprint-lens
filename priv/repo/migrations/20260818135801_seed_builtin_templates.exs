defmodule SprintLens.Repo.Migrations.SeedBuiltinTemplates do
  @moduledoc """
  The five built-in templates FR-201 names.

  These are normative data, not sample data: FR-201 says a member must be able
  to start a session from one of them, so an installation without them is an
  installation that does not meet the spec. That is why they are a migration
  and not `priv/repo/seeds.exs` — seeds do not run for a fresh deployment, nor
  for the throwaway database `mix e2e` builds.

  Column names and hints are written in English here and translated at render
  time, so a Thai-speaking team sees Thai column headings (FR-906). The
  translation is not done here and cannot be: a migration is never scanned by
  `mix gettext.extract`. `SprintLens.Teams.BuiltinTemplates` carries the same
  list where the extractor can see it, `SprintLensWeb.TemplateText` renders
  it, and a test compares these rows against that module so the two copies
  cannot drift apart in silence.
  """

  use Ecto.Migration

  import Ecto.Query, only: [from: 2]

  @templates [
    {"Start-Stop-Continue",
     [
       {"Start", "What should we begin doing?"},
       {"Stop", "What should we stop doing?"},
       {"Continue", "What is working and should carry on?"}
     ]},
    {"Mad-Sad-Glad",
     [
       {"Mad", "What frustrated you?"},
       {"Sad", "What disappointed you?"},
       {"Glad", "What made you happy?"}
     ]},
    {"4Ls",
     [
       {"Liked", "What did you enjoy?"},
       {"Learned", "What did you find out?"},
       {"Lacked", "What was missing?"},
       {"Longed for", "What did you wish you had?"}
     ]},
    {"KPT",
     [
       {"Keep", "What is worth keeping?"},
       {"Problem", "What got in the way?"},
       {"Try", "What should we try next?"}
     ]},
    {"Sailboat",
     [
       {"Wind", "What is pushing us forward?"},
       {"Anchor", "What is holding us back?"},
       {"Rocks", "What risks are ahead?"},
       {"Island", "What are we aiming for?"}
     ]}
  ]

  def up do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    entries =
      Enum.map(@templates, fn {name, columns} ->
        %{
          name: name,
          # 1, not `true`: `insert_all` against a bare table name has no
          # schema to tell it how to dump a boolean, and would store the
          # string "true" — which then fails to load as a boolean.
          is_builtin: 1,
          team_id: nil,
          columns: encode(columns),
          inserted_at: now,
          updated_at: now
        }
      end)

    repo().insert_all("retro_templates", entries)
  end

  def down do
    names = Enum.map(@templates, fn {name, _columns} -> name end)

    repo().delete_all(from(t in "retro_templates", where: t.is_builtin and t.name in ^names))
  end

  # The schema stores columns as a JSON array of {name, hint} maps; a
  # migration must not depend on the schema module, which may change shape
  # long after this migration has run everywhere.
  defp encode(columns) do
    columns
    |> Enum.map(fn {name, hint} -> %{"name" => name, "hint" => hint} end)
    |> Jason.encode!()
  end
end
