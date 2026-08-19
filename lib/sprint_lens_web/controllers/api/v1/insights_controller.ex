defmodule SprintLensWeb.Api.V1.InsightsController do
  @moduledoc """
  History, numbers and search over the API (§7.2).

  The recap endpoint is here rather than under `/export` because §7.2's export
  is about file formats (M8's job); this one answers with the same JSON shape
  every other endpoint uses.

  Everything here reads what the screens read, through the same
  `SprintLens.Insights` functions — so a search that would not show a live
  session's cards on screen does not show them here either (FR-209, FR-603).
  """

  use SprintLensWeb, :controller

  alias SprintLens.Insights
  alias SprintLens.Teams
  alias SprintLensWeb.Api.V1.InsightsJSON
  alias SprintLensWeb.FallbackController

  action_fallback FallbackController

  def show(conn, %{"id" => team_id}) do
    with {:ok, team} <- Teams.fetch_team(scope(conn), team_id),
         {:ok, metrics} <- Insights.team_metrics(scope(conn), team) do
      json(conn, %{data: InsightsJSON.metrics(metrics)})
    end
  end

  def org(conn, _params) do
    with {:ok, metrics} <- Insights.org_metrics(scope(conn)) do
      json(conn, %{data: metrics})
    end
  end

  def archive(conn, %{"id" => team_id}) do
    with {:ok, team} <- Teams.fetch_team(scope(conn), team_id) do
      json(conn, %{data: team |> Insights.archive() |> Enum.map(&InsightsJSON.archive_entry/1)})
    end
  end

  def recap(conn, %{"id" => session_id}) do
    with {:ok, session} <- Insights.fetch_closed_session(scope(conn), session_id) do
      json(conn, %{data: session |> Insights.recap(scope(conn)) |> InsightsJSON.recap()})
    end
  end

  def search(conn, %{"id" => team_id} = params) do
    with {:ok, team} <- Teams.fetch_team(scope(conn), team_id),
         {:ok, results} <- Insights.search(scope(conn), team, params["q"]) do
      json(conn, %{data: InsightsJSON.results(results)})
    end
  end

  defp scope(conn), do: conn.assigns.current_scope
end
