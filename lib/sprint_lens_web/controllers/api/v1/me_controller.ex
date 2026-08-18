defmodule SprintLensWeb.Api.V1.MeController do
  @moduledoc """
  `GET /api/v1/me` and `PATCH /api/v1/me` — the current user's profile and
  preferences (section 7.2, FR-003).
  """

  use SprintLensWeb, :controller

  alias SprintLens.Accounts
  alias SprintLensWeb.Api.V1.UserJSON
  alias SprintLensWeb.FallbackController

  action_fallback FallbackController

  def show(conn, _params) do
    json(conn, %{data: UserJSON.profile(conn.assigns.current_scope.user)})
  end

  def update(conn, params) do
    user = conn.assigns.current_scope.user

    with {:ok, updated} <- Accounts.update_user_profile(user, profile_params(params)) do
      json(conn, %{data: UserJSON.profile(updated)})
    end
  end

  # Accepts the fields nested under "user" or at the top level, so a caller
  # does not have to know which shape the HTML form happens to use.
  defp profile_params(%{"user" => params}) when is_map(params), do: params
  defp profile_params(params), do: params
end
