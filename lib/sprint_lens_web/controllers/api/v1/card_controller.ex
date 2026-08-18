defmodule SprintLensWeb.Api.V1.CardController do
  @moduledoc """
  Cards, clusters and mood entries over the API (§7.2).

  Blind mode applies here exactly as it does on screen: the caller is shown
  what *they* may see, not everything that exists (FR-209). An API that
  answered differently from the board would be a way around the promise the
  board makes, so the same `Board.visible_cards/2` decides both — including
  which card ids a cluster is allowed to name.
  """

  use SprintLensWeb, :controller

  alias SprintLens.Retro
  alias SprintLens.Retro.Board
  alias SprintLens.Retro.MoodEntry
  alias SprintLensWeb.Api.V1.CardJSON
  alias SprintLensWeb.FallbackController

  action_fallback FallbackController

  def index(conn, %{"id" => session_id}) do
    with {:ok, session} <- Retro.fetch_session(scope(conn), session_id) do
      cards = Board.visible_cards(session, scope(conn))
      visible = MapSet.new(cards, & &1.id)

      json(conn, %{
        data: %{
          cards: Enum.map(cards, &CardJSON.card(&1, session)),
          groups: session |> Board.list_groups() |> Enum.map(&CardJSON.group(&1, visible))
        }
      })
    end
  end

  def create(conn, %{"id" => session_id} = params) do
    with {:ok, session} <- Retro.fetch_session(scope(conn), session_id),
         {:ok, card} <- Board.create_card(scope(conn), session, card_params(params)) do
      conn
      |> put_status(:created)
      |> json(%{data: CardJSON.card(card, session)})
    end
  end

  def update(conn, %{"id" => card_id} = params) do
    with {:ok, session, card} <- Board.fetch_card(scope(conn), card_id),
         {:ok, updated} <- apply_update(scope(conn), session, card, card_params(params)) do
      json(conn, %{data: CardJSON.card(updated, session)})
    end
  end

  def delete(conn, %{"id" => card_id}) do
    with {:ok, session, card} <- Board.fetch_card(scope(conn), card_id),
         :ok <- Board.delete_card(scope(conn), session, card) do
      send_resp(conn, :no_content, "")
    end
  end

  def create_group(conn, %{"id" => session_id} = params) do
    with {:ok, session} <- Retro.fetch_session(scope(conn), session_id),
         {:ok, group} <-
           Board.create_group(scope(conn), session, params["label"], params["card_ids"] || []) do
      conn
      |> put_status(:created)
      |> json(%{data: reload_group(conn, session, group.id)})
    end
  end

  def reveal(conn, %{"id" => session_id}) do
    with {:ok, session} <- Retro.fetch_session(scope(conn), session_id),
         {:ok, revealed} <- Board.reveal_cards(scope(conn), session) do
      json(conn, %{data: %{cards_revealed: revealed.cards_revealed}})
    end
  end

  def mood(conn, %{"id" => session_id} = params) do
    with {:ok, session} <- Retro.fetch_session(scope(conn), session_id),
         {:ok, kind} <- fetch_kind(params["kind"]),
         {:ok, _entry} <-
           Board.record_mood(scope(conn), session, kind, params["score"], params["word"]) do
      json(conn, %{data: Board.mood_summary(session, kind)})
    end
  end

  # One endpoint, three intents: retext, move, or (un)group. Which one is meant
  # is decided by what the caller actually sent, so a client that only wants to
  # move a card never has to echo its text back.
  defp apply_update(scope, session, card, %{"column_id" => column_id} = params) do
    Board.move_card(scope, session, card, column_id, position(params["position"]))
  end

  defp apply_update(scope, session, card, %{"card_group_id" => group_id}) do
    Board.set_card_group(scope, session, card, group_id)
  end

  defp apply_update(scope, session, card, params) do
    Board.update_card(scope, session, card, params)
  end

  defp reload_group(conn, session, group_id) do
    visible = session |> Board.visible_cards(scope(conn)) |> MapSet.new(& &1.id)

    session
    |> Board.list_groups()
    |> Enum.find(&(&1.id == group_id))
    |> CardJSON.group(visible)
  end

  defp fetch_kind(kind) do
    case Enum.find(MoodEntry.kinds(), &(Atom.to_string(&1) == kind)) do
      nil -> {:error, :validation_failed}
      found -> {:ok, found}
    end
  end

  # JSON bodies and query strings disagree about whether a number is a number,
  # so anything unreadable lands at the top of the column rather than failing.
  defp position(value) when is_integer(value) and value >= 0, do: value

  defp position(value) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} when parsed >= 0 -> parsed
      _other -> 0
    end
  end

  defp position(_value), do: 0

  defp card_params(%{"card" => %{} = params}), do: params
  defp card_params(params), do: Map.drop(params, ["id"])

  defp scope(conn), do: conn.assigns.current_scope
end
