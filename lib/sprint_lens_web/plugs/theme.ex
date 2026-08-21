defmodule SprintLensWeb.Plugs.Theme do
  @moduledoc """
  Assigns the request's theme from the signed-in user, then a choice stored in
  the session, then `system` (FR-910, FR-911).

  The mirror of `SprintLensWeb.Plugs.Locale`, and it runs for the same reason:
  the layout stamps `data-theme` on `<html>` before the page is painted, and
  it can only do that if something has resolved the theme on the way in.
  Without this the server had no idea what a signed-out visitor had chosen,
  and every page load reset them to the operating system's preference.
  """

  @behaviour Plug

  alias SprintLensWeb.Theme

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    theme =
      conn
      |> current_user()
      |> Theme.resolve(session_theme(conn))

    Plug.Conn.assign(conn, :theme, theme)
  end

  defp current_user(conn) do
    case conn.assigns do
      %{current_scope: %{user: %{} = user}} -> user
      _no_user -> nil
    end
  end

  # A plug exercised in isolation has no session, and that is not a reason to
  # fail the request.
  defp session_theme(%{private: %{plug_session: %{}}} = conn) do
    Plug.Conn.get_session(conn, :theme)
  end

  defp session_theme(_conn), do: nil
end
