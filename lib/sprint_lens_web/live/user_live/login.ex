defmodule SprintLensWeb.UserLive.Login do
  @moduledoc """
  SCR-01 Sign-in. Offers both baseline methods: a password (FR-001) and a
  short-lived link emailed to the address on file, which doubles as the
  password reset path (FR-004).
  """

  use SprintLensWeb, :live_view

  alias SprintLens.Accounts

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <Layouts.auth_card>
        <:title>{gettext("Log in")}</:title>
        <:subtitle>
          <%= if @current_scope do %>
            {gettext("Please sign in again to change your account settings.")}
          <% else %>
            {gettext("No account yet?")}
            <.link navigate={~p"/users/register"} class="font-medium text-primary hover:underline">
              {gettext("Create one")}
            </.link>
          <% end %>
        </:subtitle>

        <Layouts.notice :if={local_mail_adapter?()}>
          <p>{gettext("You are running the local mail adapter.")}</p>
          <p>
            {gettext("Sent emails appear in")}
            <.link href="/dev/mailbox" class="underline">{gettext("the mailbox")}</.link>.
          </p>
        </Layouts.notice>

        <.form
          :let={f}
          for={@form}
          id="login_form_magic"
          action={~p"/users/log-in"}
          phx-submit="submit_magic"
        >
          <.input
            readonly={!!@current_scope}
            field={f[:email]}
            type="email"
            label={gettext("Email")}
            autocomplete="username"
            spellcheck="false"
            required
            phx-mounted={JS.focus()}
          />
          <.button variant="primary" class="w-full">
            {gettext("Email me a sign-in link")} <span aria-hidden="true">→</span>
          </.button>
        </.form>

        <div class="flex items-center gap-3 py-4 text-caption text-base-content/50">
          <span class="h-px flex-1 bg-base-200" aria-hidden="true" />
          {gettext("or")}
          <span class="h-px flex-1 bg-base-200" aria-hidden="true" />
        </div>

        <.form
          :let={f}
          for={@form}
          id="login_form_password"
          action={~p"/users/log-in"}
          phx-submit="submit_password"
          phx-trigger-action={@trigger_submit}
        >
          <.input
            readonly={!!@current_scope}
            field={f[:email]}
            type="email"
            label={gettext("Email")}
            autocomplete="username"
            spellcheck="false"
            required
          />
          <.input
            field={@form[:password]}
            type="password"
            label={gettext("Password")}
            autocomplete="current-password"
            spellcheck="false"
          />
          <.button variant="primary" class="w-full" name={@form[:remember_me].name} value="true">
            {gettext("Log in and stay logged in")} <span aria-hidden="true">→</span>
          </.button>
          <.button class="w-full mt-2">
            {gettext("Log in only this time")}
          </.button>
        </.form>

        <p class="pt-4 text-center text-label">
          <.link
            navigate={~p"/users/reset-password"}
            class="font-medium text-primary hover:underline"
          >
            {gettext("Forgot your password?")}
          </.link>
        </p>
      </Layouts.auth_card>
    </Layouts.app>
    """
  end

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    email =
      Phoenix.Flash.get(socket.assigns.flash, :email) ||
        get_in(socket.assigns, [:current_scope, Access.key(:user), Access.key(:email)])

    form = to_form(%{"email" => email}, as: "user")

    {:ok, assign(socket, form: form, trigger_submit: false)}
  end

  @impl Phoenix.LiveView
  def handle_event("submit_password", _params, socket) do
    {:noreply, assign(socket, :trigger_submit, true)}
  end

  def handle_event("submit_magic", %{"user" => %{"email" => email}}, socket) do
    if user = Accounts.get_user_by_email(email) do
      Accounts.deliver_login_instructions(
        user,
        &url(~p"/users/log-in/#{&1}")
      )
    end

    info = gettext("If that email has an account, a sign-in link is on its way.")

    {:noreply,
     socket
     |> put_flash(:info, info)
     |> push_navigate(to: ~p"/users/log-in")}
  end

  defp local_mail_adapter? do
    Application.get_env(:sprint_lens, SprintLens.Mailer)[:adapter] == Swoosh.Adapters.Local
  end
end
