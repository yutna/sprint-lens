defmodule SprintLensWeb.Api.V1.CardJSON do
  @moduledoc """
  Serialises cards and clusters for the API (§7.2).

  Authorship is omitted entirely for an anonymous session — not sent as null,
  not sent as a placeholder. FR-210 hides it from everyone including the
  facilitator and the Org Admin, and a field that is present for some cards
  and absent for others is itself a signal.
  """

  alias SprintLens.Retro.Card
  alias SprintLens.Retro.CardGroup
  alias SprintLens.Retro.Session
  alias SprintLensWeb.Api.V1.UserJSON

  @doc """
  One card, as the caller is allowed to see it.
  """
  @spec card(Card.t(), Session.t()) :: map()
  def card(%Card{} = card, %Session{} = session) do
    base = %{
      id: card.id,
      column_id: card.column_id,
      card_group_id: card.card_group_id,
      text: card.text,
      position: card.position,
      created_at: card.inserted_at
    }

    if session.is_anonymous do
      base
    else
      # Every card the context hands out has its author preloaded, so this is
      # a `%User{}` — or `nil` only in the anonymous case the branch above
      # already took.
      Map.put(base, :author, UserJSON.summary(card.author))
    end
  end

  @doc """
  One cluster, naming only the cards `visible` says the caller may see.

  A cluster is a way of reading the board, so it must not become a way of
  learning that a card exists while blind mode still hides it (FR-209).
  """
  @spec group(CardGroup.t(), MapSet.t()) :: map()
  def group(%CardGroup{} = group, visible) do
    %{
      id: group.id,
      label: group.label,
      position: group.position,
      card_ids: group.cards |> Enum.map(& &1.id) |> Enum.filter(&(&1 in visible))
    }
  end
end
