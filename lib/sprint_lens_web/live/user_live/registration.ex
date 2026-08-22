defmodule SprintLensWeb.UserLive.Registration do
  @moduledoc """
  SCR-01, registration half. Creates an account from an email address and a
  display name (FR-001, FR-003).

  No password is chosen here: the account is confirmed by a link sent to the
  email address, and the password is set from inside the session afterwards.
  That ordering is what makes the credential pre-stuffing attack described in
  `mix help phx.gen.auth` impossible.
  """

  use SprintLensWeb, :live_view

  alias SprintLens.Accounts
  alias SprintLens.Accounts.User

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
      <Layouts.auth_card>
        <:title>{gettext("Create your account")}</:title>
        <:subtitle>
          {gettext("Already have an account?")}
          <.link navigate={~p"/users/log-in"} class="font-medium text-link hover:underline">
            {gettext("Log in")}
          </.link>
        </:subtitle>

        <.form for={@form} id="registration_form" phx-submit="save" phx-change="validate">
          <.input
            field={@form[:display_name]}
            type="text"
            label={gettext("Display name")}
            autocomplete="name"
            required
            phx-mounted={JS.focus()}
          />
          <.input
            field={@form[:email]}
            type="email"
            label={gettext("Email")}
            autocomplete="username"
            spellcheck="false"
            required
          />

          <.button phx-disable-with={gettext("Creating account...")} variant="primary" class="w-full">
            {gettext("Create an account")}
          </.button>
        </.form>
      </Layouts.auth_card>
    </Layouts.app>
    """
  end

  @impl Phoenix.LiveView
  def mount(_params, _session, %{assigns: %{current_scope: %{user: user}}} = socket)
      when not is_nil(user) do
    {:ok, redirect(socket, to: SprintLensWeb.UserAuth.signed_in_path(socket))}
  end

  def mount(_params, _session, socket) do
    changeset = Accounts.change_user_registration(%User{}, %{}, validate_unique: false)

    {:ok, assign_form(socket, changeset), temporary_assigns: [form: nil]}
  end

  @impl Phoenix.LiveView
  def handle_event("save", %{"user" => user_params}, socket) do
    case Accounts.register_user(user_params) do
      {:ok, user} ->
        {:ok, _email} = Accounts.deliver_login_instructions(user, &url(~p"/users/log-in/#{&1}"))

        {:noreply,
         socket
         |> put_flash(
           :info,
           gettext("We sent a confirmation link to %{email}.", email: user.email)
         )
         |> push_navigate(to: ~p"/users/log-in")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  def handle_event("validate", %{"user" => user_params}, socket) do
    changeset = Accounts.change_user_registration(%User{}, user_params, validate_unique: false)
    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, form: to_form(changeset, as: "user"))
  end
end
