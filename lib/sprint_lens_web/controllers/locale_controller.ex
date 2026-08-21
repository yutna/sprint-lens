defmodule SprintLensWeb.LocaleController do
  @moduledoc """
  The single write path for a language choice (FR-907).

  The switcher in the navigation bar is an ordinary link that comes through
  here and goes straight back to where the visitor was. That is what makes it
  work on every page rather than only on a LiveView: a pushed event needs a
  live process on the other end of the socket, and the landing page, the
  development routes and the rendered error pages have none. The click used to
  fail silently on all of them.

  Where the choice is written depends on who is asking. A signed-in user has a
  profile and it follows them to their next device (FR-003). A visitor with no
  account has only the session cookie, which a LiveView cannot write anyway.
  """

  use SprintLensWeb, :controller

  alias SprintLens.Accounts
  alias SprintLensWeb.Locale
  alias SprintLensWeb.ReturnTo

  def update(conn, %{"language" => language} = params) do
    conn
    |> store(language)
    |> redirect(to: ReturnTo.path(params))
  end

  defp store(conn, language) do
    if Locale.supported?(language) do
      write(conn, current_user(conn), language)
    else
      conn
    end
  end

  defp write(conn, nil, language), do: put_session(conn, :locale, language)

  defp write(conn, user, language) do
    # Deliberately ignoring a failed write. A profile row that no longer
    # satisfies its own validations — the shape a bad data migration leaves
    # behind — must not turn "change the language" into an error page
    # (FR-919). The choice is dropped and the visitor lands back where they
    # were.
    _ = Accounts.update_user_profile(user, %{language: language})

    conn
  end

  defp current_user(conn) do
    case conn.assigns do
      %{current_scope: %{user: %{} = user}} -> user
      _no_user -> nil
    end
  end
end
