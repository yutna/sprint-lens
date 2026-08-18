defmodule SprintLens.Repo.Migrations.CreateRetroSessions do
  @moduledoc """
  Retrospective sessions and the board columns each one is seeded with
  (spec section 6.3: RETRO_SESSION, COLUMN).
  """

  use Ecto.Migration

  def change do
    create table(:retro_sessions) do
      add :team_id, references(:teams, on_delete: :delete_all), null: false
      # The template a session was seeded from. Kept for the record even if
      # the template is later deleted, hence nilify rather than cascade —
      # the columns have already been copied onto the session.
      add :template_id, references(:retro_templates, on_delete: :nilify_all)
      add :facilitator_id, references(:users, on_delete: :nilify_all)

      add :title, :string, null: false
      add :scheduled_at, :utc_datetime
      add :state, :string, null: false, default: "created"
      add :phase, :string, null: false, default: "checkin"

      # Modes, fixed at creation (FR-209, FR-210).
      add :is_anonymous, :boolean, null: false, default: false
      add :is_blind, :boolean, null: false, default: false
      add :cards_revealed, :boolean, null: false, default: false
      add :votes_revealed, :boolean, null: false, default: false

      add :vote_budget, :integer, null: false, default: 5
      add :multi_vote, :boolean, null: false, default: false

      # Short code participants type to join (FR-204).
      add :join_code, :string, null: false

      # A server-authoritative timer that does not tick over the wire
      # (FR-208): clients derive the remaining time from these three fields.
      add :timer_duration_s, :integer
      add :timer_started_at, :utc_datetime_usec
      add :timer_remaining_s, :integer

      add :closed_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:retro_sessions, [:join_code])
    create index(:retro_sessions, [:team_id])
    create index(:retro_sessions, [:team_id, :state])

    create table(:retro_columns) do
      add :session_id, references(:retro_sessions, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :hint, :string
      add :position, :integer, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:retro_columns, [:session_id])
    create unique_index(:retro_columns, [:session_id, :position])
  end
end
