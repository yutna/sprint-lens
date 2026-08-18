defmodule SprintLens.Repo.Migrations.CreateCardsGroupsAndMoods do
  @moduledoc """
  The board itself: cards, the clusters they are merged into, and the mood
  entries collected at check-in and wrap-up (section 6.3: CARD, CARD_GROUP,
  MOOD_ENTRY).
  """

  use Ecto.Migration

  def change do
    create table(:card_groups) do
      add :session_id, references(:retro_sessions, on_delete: :delete_all), null: false
      add :label, :string, null: false
      add :position, :integer, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:card_groups, [:session_id])

    create table(:cards) do
      add :column_id, references(:retro_columns, on_delete: :delete_all), null: false
      # Nullable, and deliberately so. The reference exists while the session
      # runs, so people can edit their own cards and blind mode knows whose is
      # whose; when an anonymous session closes it is deleted outright, not
      # hidden (section 6.4, NFR-304).
      add :author_id, references(:users, on_delete: :nilify_all)
      add :card_group_id, references(:card_groups, on_delete: :nilify_all)

      add :text, :text, null: false
      add :position, :integer, null: false

      # The client's own id for the request that created this card. A flaky
      # mobile network retrying a POST must not produce two cards (§7.5).
      add :client_request_id, :string

      timestamps(type: :utc_datetime)
    end

    create index(:cards, [:column_id])
    create index(:cards, [:card_group_id])
    create index(:cards, [:author_id])

    # Scoped to the column rather than globally unique: two people on two
    # boards may well generate the same id, and the guarantee only needs to
    # hold where the duplicate would appear.
    create unique_index(:cards, [:column_id, :client_request_id],
             where: "client_request_id IS NOT NULL",
             name: :cards_idempotency
           )

    create table(:mood_entries) do
      add :session_id, references(:retro_sessions, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :nilify_all)

      add :kind, :string, null: false
      add :score, :integer, null: false
      add :word, :string

      timestamps(type: :utc_datetime)
    end

    create index(:mood_entries, [:session_id])

    # One answer per person per kind: a check-in mood and a ROTI score are
    # each asked once, and answering again replaces the answer (FR-211,
    # FR-214). Partial, because an anonymous session's entries lose their
    # user reference when it closes.
    create unique_index(:mood_entries, [:session_id, :user_id, :kind],
             where: "user_id IS NOT NULL",
             name: :mood_entries_one_per_person
           )
  end
end
