defmodule SprintLensWeb.UserLive.Preferences do
  @moduledoc """
  SCR-13 Preferences: display name, avatar, language and theme (FR-003).

  Separate from `/users/settings`, which changes the email address and the
  password and therefore demands a recent authentication. Changing your theme
  should not send you back to the login page, so this screen needs only a
  signed-in session.
  """

  use SprintLensWeb, :live_view

  alias SprintLens.Accounts

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      locale={@locale}
      theme={@theme}
      current_path={@current_path}
    >
      <.header>
        {gettext("Preferences")}
        <:subtitle>{gettext("How you appear, and how the app appears to you.")}</:subtitle>
        <:actions>
          <.link navigate={~p"/users/settings"} class="btn btn-ghost btn-sm">
            {gettext("Account settings")}
          </.link>
        </:actions>
      </.header>

      <.form
        for={@form}
        id="preferences_form"
        phx-change="validate"
        phx-submit="save"
        class="max-w-md"
      >
        <.input
          field={@form[:display_name]}
          type="text"
          label={gettext("Display name")}
          autocomplete="name"
          required
        />
        <.input
          field={@form[:avatar_url]}
          type="url"
          label={gettext("Avatar URL")}
          spellcheck="false"
        />
        <.input
          field={@form[:language]}
          type="select"
          label={gettext("Language")}
          options={Layouts.language_choices()}
        />
        <.input
          field={@form[:theme]}
          type="select"
          label={gettext("Theme")}
          options={Layouts.theme_choices()}
        />

        <.button variant="primary" phx-disable-with={gettext("Saving...")}>
          {gettext("Save preferences")}
        </.button>
      </.form>
    </Layouts.app>
    """
  end

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user

    {:ok, assign_form(socket, Accounts.change_user_profile(user))}
  end

  @impl Phoenix.LiveView
  def handle_event("validate", %{"user" => user_params}, socket) do
    changeset =
      socket.assigns.current_scope.user
      |> Accounts.change_user_profile(user_params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"user" => user_params}, socket) do
    case Accounts.update_user_profile(socket.assigns.current_scope.user, user_params) do
      {:ok, user} ->
        # Reflect the change in this session immediately rather than waiting
        # for the next request (FR-907, FR-911). A language change navigates
        # to this same page so every translated string re-renders — see
        # `SprintLensWeb.Hooks.Preferences` for why.
        SprintLensWeb.Locale.put(user.language)

        socket =
          socket
          |> assign(:current_scope, SprintLens.Accounts.Scope.for_user(user))
          |> assign(:locale, user.language)
          |> assign(:theme, user.theme)
          |> assign_form(Accounts.change_user_profile(user))
          |> put_flash(:info, gettext("Preferences saved."))

        {:noreply, push_navigate(socket, to: ~p"/users/preferences")}

      {:error, changeset} ->
        {:noreply, assign_form(socket, Map.put(changeset, :action, :insert))}
    end
  end

  defp assign_form(socket, changeset), do: assign(socket, form: to_form(changeset, as: "user"))
end
