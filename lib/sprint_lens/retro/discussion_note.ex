defmodule SprintLens.Retro.DiscussionNote do
  @moduledoc """
  What the room decided about one topic (FR-407).

  Section 6.3 lists no entity for this, which reads as an omission rather than
  a decision: FR-407 requires a note per topic, FR-602 requires notes in the
  recap and FR-603 requires them to be searchable alongside cards and action
  items. Hanging the text off `CARD` and `CARD_GROUP` as two more columns
  would make "search the notes" mean reading two tables and "the recap's
  notes" mean two joins, so it is its own table, shaped like `VOTE` — one
  session, exactly one topic.

  No author reference. The note is the facilitator's record of a shared
  conversation, section 6.3 models no author for it, and one less personal
  reference is one less thing to strip when an anonymous session closes.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias SprintLens.Retro.Card
  alias SprintLens.Retro.CardGroup
  alias SprintLens.Retro.Session
  alias SprintLens.Retro.Topic

  @type t :: %__MODULE__{}

  @max_body 4_000

  schema "discussion_notes" do
    belongs_to :session, Session
    belongs_to :card, Card
    belongs_to :card_group, CardGroup

    field :body, :string

    timestamps(type: :utc_datetime)
  end

  @doc """
  The longest a note may be.

  No requirement names a limit; this one exists so a runaway paste cannot fill
  the database, and is generous enough that nobody writing in good faith will
  meet it.
  """
  @spec max_body() :: pos_integer()
  def max_body, do: @max_body

  @doc """
  A changeset for recording or editing a note.
  """
  def changeset(note, attrs) do
    note
    |> cast(attrs, [:session_id, :card_id, :card_group_id, :body])
    |> validate_required([:session_id, :body])
    |> update_change(:body, &String.trim/1)
    |> validate_length(:body, min: 1, max: @max_body)
    |> validate_one_target()
    |> foreign_key_constraint(:session_id)
    |> foreign_key_constraint(:card_id)
    |> foreign_key_constraint(:card_group_id)
  end

  defp validate_one_target(changeset) do
    card_id = get_field(changeset, :card_id)
    group_id = get_field(changeset, :card_group_id)

    case Topic.from_ids(card_id, group_id) do
      {:ok, _ref} -> changeset
      :error -> add_error(changeset, :card_id, "must name exactly one card or group")
    end
  end
end
