defmodule SprintLensWeb.SessionLive.Join do
  @moduledoc """
  Joining a session by code (FR-204).

  The short link `/join/:code` lands here with the code filled in, so a code
  read out in a meeting and a link pasted into chat both work.
  """

  use SprintLensWeb, :live_view

  alias SprintLens.Retro

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
      <div class="mx-auto max-w-sm">
        <.header>
          {gettext("Join a retrospective")}
          <:subtitle>{gettext("Enter the code the facilitator shared.")}</:subtitle>
        </.header>

        <.form for={@form} id="join_form" phx-submit="join">
          <.input
            field={@form[:code]}
            type="text"
            label={gettext("Join code")}
            autocomplete="off"
            spellcheck="false"
            class="w-full input font-mono uppercase"
            required
            phx-mounted={JS.focus()}
          />
          <.button variant="primary" phx-disable-with={gettext("Joining...")} class="w-full">
            {gettext("Join")}
          </.button>
        </.form>
      </div>
    </Layouts.app>
    """
  end

  @impl Phoenix.LiveView
  def mount(params, _session, socket) do
    code = params["code"] || ""

    socket = assign(socket, :form, to_form(%{"code" => code}, as: "join"))

    # Arriving through the short link joins straight away rather than
    # showing a form with the answer already in it.
    if code == "" do
      {:ok, socket}
    else
      {:ok, attempt(socket, code)}
    end
  end

  @impl Phoenix.LiveView
  def handle_event("join", %{"join" => %{"code" => code}}, socket) do
    {:noreply, attempt(socket, code)}
  end

  defp attempt(socket, code) do
    case Retro.fetch_session_by_code(socket.assigns.current_scope, code) do
      {:ok, session} ->
        push_navigate(socket, to: ~p"/sessions/#{session}")

      {:error, :session_closed} ->
        put_flash(socket, :error, gettext("This session is closed."))

      {:error, :not_found} ->
        put_flash(socket, :error, gettext("No session with that code."))
    end
  end
end
