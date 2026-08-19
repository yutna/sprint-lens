defmodule SprintLens.Repo.Migrations.CreateAiSuggestions do
  @moduledoc """
  One AI job and its output (section 6.3, AI_SUGGESTION; AI-005, AI-018).

  ## Both references cascade

  Section 6.4 lists session-scoped AI suggestions among the things a purge
  takes with the session, and AI-018 says stored suggestions follow the same
  retention rules as their team's sessions. A suggestion is a derived opinion
  about content that has been deleted; keeping it would be keeping a summary
  of a retrospective the organisation decided not to keep.

  ## The accepted output is stored beside the suggested one

  AI-002 lets a human *edit* before accepting, so what the team agreed to is
  not always what the model said. Keeping both means the recap shows the
  human's version while the log still says what was suggested — which is the
  only way to tell later whether the model was useful.
  """

  use Ecto.Migration

  def change do
    create table(:ai_suggestions) do
      add :team_id, references(:teams, on_delete: :delete_all), null: false
      add :session_id, references(:retro_sessions, on_delete: :delete_all)
      add :requested_by_id, references(:users, on_delete: :nilify_all)

      add :type, :string, null: false
      add :status, :string, null: false, default: "queued"
      add :input_scope, :string, null: false

      add :output, :text
      add :accepted_output, :text
      add :error, :string

      # How long the model took and how much was sent, for operations —
      # never what was sent (AI-017).
      add :duration_ms, :integer
      add :input_bytes, :integer

      timestamps(type: :utc_datetime)
    end

    create index(:ai_suggestions, [:team_id])
    create index(:ai_suggestions, [:session_id])
    create index(:ai_suggestions, [:status])

    # The recap shows the summary a facilitator accepted (AI-009). Stored on
    # the session rather than read back through the suggestion, so a purge of
    # the suggestions cannot empty a recap somebody signed off.
    alter table(:retro_sessions) do
      add :summary, :text
    end
  end
end
