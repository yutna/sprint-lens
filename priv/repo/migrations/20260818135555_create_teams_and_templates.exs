defmodule SprintLens.Repo.Migrations.CreateTeamsAndTemplates do
  @moduledoc """
  Teams, their membership, and the column layouts a session is created from
  (spec section 6.3: TEAM, TEAM_MEMBERSHIP, RETRO_TEMPLATE).
  """

  use Ecto.Migration

  def change do
    create table(:teams) do
      add :name, :string, null: false
      add :description, :text
      add :is_archived, :boolean, null: false, default: false
      add :default_vote_budget, :integer, null: false, default: 5
      add :ai_opt_in, :boolean, null: false, default: false
      # Set after retro_templates exists; see the reference added below.
      add :default_template_id, :integer

      timestamps(type: :utc_datetime)
    end

    create table(:team_memberships) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :team_id, references(:teams, on_delete: :delete_all), null: false
      add :role, :string, null: false, default: "member"

      timestamps(type: :utc_datetime)
    end

    # "A user has at most one membership per team; changing the role updates
    # that membership" (section 6.4). Enforced by the database, not by
    # convention.
    create unique_index(:team_memberships, [:team_id, :user_id])
    create index(:team_memberships, [:user_id])

    create table(:retro_templates) do
      # Null for the built-ins, which belong to no team and are available to
      # everyone (section 6.3).
      add :team_id, references(:teams, on_delete: :delete_all)
      add :name, :string, null: false
      add :is_builtin, :boolean, null: false, default: false
      # A list of %{"name" => ..., "hint" => ...}, two to six entries
      # (FR-202). Stored as JSON because columns are only ever read and
      # written as a whole layout.
      add :columns, :text, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:retro_templates, [:team_id])

    create unique_index(:retro_templates, [:name],
             where: "is_builtin = 1",
             name: :builtin_template_name
           )
  end
end
