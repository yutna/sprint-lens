defmodule SprintLensWeb.Plugs.Locale do
  @moduledoc """
  Sets the request's locale from the signed-in user, then a choice stored in
  the session, then the browser's `accept-language`, then the org default
  (FR-906, FR-907).

  Runs after `:fetch_current_scope_for_user` so a signed-in user's saved
  preference wins. The chosen locale is also assigned, so layouts can set
  `<html lang>` without recomputing it.
  """

  @behaviour Plug

  alias SprintLensWeb.Locale

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    locale =
      conn
      |> current_user()
      |> Locale.resolve(accept_language(conn), session_locale(conn))
      |> Locale.put()

    Plug.Conn.assign(conn, :locale, locale)
  end

  defp current_user(conn) do
    case conn.assigns do
      %{current_scope: %{user: user}} -> user
      _no_scope -> nil
    end
  end

  # The API pipeline has no session, and neither does a plug tested in
  # isolation. Neither is a reason to fail the request.
  defp session_locale(%{private: %{plug_session: %{}}} = conn) do
    Plug.Conn.get_session(conn, :locale)
  end

  defp session_locale(_conn), do: nil

  defp accept_language(conn) do
    case Plug.Conn.get_req_header(conn, "accept-language") do
      [header | _rest] -> header
      [] -> nil
    end
  end
end
