defmodule SprintLensWeb.Hooks.Preferences do
  @moduledoc """
  Carries language and theme into every LiveView (FR-907, FR-910).

  Mounted on every `live_session`, this hook does two things:

    * puts the viewer's locale on the LiveView process, so strings rendered by
      that process are translated even though the plug pipeline ran in a
      different process;
    * remembers the current path, so the preference switchers can send the
      visitor back to the page they were on.

  ## Why it no longer handles events

  It used to. The switchers pushed `set_language` and `set_theme`, and this
  hook wrote them to the profile. That worked on a LiveView and silently did
  nothing anywhere else, because a pushed event needs a live process and the
  landing page, the development routes and the rendered error pages have none.

  Both switchers are now ordinary links handled by
  `SprintLensWeb.LocaleController` and `SprintLensWeb.ThemeController`, which
  are reachable from every page and work without JavaScript. There is one
  write path for each preference instead of two that disagreed about which
  pages they covered.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [attach_hook: 4]

  alias SprintLensWeb.Locale
  alias SprintLensWeb.Theme

  def on_mount(:default, _params, session, socket) do
    user = current_user(socket)

    # The plug pipeline ran in another process, so its decisions do not carry
    # over. Both are re-resolved here from the same inputs the plugs used: the
    # profile, then the choice a signed-out visitor made in this session.
    locale = user |> Locale.resolve(nil, session["locale"]) |> Locale.put()

    socket =
      socket
      |> assign(:locale, locale)
      |> assign(:theme, Theme.resolve(user, session["theme"]))
      |> assign(:current_path, "/")
      |> attach_hook(:preferences_path, :handle_params, &track_path/3)

    {:cont, socket}
  end

  defp track_path(_params, uri, socket) do
    {:cont, assign(socket, :current_path, URI.parse(uri).path || "/")}
  end

  defp current_user(socket) do
    case socket.assigns do
      %{current_scope: %{user: user}} -> user
      _no_scope -> nil
    end
  end
end
