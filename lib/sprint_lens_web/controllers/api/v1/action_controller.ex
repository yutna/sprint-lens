defmodule SprintLensWeb.Api.V1.ActionController do
  @moduledoc """
  Action items over the API (§7.2).

  The one asymmetry worth noticing: creating goes through a session, because
  FR-501 puts creation inside a live discussion, while updating goes through
  the item alone, because FR-503 says a team member may do it "at any time,
  including after the session closes". The routes follow that shape rather
  than making both look the same.
  """

  use SprintLensWeb, :controller

  alias SprintLens.Actions
  alias SprintLens.Retro
  alias SprintLens.Teams
  alias SprintLensWeb.Api.V1.ActionJSON
  alias SprintLensWeb.FallbackController

  action_fallback FallbackController

  def index(conn, %{"id" => team_id} = params) do
    with {:ok, team} <- Teams.fetch_team(scope(conn), team_id) do
      json(conn, %{
        data: team |> Actions.list_actions(filters(params)) |> Enum.map(&ActionJSON.action/1),
        meta: Actions.stats(team)
      })
    end
  end

  def open(conn, %{"id" => team_id}) do
    with {:ok, team} <- Teams.fetch_team(scope(conn), team_id) do
      json(conn, %{data: team |> Actions.list_open_actions() |> Enum.map(&ActionJSON.action/1)})
    end
  end

  def create(conn, %{"id" => session_id} = params) do
    with {:ok, session} <- Retro.fetch_session(scope(conn), session_id),
         {:ok, item} <- Actions.create_action(scope(conn), session, action_params(params)) do
      conn
      |> put_status(:created)
      |> json(%{data: ActionJSON.action(item)})
    end
  end

  def update(conn, %{"id" => id} = params) do
    with {:ok, item} <- Actions.fetch_action(scope(conn), id),
         {:ok, updated} <- Actions.update_action(scope(conn), item, action_params(params)) do
      json(conn, %{data: ActionJSON.action(updated)})
    end
  end

  def carry_over(conn, %{"id" => session_id, "action_id" => action_id}) do
    with {:ok, session} <- Retro.fetch_session(scope(conn), session_id),
         {:ok, item} <- Actions.fetch_action(scope(conn), action_id),
         {:ok, carried} <- Actions.carry_over(scope(conn), session, item) do
      conn
      |> put_status(:created)
      |> json(%{data: ActionJSON.action(carried)})
    end
  end

  # FR-504's three filters, and nothing else: an unknown parameter must not
  # silently narrow a list somebody is reading as complete.
  defp filters(params) do
    for key <- ~w(status assignee_id session_id),
        value = params[key],
        value not in [nil, ""],
        do: {String.to_existing_atom(key), value}
  end

  defp action_params(%{"action" => %{} = params}), do: params
  defp action_params(params), do: Map.drop(params, ["id", "action_id"])

  defp scope(conn), do: conn.assigns.current_scope
end
