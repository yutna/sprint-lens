defmodule SprintLens.Repo.Migrations.CreateVotesAndDiscussion do
  @moduledoc """
  Voting and the discussion that follows it (section 6.3 VOTE, plus the
  discussion notes of FR-407 and the focused topic of FR-406).

  ## Two nullable references instead of one polymorphic column

  A vote, a note and the focus all point at a *topic*, which is either a card
  or a cluster. Section 6.3 models that as two optional refs with exactly one
  set, and following it keeps the foreign keys real: deleting a card takes its
  votes with it and clears the focus, which a `target_type`/`target_id` pair
  could not do.

  The "exactly one" rule itself lives in the changesets. SQLite cannot add a
  CHECK constraint to a table after the fact, and every other invariant here —
  the vote budget, the multi-vote setting — is already enforced in
  `SprintLens.Retro.Board` inside a transaction, which SQLite's single writer
  makes as good as a constraint.
  """

  use Ecto.Migration

  def change do
    create table(:votes) do
      add :session_id, references(:retro_sessions, on_delete: :delete_all), null: false
      # Nullable for the same reason `cards.author_id` is: the reference exists
      # while the session runs so the budget can be enforced, and is deleted
      # outright when an anonymous session closes (section 6.4, NFR-304).
      add :voter_id, references(:users, on_delete: :nilify_all)

      add :card_id, references(:cards, on_delete: :delete_all)
      add :card_group_id, references(:card_groups, on_delete: :delete_all)

      add :client_request_id, :string

      timestamps(type: :utc_datetime)
    end

    # Counting one person's votes in a session is the hot query: it runs on
    # every cast, to enforce the budget (FR-401).
    create index(:votes, [:session_id, :voter_id])
    create index(:votes, [:card_id])
    create index(:votes, [:card_group_id])

    create unique_index(:votes, [:session_id, :client_request_id],
             where: "client_request_id IS NOT NULL",
             name: :votes_idempotency
           )

    create table(:discussion_notes) do
      add :session_id, references(:retro_sessions, on_delete: :delete_all), null: false
      add :card_id, references(:cards, on_delete: :delete_all)
      add :card_group_id, references(:card_groups, on_delete: :delete_all)

      add :body, :text, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:discussion_notes, [:session_id])

    # One note per topic (FR-407): writing again edits the note rather than
    # adding a second one.
    create unique_index(:discussion_notes, [:session_id, :card_id],
             where: "card_id IS NOT NULL",
             name: :discussion_notes_one_per_card
           )

    create unique_index(:discussion_notes, [:session_id, :card_group_id],
             where: "card_group_id IS NOT NULL",
             name: :discussion_notes_one_per_group
           )

    # The focused topic (FR-406). Nilify rather than cascade: deleting the card
    # everyone is looking at should empty the spotlight, not the session.
    alter table(:retro_sessions) do
      add :focus_card_id, references(:cards, on_delete: :nilify_all)
      add :focus_card_group_id, references(:card_groups, on_delete: :nilify_all)
    end
  end
end
