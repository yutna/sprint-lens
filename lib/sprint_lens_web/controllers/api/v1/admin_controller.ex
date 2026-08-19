defmodule SprintLensWeb.Api.V1.AdminController do
  @moduledoc """
  The administration endpoints of §7.2.

  §7.2 lists four: the user list, one `PATCH` on a user for "deactivate or
  erase", the audit log and the settings. Purging on demand (FR-804) is not
  in that list; it is added here under the section's own "implementations may
  add endpoints as long as the behavior stays within this spec", because an
  administrator who can purge from a screen and not from a script has half a
  feature.

  Every action refuses with 403 rather than 404. An Org Admin is not a secret
  the way another team's board is (FR-103) — the answer to "may I?" here is
  no, not "there is nothing here".
  """

  use SprintLensWeb, :controller

  alias SprintLens.Admin
  alias SprintLens.Repo
  alias SprintLens.Retro.Session
  alias SprintLens.Teams.Team
  alias SprintLensWeb.Api.V1.AdminJSON
  alias SprintLensWeb.FallbackController

  action_fallback FallbackController

  def users(conn, _params) do
    with {:ok, users} <- Admin.list_users(scope(conn)) do
      json(conn, %{data: Enum.map(users, &AdminJSON.user/1)})
    end
  end

  def update_user(conn, %{"id" => id} = params) do
    with {:ok, user} <- fetch(SprintLens.Accounts.User, id),
         {:ok, updated} <- apply_user_action(conn, user, params["action"]) do
      json(conn, %{data: AdminJSON.user(updated)})
    end
  end

  def audit(conn, params) do
    with {:ok, events} <- Admin.list_audit_events(scope(conn), limit(params)) do
      json(conn, %{data: Enum.map(events, &AdminJSON.event/1)})
    end
  end

  def settings(conn, _params) do
    with :ok <- authorize(conn) do
      json(conn, %{data: AdminJSON.settings(Admin.settings())})
    end
  end

  def update_settings(conn, params) do
    with {:ok, settings} <- Admin.update_settings(scope(conn), settings_params(params)) do
      json(conn, %{data: AdminJSON.settings(settings)})
    end
  end

  def purge_session(conn, %{"id" => id}) do
    with {:ok, session} <- fetch(Session, id),
         {:ok, _purged} <- Admin.purge_session(scope(conn), session) do
      send_resp(conn, :no_content, "")
    end
  end

  def purge_team(conn, %{"id" => id}) do
    with {:ok, team} <- fetch(Team, id),
         {:ok, _purged} <- Admin.purge_team(scope(conn), team) do
      send_resp(conn, :no_content, "")
    end
  end

  # §7.2's `PATCH /admin/users/{id}` is one endpoint for "deactivate or
  # erase", so the body says which. Naming the action rather than inferring
  # it from a field keeps an erasure from ever being an accident.
  defp apply_user_action(conn, user, "deactivate"), do: Admin.deactivate_user(scope(conn), user)
  defp apply_user_action(conn, user, "reactivate"), do: Admin.reactivate_user(scope(conn), user)
  defp apply_user_action(conn, user, "erase"), do: Admin.erase_user(scope(conn), user)

  defp apply_user_action(_conn, _user, _other) do
    {:error, :validation_failed, %{action: ["deactivate", "reactivate", "erase"]}}
  end

  defp authorize(conn) do
    with {:ok, _events} <- Admin.list_audit_events(scope(conn), 1), do: :ok
  end

  defp settings_params(%{"settings" => %{} = params}), do: params
  defp settings_params(params), do: Map.drop(params, ["id"])

  defp limit(params) do
    case Integer.parse(params["limit"] || "") do
      {value, ""} when value > 0 and value <= 500 -> value
      _other -> 100
    end
  end

  defp fetch(schema, id) do
    case Repo.fetch(schema, id) do
      nil -> {:error, :not_found}
      record -> {:ok, record}
    end
  end

  defp scope(conn), do: conn.assigns.current_scope
end
