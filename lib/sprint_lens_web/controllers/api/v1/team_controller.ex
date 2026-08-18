defmodule SprintLensWeb.Api.V1.TeamController do
  @moduledoc """
  Teams, membership and templates over the API (§7.2).

  Nothing here decides anything: every action loads the team through
  `SprintLens.Teams`, which authorises through `SprintLens.Policy`. The
  controller's whole job is to turn HTTP into a context call and the result
  into JSON, so this surface and the LiveView cannot drift apart (NFR-201).
  """

  use SprintLensWeb, :controller

  alias SprintLens.Teams
  alias SprintLensWeb.Api.V1.TeamJSON
  alias SprintLensWeb.FallbackController

  action_fallback FallbackController

  ## Teams

  def index(conn, _params) do
    json(conn, %{data: Enum.map(Teams.list_teams(scope(conn)), &TeamJSON.team/1)})
  end

  def create(conn, params) do
    with {:ok, team} <- Teams.create_team(scope(conn), team_params(params)) do
      conn
      |> put_status(:created)
      |> json(%{data: TeamJSON.team_detail(team, Teams.list_members(team))})
    end
  end

  def show(conn, %{"id" => id}) do
    with {:ok, team} <- Teams.fetch_team(scope(conn), id) do
      json(conn, %{data: TeamJSON.team_detail(team, Teams.list_members(team))})
    end
  end

  def update(conn, %{"id" => id} = params) do
    with {:ok, team} <- Teams.fetch_team_for_management(scope(conn), id),
         {:ok, updated} <- Teams.update_team_settings(scope(conn), team, team_params(params)) do
      json(conn, %{data: TeamJSON.team_detail(updated, Teams.list_members(updated))})
    end
  end

  def archive(conn, %{"id" => id}) do
    with {:ok, team} <- Teams.fetch_team_for_management(scope(conn), id),
         {:ok, archived} <- Teams.archive_team(scope(conn), team) do
      json(conn, %{data: TeamJSON.team(archived)})
    end
  end

  def restore(conn, %{"id" => id}) do
    with {:ok, team} <- Teams.fetch_team_for_management(scope(conn), id),
         {:ok, restored} <- Teams.restore_team(scope(conn), team) do
      json(conn, %{data: TeamJSON.team(restored)})
    end
  end

  ## Membership

  def add_member(conn, %{"id" => id} = params) do
    role = Map.get(params, "role", "member")

    with {:ok, team} <- Teams.fetch_team_for_management(scope(conn), id),
         {:ok, _membership} <- add(scope(conn), team, params, role) do
      conn
      |> put_status(:created)
      |> json(%{data: Enum.map(Teams.list_members(team), &TeamJSON.membership/1)})
    end
  end

  def remove_member(conn, %{"id" => id, "user_id" => user_id}) do
    with {:ok, team} <- Teams.fetch_team_for_management(scope(conn), id),
         :ok <- Teams.remove_member(scope(conn), team, user_id) do
      send_resp(conn, :no_content, "")
    end
  end

  def leave(conn, %{"id" => id}) do
    with {:ok, team} <- Teams.fetch_team(scope(conn), id),
         :ok <- Teams.leave_team(scope(conn), team) do
      send_resp(conn, :no_content, "")
    end
  end

  ## Templates

  def templates(conn, %{"id" => id}) do
    with {:ok, team} <- Teams.fetch_team(scope(conn), id) do
      json(conn, %{data: Enum.map(Teams.list_templates(team), &TeamJSON.template/1)})
    end
  end

  def create_template(conn, %{"id" => id} = params) do
    with {:ok, team} <- Teams.fetch_team(scope(conn), id),
         {:ok, template} <- Teams.create_template(scope(conn), team, template_params(params)) do
      conn
      |> put_status(:created)
      |> json(%{data: TeamJSON.template(template)})
    end
  end

  def delete_template(conn, %{"id" => id, "template_id" => template_id}) do
    with {:ok, team} <- Teams.fetch_team(scope(conn), id),
         {:ok, template} <- Teams.fetch_template(team, template_id),
         :ok <- Teams.delete_template(scope(conn), team, template) do
      send_resp(conn, :no_content, "")
    end
  end

  ## Params

  defp add(scope, team, %{"email" => email}, role) when is_binary(email) do
    Teams.add_member_by_email(scope, team, email, role)
  end

  defp add(scope, team, %{"user_id" => user_id}, role) do
    Teams.add_member(scope, team, user_id, role)
  end

  defp add(_scope, _team, _params, _role), do: {:error, :validation_failed}

  defp team_params(params), do: nested(params, "team")
  defp template_params(params), do: nested(params, "template")

  # Accepts fields nested under a wrapper key or at the top level, so a caller
  # need not know which shape the HTML form happens to use.
  defp nested(%{} = params, key) do
    case Map.get(params, key) do
      %{} = inner -> inner
      _absent -> Map.drop(params, ["id", "user_id", "template_id"])
    end
  end

  defp scope(conn), do: conn.assigns.current_scope
end
