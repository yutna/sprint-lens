defmodule SprintLens.Retro.Vote do
  @moduledoc """
  One vote on a card or a cluster (section 6.3, VOTE).

  A vote is a row rather than a counter, because FR-402 lets a session allow
  more than one vote from the same person on the same topic. Counting rows is
  then the whole implementation of both the total and the budget, and
  retracting is deleting one row rather than decrementing something that could
  drift.

  The voter reference is nullable and is deleted outright when an anonymous
  session closes (section 6.4, NFR-304) — the same treatment as card
  authorship, for the same reason.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias SprintLens.Accounts.User
  alias SprintLens.Retro.Card
  alias SprintLens.Retro.CardGroup
  alias SprintLens.Retro.Session
  alias SprintLens.Retro.Topic

  @type t :: %__MODULE__{}

  schema "votes" do
    belongs_to :session, Session
    belongs_to :voter, User
    belongs_to :card, Card
    belongs_to :card_group, CardGroup

    field :client_request_id, :string

    timestamps(type: :utc_datetime)
  end

  @doc """
  A changeset for casting a vote.

  Exactly one of `card_id` and `card_group_id` must be set (section 6.3).
  Neither means a vote for nothing; both means a vote that would be counted
  twice, once under each total.
  """
  def changeset(vote, attrs) do
    vote
    |> cast(attrs, [:session_id, :voter_id, :card_id, :card_group_id, :client_request_id])
    |> validate_required([:session_id, :voter_id])
    |> validate_one_target()
    |> foreign_key_constraint(:session_id)
    |> foreign_key_constraint(:card_id)
    |> foreign_key_constraint(:card_group_id)
    |> unique_constraint([:session_id, :client_request_id])
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
