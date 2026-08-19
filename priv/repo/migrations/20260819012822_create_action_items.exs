defmodule SprintLens.Repo.Migrations.CreateActionItems do
  @moduledoc """
  Action items (section 6.3, ACTION_ITEM).

  ## Every reference here nullifies, and that is the point

  Section 6.4 says action items survive their session: "Deleting a session
  cascades to its columns, cards, groups, votes, mood entries... Action items
  survive with their session link cleared."

  That has to hold through the *card* reference too. A retention purge (FR-803)
  deletes a session and its cards; if `card_id` cascaded, the team would lose
  the follow-up it agreed to along with the note that prompted it. An action
  outlives the conversation that produced it — that is what makes it an action
  rather than a comment.
  """

  use Ecto.Migration

  def change do
    create table(:action_items) do
      add :team_id, references(:teams, on_delete: :delete_all), null: false
      add :session_id, references(:retro_sessions, on_delete: :nilify_all)
      add :card_id, references(:cards, on_delete: :nilify_all)
      add :card_group_id, references(:card_groups, on_delete: :nilify_all)
      add :assignee_id, references(:users, on_delete: :nilify_all)
      add :carried_from_id, references(:action_items, on_delete: :nilify_all)

      add :title, :string, null: false
      add :description, :text
      add :status, :string, null: false, default: "open"
      add :due_date, :utc_datetime

      add :client_request_id, :string

      timestamps(type: :utc_datetime)
    end

    create index(:action_items, [:team_id])
    create index(:action_items, [:session_id])
    create index(:action_items, [:assignee_id])
    create index(:action_items, [:status])

    # An item is carried over once. Carrying it a second time would leave two
    # live copies of the same commitment and no way to say which the team
    # means; a chain continues through the copy instead (FR-505).
    create unique_index(:action_items, [:carried_from_id],
             where: "carried_from_id IS NOT NULL",
             name: :action_items_carried_once
           )

    create unique_index(:action_items, [:team_id, :client_request_id],
             where: "client_request_id IS NOT NULL",
             name: :action_items_idempotency
           )
  end
end
