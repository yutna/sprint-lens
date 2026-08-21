defmodule SprintLensWeb.ThemeController do
  @moduledoc """
  The single write path for a theme choice (FR-910, FR-911).

  The mirror image of `SprintLensWeb.LocaleController`, and it exists for the
  same reason. The theme control used to combine a client-side repaint with a
  pushed event: the repaint half worked everywhere, the persisting half only
  worked where a live process happened to exist. A visitor who chose a theme
  before signing in got the colours they asked for and lost them on the next
  request, which is a worse failure than not offering the control at all.

  Storing the choice on the server rather than in `localStorage` is what makes
  FR-911 hold without JavaScript: the theme is stamped on `<html>` by the
  layout before anything is painted, so there is nothing to flash.
  """

  use SprintLensWeb, :controller

  alias SprintLens.Accounts
  alias SprintLensWeb.ReturnTo
  alias SprintLensWeb.Theme

  def update(conn, %{"theme" => theme} = params) do
    conn
    |> store(theme)
    |> redirect(to: ReturnTo.path(params))
  end

  defp store(conn, theme) do
    if Theme.supported?(theme) do
      write(conn, current_user(conn), theme)
    else
      conn
    end
  end

  defp write(conn, nil, theme), do: put_session(conn, :theme, theme)

  defp write(conn, user, theme) do
    # Same reasoning as the language controller: a profile that cannot be
    # written is not a reason to fail the request (FR-919).
    _ = Accounts.update_user_profile(user, %{theme: theme})

    conn
  end

  defp current_user(conn) do
    case conn.assigns do
      %{current_scope: %{user: %{} = user}} -> user
      _no_user -> nil
    end
  end
end
