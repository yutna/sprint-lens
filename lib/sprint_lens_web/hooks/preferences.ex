defmodule SprintLensWeb.Hooks.Preferences do
  @moduledoc """
  Keeps language and theme live inside every LiveView (FR-907, FR-910).

  Mounted on every `live_session`, this hook does three things:

    * puts the viewer's locale on the LiveView process, so strings rendered by
      that process are translated even though the plug pipeline ran in a
      different process;
    * handles the `set_language` and `set_theme` events the switchers push, so
      a change takes effect immediately and is written to the profile rather
      than living only in the browser (FR-003, FR-907, FR-911);
    * remembers the current path, so a language change can re-render the page
      in the new language.

  ## Why a language change navigates

  `gettext/1` calls inside a `~H` template are evaluated when that part of the
  template is rendered, and LiveView only re-renders the parts whose assigns
  changed. Translated text that does not depend on an assign would therefore
  keep its old language until something else happened to touch it. Navigating
  to the same path remounts the view and re-renders everything — a live
  navigation, not a page load, which is what FR-907 asks for.

  Signed-out visitors can still switch: the change applies to their session
  view but there is no profile to persist it to.
  """

  use SprintLensWeb, :verified_routes

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [attach_hook: 4, push_navigate: 2, redirect: 2]

  alias SprintLens.Accounts
  alias SprintLens.Accounts.Scope
  alias SprintLens.Accounts.User
  alias SprintLensWeb.Locale

  def on_mount(:default, _params, session, socket) do
    user = current_user(socket)

    # The plug pipeline ran in another process, so its locale decision does
    # not carry over. Re-resolve here from the same inputs: the user's
    # profile, then the session choice a signed-out visitor made.
    locale = user |> Locale.resolve(nil, session["locale"]) |> Locale.put()

    socket =
      socket
      |> assign(:locale, locale)
      |> assign(:theme, theme_for(user))
      |> assign(:current_path, "/")
      |> attach_hook(:preferences_path, :handle_params, &track_path/3)
      |> attach_hook(:preferences, :handle_event, &handle_preference_event/3)

    {:cont, socket}
  end

  defp track_path(_params, uri, socket) do
    {:cont, assign(socket, :current_path, URI.parse(uri).path || "/")}
  end

  defp handle_preference_event("set_language", %{"language" => language}, socket) do
    cond do
      not Locale.supported?(language) ->
        {:halt, socket}

      is_nil(current_user(socket)) ->
        # No profile to write to; the session cookie is the only place the
        # choice can live, and only a plug can write that.
        {:halt,
         redirect(socket,
           to: ~p"/locale/#{language}?#{[return_to: socket.assigns.current_path]}"
         )}

      true ->
        socket = socket |> persist(:language, language) |> assign(:locale, language)
        Locale.put(language)

        {:halt, push_navigate(socket, to: socket.assigns.current_path)}
    end
  end

  defp handle_preference_event("set_theme", %{"theme" => theme}, socket) do
    if theme in User.themes() do
      {:halt, socket |> persist(:theme, theme) |> assign(:theme, theme)}
    else
      {:halt, socket}
    end
  end

  defp handle_preference_event(_event, _params, socket), do: {:cont, socket}

  defp persist(socket, field, value) do
    case current_user(socket) do
      nil ->
        socket

      user ->
        case Accounts.update_user_profile(user, %{field => value}) do
          {:ok, updated} -> assign(socket, :current_scope, Scope.for_user(updated))
          {:error, _changeset} -> socket
        end
    end
  end

  defp current_user(socket) do
    case socket.assigns do
      %{current_scope: %{user: user}} -> user
      _no_scope -> nil
    end
  end

  defp theme_for(%{theme: theme}) when is_binary(theme), do: theme
  defp theme_for(_user), do: "system"
end
