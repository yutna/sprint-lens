defmodule SprintLensWeb.Api.V1.SessionJSON do
  @moduledoc """
  Serialises sessions for the API (§7.2).

  Two shapes: a `summary/1` for lists, and a `detail/1` that carries the same
  board snapshot the realtime clients get on connect (FR-309), so an API
  client and a browser start from the same picture.
  """

  alias SprintLens.Retro
  alias SprintLens.Retro.Session
  alias SprintLensWeb.Api.V1.UserJSON

  @doc """
  A session as it appears in a list (FR-203).
  """
  @spec summary(Session.t()) :: map()
  def summary(%Session{} = session) do
    %{
      id: session.id,
      team_id: session.team_id,
      title: session.title,
      state: Session.state(session),
      phase: Session.phase(session),
      is_anonymous: session.is_anonymous,
      is_blind: session.is_blind,
      scheduled_at: session.scheduled_at,
      closed_at: session.closed_at,
      created_at: session.inserted_at
    }
  end

  @doc """
  A session with everything needed to render its board.
  """
  @spec detail(Session.t()) :: map()
  def detail(%Session{} = session) do
    snapshot = Retro.snapshot(session)

    session
    |> summary()
    |> Map.merge(%{
      join_code: session.join_code,
      vote_budget: session.vote_budget,
      multi_vote: session.multi_vote,
      cards_revealed: session.cards_revealed,
      votes_revealed: session.votes_revealed,
      facilitator: UserJSON.summary(session.facilitator),
      timer: snapshot.timer,
      columns: snapshot.columns
    })
  end
end
