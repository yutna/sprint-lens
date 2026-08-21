defmodule SprintLens.Repo.Migrations.AddFromBuiltinToRetroColumns do
  @moduledoc """
  Records, on the column itself, whether its heading is the product's wording
  or the team's.

  A column is copied onto the session when the session is created, and never
  read from its template again — a team editing a template must not rewrite
  the headings of a retrospective that already happened (FR-602). The same
  reasoning applies to this flag: whether the wording was ours is decided once,
  at creation, and travels with the row.

  Carrying it here rather than looking it up through the session's template is
  what lets every render site — board, recap, search — answer "may this be
  translated?" without a join, and keeps answering it correctly after a
  template is deleted. Translating a team's own words would break FR-909;
  leaving ours in English breaks FR-906.
  """

  use Ecto.Migration

  def up do
    alter table(:retro_columns) do
      add :from_builtin, :boolean, default: false, null: false
    end

    # Existing boards: their headings came from the product whenever the
    # session was started from a built-in template, or from no template at all
    # — in which case the fallback columns are ours too.
    execute """
    UPDATE retro_columns
       SET from_builtin = true
     WHERE session_id IN (
       SELECT s.id
         FROM retro_sessions s
         LEFT JOIN retro_templates t ON t.id = s.template_id
        WHERE s.template_id IS NULL OR t.is_builtin
     )
    """
  end

  def down do
    alter table(:retro_columns) do
      remove :from_builtin
    end
  end
end
