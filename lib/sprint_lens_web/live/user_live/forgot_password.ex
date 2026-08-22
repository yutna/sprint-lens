defmodule SprintLensWeb.UserLive.ForgotPassword do
  @moduledoc """
  The password reset entry point (FR-004).

  Emails a short-lived sign-in link. Following it signs the user in, and they
  then set a new password from `/users/settings` — a reset link never sets a
  password by itself, so an old link found in a mailbox later is useless.

  The response is identical whether or not the address is registered.
  Confirming which addresses have accounts is a disclosure this screen has no
  reason to make.
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
      <Layouts.auth_card>
        <:title>{gettext("Reset your password")}</:title>
        <:subtitle>
          {gettext("We will email you a link to sign in, so you can choose a new password.")}
        </:subtitle>

        <.form for={@form} id="forgot_password_form" phx-submit="send">
          <.input
            field={@form[:email]}
            type="email"
            label={gettext("Email")}
            autocomplete="username"
            spellcheck="false"
            required
            phx-mounted={JS.focus()}
          />
          <.button variant="primary" phx-disable-with={gettext("Sending...")} class="w-full">
            {gettext("Send reset link")}
          </.button>
        </.form>

        <p class="mt-4 text-center text-sm">
          <.link navigate={~p"/users/log-in"} class="font-semibold hover:underline">
            {gettext("Back to log in")}
          </.link>
        </p>
      </Layouts.auth_card>
    </Layouts.app>
    """
  end

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    {:ok, assign(socket, form: to_form(%{}, as: "user"))}
  end

  @impl Phoenix.LiveView
  def handle_event("send", %{"user" => %{"email" => email}}, socket) do
    if user = Accounts.get_user_by_email(email) do
      Accounts.deliver_password_reset_instructions(user, &url(~p"/users/log-in/#{&1}"))
    end

    {:noreply,
     socket
     |> put_flash(
       :info,
       gettext("If that email has an account, a reset link is on its way.")
     )
     |> push_navigate(to: ~p"/users/log-in")}
  end
end
