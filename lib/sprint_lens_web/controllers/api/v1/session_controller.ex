defmodule SprintLensWeb.Api.V1.SessionController do
  @moduledoc """
  Sessions, phases and the timer over the API (§7.2).

  Like every controller here, it decides nothing: `SprintLens.Retro`
  authorises, changes and broadcasts, so a client driving the API and a person
  driving the board go through the same gate and produce the same realtime
  events (NFR-201, §7.3).
  """

  use SprintLensWeb, :controller

  alias SprintLens.Retro
  alias SprintLens.Retro.Session
  alias SprintLens.Teams
  alias SprintLensWeb.Api.V1.SessionJSON
  alias SprintLensWeb.FallbackController

  action_fallback FallbackController

  def index(conn, %{"id" => team_id}) do
    with {:ok, team} <- Teams.fetch_team(scope(conn), team_id) do
      json(conn, %{data: Enum.map(Retro.list_sessions(team), &SessionJSON.summary/1)})
    end
  end

  def create(conn, %{"id" => team_id} = params) do
    with {:ok, team} <- Teams.fetch_team(scope(conn), team_id),
         {:ok, session} <- Retro.create_session(scope(conn), team, session_params(params)) do
      conn
      |> put_status(:created)
      |> json(%{data: SessionJSON.detail(session)})
    end
  end

  def show(conn, %{"id" => id}) do
    with {:ok, session} <- Retro.fetch_session(scope(conn), id) do
      json(conn, %{data: SessionJSON.detail(session)})
    end
  end

  @doc """
  `POST /api/v1/sessions/join` — resolve a join code to a session (FR-204).
  """
  def join(conn, params) do
    with {:ok, session} <- Retro.fetch_session_by_code(scope(conn), params["code"]) do
      json(conn, %{data: SessionJSON.detail(session)})
    end
  end

  @doc """
  `POST /api/v1/sessions/:id/phase` — advance, revert or jump (FR-206), and
  start or close the session (FR-205).
  """
  def phase(conn, %{"id" => id} = params) do
    with {:ok, session} <- Retro.fetch_session(scope(conn), id),
         {:ok, updated} <- apply_phase(scope(conn), session, params) do
      json(conn, %{data: SessionJSON.detail(updated)})
    end
  end

  @doc """
  `POST /api/v1/sessions/:id/timer` — start, pause or reset (FR-208).
  """
  def timer(conn, %{"id" => id} = params) do
    with {:ok, session} <- Retro.fetch_session(scope(conn), id),
         {:ok, updated} <- apply_timer(scope(conn), session, params) do
      json(conn, %{data: SessionJSON.detail(updated)})
    end
  end

  @doc """
  `POST /api/v1/sessions/:id/facilitator` — hand the role over (FR-207).
  """
  def facilitator(conn, %{"id" => id} = params) do
    with {:ok, session} <- Retro.fetch_session(scope(conn), id),
         {:ok, updated} <-
           Retro.transfer_facilitator(scope(conn), session, params["user_id"]) do
      json(conn, %{data: SessionJSON.detail(updated)})
    end
  end

  defp apply_phase(scope, session, %{"action" => action}) do
    case action do
      "start" -> Retro.start_session(scope, session)
      "close" -> Retro.close_session(scope, session)
      "advance" -> Retro.advance_phase(scope, session)
      "revert" -> Retro.revert_phase(scope, session)
      _unknown -> {:error, :validation_failed}
    end
  end

  defp apply_phase(scope, session, %{"phase" => phase}) do
    Retro.set_phase(scope, session, to_phase(phase))
  end

  defp apply_phase(_scope, _session, _params), do: {:error, :validation_failed}

  defp apply_timer(scope, session, %{"action" => action} = params) do
    case action do
      "start" -> Retro.start_timer(scope, session, params["duration_s"])
      "pause" -> Retro.pause_timer(scope, session)
      "reset" -> Retro.reset_timer(scope, session)
      _unknown -> {:error, :validation_failed}
    end
  end

  defp apply_timer(_scope, _session, _params), do: {:error, :validation_failed}

  defp to_phase(phase) when is_binary(phase) do
    Enum.find(Session.phases(), &(Atom.to_string(&1) == phase))
  end

  defp to_phase(_phase), do: nil

  defp session_params(%{"session" => %{} = params}), do: params
  defp session_params(params), do: Map.drop(params, ["id"])

  defp scope(conn), do: conn.assigns.current_scope
end
