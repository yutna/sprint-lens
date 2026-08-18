defmodule SprintLensWeb.Api.V1.VoteController do
  @moduledoc """
  Voting, the spotlight and the record of what was said (§7.2).

  §7.2 gives one endpoint for votes — "cast or retract a vote" — so the body
  says which, rather than the method. That also keeps the retraction out of a
  `DELETE` body, which some clients and proxies drop on the way.

  Totals are hidden here exactly as they are on screen: `Board.topics/2`
  decides, and it returns `null` until the facilitator reveals (FR-404). The
  caller's own count is always theirs to see (FR-403).
  """

  use SprintLensWeb, :controller

  alias SprintLens.Retro
  alias SprintLens.Retro.Board
  alias SprintLensWeb.Api.V1.TopicJSON
  alias SprintLensWeb.FallbackController

  action_fallback FallbackController

  def index(conn, %{"id" => session_id}) do
    with {:ok, session} <- Retro.fetch_session(scope(conn), session_id) do
      json(conn, %{
        data: %{
          topics: session |> Board.topics(scope(conn)) |> Enum.map(&TopicJSON.topic/1),
          votes: Board.vote_summary(session, scope(conn))
        }
      })
    end
  end

  def vote(conn, %{"id" => session_id} = params) do
    with {:ok, session} <- Retro.fetch_session(scope(conn), session_id),
         {:ok, topic} <- fetch_topic(params) do
      apply_vote(conn, session, topic, params)
    end
  end

  def reveal(conn, %{"id" => session_id}) do
    with {:ok, session} <- Retro.fetch_session(scope(conn), session_id),
         {:ok, revealed} <- Board.reveal_votes(scope(conn), session) do
      json(conn, %{data: %{votes_revealed: revealed.votes_revealed}})
    end
  end

  def focus(conn, %{"id" => session_id} = params) do
    with {:ok, session} <- Retro.fetch_session(scope(conn), session_id),
         {:ok, focused} <- set_focus(session, conn, params) do
      json(conn, %{data: TopicJSON.focus(focused)})
    end
  end

  def note(conn, %{"id" => session_id} = params) do
    with {:ok, session} <- Retro.fetch_session(scope(conn), session_id),
         {:ok, topic} <- fetch_topic(params),
         {:ok, note} <- Board.write_note(scope(conn), session, topic, params["body"]) do
      json(conn, %{data: TopicJSON.note(note, topic)})
    end
  end

  # `retract: true` rather than a second endpoint, per §7.2's one line for
  # both.
  defp apply_vote(conn, session, topic, %{"retract" => true}) do
    with :ok <- Board.retract_vote(scope(conn), session, topic) do
      json(conn, %{data: Board.vote_summary(session, scope(conn))})
    end
  end

  defp apply_vote(conn, session, topic, params) do
    opts = [client_request_id: params["client_request_id"]]

    with {:ok, _vote} <- Board.cast_vote(scope(conn), session, topic, opts) do
      conn
      |> put_status(:created)
      |> json(%{data: Board.vote_summary(session, scope(conn))})
    end
  end

  # Clearing the spotlight is sending no topic at all, which is the same thing
  # the LiveView's "stop discussing" does (FR-406).
  defp set_focus(session, conn, %{"topic" => topic} = params) when not is_nil(topic) do
    Board.set_focus(scope(conn), session, topic, params["timer_s"])
  end

  defp set_focus(session, conn, %{"card_id" => _id} = params) do
    with {:ok, topic} <- fetch_topic(params) do
      Board.set_focus(scope(conn), session, topic, params["timer_s"])
    end
  end

  defp set_focus(session, conn, %{"card_group_id" => _id} = params) do
    with {:ok, topic} <- fetch_topic(params) do
      Board.set_focus(scope(conn), session, topic, params["timer_s"])
    end
  end

  defp set_focus(session, conn, _params) do
    Board.set_focus(scope(conn), session, nil)
  end

  # A topic arrives either as a key or as the pair of ids the data model uses;
  # both are §7.2-shaped, and neither is a topic on its own.
  defp fetch_topic(%{"topic" => topic}) when is_binary(topic), do: {:ok, topic}

  defp fetch_topic(params) do
    case {params["card_id"], params["card_group_id"]} do
      {nil, nil} -> {:error, :not_found}
      {card_id, nil} -> {:ok, {:card, card_id}}
      {nil, group_id} -> {:ok, {:group, group_id}}
      {_card_id, _group_id} -> {:error, :validation_failed}
    end
  end

  defp scope(conn), do: conn.assigns.current_scope
end
