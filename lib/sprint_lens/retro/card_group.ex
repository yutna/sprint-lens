defmodule SprintLens.Retro.CardGroup do
  @moduledoc """
  A labelled cluster of similar cards (section 6.3, CARD_GROUP).

  Ungrouping a card clears its reference rather than deleting the group, and
  deleting a group leaves its cards on the board — merging is a way of
  reading the board, not a way of destroying what people wrote (FR-304).
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias SprintLens.Retro.Card
  alias SprintLens.Retro.Session

  @type t :: %__MODULE__{}

  schema "card_groups" do
    field :label, :string
    field :position, :integer

    belongs_to :session, Session
    has_many :cards, Card, preload_order: [asc: :position]

    timestamps(type: :utc_datetime)
  end

  @doc """
  A changeset for creating or relabelling a cluster.
  """
  def changeset(group, attrs) do
    group
    |> cast(attrs, [:session_id, :label, :position])
    |> validate_required([:session_id, :label, :position])
    |> update_change(:label, &String.trim/1)
    |> validate_length(:label, min: 1, max: 120)
    |> validate_number(:position, greater_than_or_equal_to: 0)
  end
end
