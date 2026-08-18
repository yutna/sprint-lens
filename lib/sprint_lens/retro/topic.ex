defmodule SprintLens.Retro.Topic do
  @moduledoc """
  A thing the room can vote on, focus on and take notes about.

  Three requirements talk about the same object under the same name: FR-405
  sorts "topics (cards or groups)" by votes, FR-406 focuses one, FR-407
  records a note per one. So it is one concept here too, rather than three
  pairs of `card_id`/`card_group_id` arguments repeated across the context.

  ## What counts as a topic

  A cluster is a topic; a card is a topic *unless it belongs to a cluster*.
  Merging cards is how the room says "these are one conversation" (FR-304), so
  listing both the cluster and its members would put the same conversation on
  the agenda twice.

  ## Why a cluster's total includes its cards

  Voting comes after grouping, but the facilitator can step back a phase
  (FR-206), so a card can pick up votes and be merged into a cluster
  afterwards. Counting only votes cast on the cluster itself would silently
  drop those. A cluster's total is therefore its own votes plus its members',
  and — importantly — retracting works over the same set, or the screen would
  offer a vote back that nothing can return.
  """

  alias SprintLens.Retro.Card
  alias SprintLens.Retro.CardGroup

  @type kind :: :card | :group
  @type ref :: {kind(), term()}

  @type t :: %__MODULE__{
          kind: kind(),
          id: term(),
          key: String.t(),
          title: String.t(),
          cards: [Card.t()],
          votes: non_neg_integer() | nil,
          my_votes: non_neg_integer(),
          note: String.t() | nil,
          created_at: DateTime.t(),
          focused?: boolean()
        }

  defstruct [
    :kind,
    :id,
    :key,
    :title,
    :votes,
    :note,
    :created_at,
    cards: [],
    my_votes: 0,
    focused?: false
  ]

  @doc """
  A topic built from a cluster (FR-405).
  """
  @spec from_group(CardGroup.t()) :: t()
  def from_group(%CardGroup{} = group) do
    %__MODULE__{
      kind: :group,
      id: group.id,
      key: key({:group, group.id}),
      title: group.label,
      cards: loaded(group.cards),
      created_at: group.inserted_at
    }
  end

  @doc """
  A topic built from a card that belongs to no cluster (FR-405).
  """
  @spec from_card(Card.t()) :: t()
  def from_card(%Card{} = card) do
    %__MODULE__{
      kind: :card,
      id: card.id,
      key: key({:card, card.id}),
      title: card.text,
      cards: [card],
      created_at: card.inserted_at
    }
  end

  @doc """
  The stable string a client uses to name a topic, such as `"group:7"`.

  Needed because a card id and a cluster id can both be `7`, and HTML
  attributes and JSON keys have no room for a tuple.
  """
  @spec key(ref() | t()) :: String.t()
  def key(%__MODULE__{kind: kind, id: id}), do: key({kind, id})
  def key({kind, id}) when kind in [:card, :group], do: "#{kind}:#{id}"

  @doc """
  The key in a form an HTML `id` can hold.

  `Topic.key/1` uses a colon, which is legal in an id but has to be escaped in
  every CSS selector that looks for it — a footgun for tests and for any hook
  that needs `getElementById`.
  """
  @spec dom_id(ref() | t()) :: String.t()
  def dom_id(topic), do: topic |> key() |> String.replace(":", "-")

  @doc """
  Reads a topic reference back from the string form.

  Returns `:error` for anything else, so a hand-typed parameter cannot be
  mistaken for a topic that happens to exist.
  """
  @spec parse(String.t() | ref() | nil) :: {:ok, ref()} | :error
  def parse({kind, id}) when kind in [:card, :group], do: {:ok, {kind, id}}

  def parse(value) when is_binary(value) do
    case String.split(value, ":", parts: 2) do
      ["card", id] -> integer(:card, id)
      ["group", id] -> integer(:group, id)
      _other -> :error
    end
  end

  def parse(_value), do: :error

  @doc """
  A topic reference from the `card_id` / `card_group_id` pair the API and the
  database both speak, or `:error` when neither or both are given.

  This is where "exactly one of card or card_group is set" (section 6.3) is
  actually decided; the schemas and the context both come through here.
  """
  @spec from_ids(term(), term()) :: {:ok, ref()} | :error
  def from_ids(nil, nil), do: :error
  def from_ids(card_id, nil) when not is_nil(card_id), do: {:ok, {:card, card_id}}
  def from_ids(nil, group_id) when not is_nil(group_id), do: {:ok, {:group, group_id}}
  def from_ids(_card_id, _group_id), do: :error

  @doc """
  The `card_id` / `card_group_id` pair for a reference, for querying and for
  writing rows.
  """
  @spec to_ids(ref() | t()) :: {term() | nil, term() | nil}
  def to_ids(%__MODULE__{kind: kind, id: id}), do: to_ids({kind, id})
  def to_ids({:card, id}), do: {id, nil}
  def to_ids({:group, id}), do: {nil, id}

  @doc """
  Orders topics the way the discuss phase presents them: most votes first,
  ties broken by which came into being first (FR-405).

  When totals are hidden the vote counts are `nil` and only the tiebreak
  applies — an order that came out of the totals would publish them just as
  plainly as a number would (FR-404).
  """
  @spec rank([t()]) :: [t()]
  def rank(topics) do
    Enum.sort_by(topics, &{-(&1.votes || 0), DateTime.to_unix(&1.created_at), &1.key})
  end

  defp integer(kind, id) do
    case Integer.parse(id) do
      {parsed, ""} -> {:ok, {kind, parsed}}
      _other -> :error
    end
  end

  defp loaded(%Ecto.Association.NotLoaded{}), do: []
  defp loaded(cards), do: cards
end
