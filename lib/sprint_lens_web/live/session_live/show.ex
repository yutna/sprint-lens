defmodule SprintLensWeb.SessionLive.Show do
  @moduledoc """
  SCR-07 Live board — the phase, timer, presence and facilitator controls.

  The cards themselves arrive with the board milestone; what is here is the
  frame they live in, and the realtime machinery underneath: the snapshot on
  mount (FR-309), the section 7.3 events, presence with a ready count
  (FR-213), and the facilitator hand-off (FR-207).

  ## Reconnection

  A LiveView that loses its socket remounts. `mount/3` always takes a fresh
  snapshot, so a client that missed events while away does not have to work
  out what it missed (FR-309, NFR-401).
  """

  use SprintLensWeb, :live_view

  alias SprintLens.Retro
  alias SprintLens.Retro.Events
  alias SprintLens.Retro.Session
  alias SprintLens.Retro.SessionServer
  alias SprintLensWeb.Presence

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} locale={@locale} theme={@theme}>
      <.header>
        {@session.title}
        <:subtitle>
          <span class={["badge badge-sm", state_class(@session)]}>
            {state_label(Session.state(@session))}
          </span>
          <span :if={@session.is_anonymous} class="badge badge-ghost badge-sm">
            {gettext("Anonymous")}
          </span>
          <span :if={@session.is_blind} class="badge badge-ghost badge-sm">
            {gettext("Cards hidden until revealed")}
          </span>
        </:subtitle>
        <:actions>
          <span id="join-code" class="badge badge-outline font-mono">
            {@session.join_code}
          </span>
          <.button
            :if={@is_facilitator and Session.state(@session) == :created}
            id="start-session"
            variant="primary"
            phx-click="start"
          >
            {gettext("Start")}
          </.button>
          <.button
            :if={@is_facilitator and Session.state(@session) == :active}
            id="close-session"
            phx-click="close"
            data-confirm={gettext("Close this session? It becomes read-only.")}
          >
            {gettext("Close")}
          </.button>
        </:actions>
      </.header>

      <%!--
        The phase is announced to assistive technology as it changes, which is
        what FR-915 asks for; the region is polite so it does not interrupt
        someone mid-sentence.
      --%>
      <section
        id="phase-bar"
        aria-live="polite"
        aria-label={gettext("Phase")}
        class="flex flex-wrap items-center gap-2 rounded-box border border-base-300 p-3"
      >
        <ol class="flex flex-wrap gap-1">
          <li :for={phase <- Session.phases()}>
            <button
              :if={@is_facilitator and Session.state(@session) == :active}
              type="button"
              id={"phase-#{phase}"}
              class={["btn btn-xs", phase == @phase && "btn-primary"]}
              aria-current={to_string(phase == @phase)}
              phx-click="set_phase"
              phx-value-phase={phase}
            >
              {phase_label(phase)}
            </button>
            <span
              :if={not (@is_facilitator and Session.state(@session) == :active)}
              class={["badge badge-sm", phase == @phase && "badge-primary"]}
              aria-current={to_string(phase == @phase)}
            >
              {phase_label(phase)}
            </span>
          </li>
        </ol>

        <div :if={@is_facilitator and Session.state(@session) == :active} class="ml-auto flex gap-1">
          <.button id="revert-phase" phx-click="revert_phase" class="btn btn-ghost btn-xs">
            {gettext("Back")}
          </.button>
          <.button id="advance-phase" phx-click="advance_phase" class="btn btn-ghost btn-xs">
            {gettext("Next")}
          </.button>
        </div>
      </section>

      <div class="grid gap-4 sm:grid-cols-[2fr_1fr]">
        <section
          id="board"
          aria-label={gettext("Board")}
          class="rounded-box border border-base-300 p-3"
        >
          <ol
            class="grid gap-3"
            style={"grid-template-columns: repeat(#{length(@columns)}, minmax(0, 1fr))"}
          >
            <li :for={column <- @columns} id={"column-#{column.id}"} class="min-w-0">
              <h3 class="font-semibold">{column.name}</h3>
              <p :if={column.hint} class="text-sm opacity-70">{column.hint}</p>
            </li>
          </ol>
        </section>

        <aside class="space-y-4">
          <section
            id="timer"
            aria-live="polite"
            aria-label={gettext("Timer")}
            class="rounded-box border border-base-300 p-3"
          >
            <p class="font-mono text-2xl" id="timer-remaining">
              {format_remaining(@timer.remaining_s)}
            </p>
            <div :if={@is_facilitator} class="mt-2 flex flex-wrap gap-1">
              <.button
                :for={{label, seconds} <- timer_presets()}
                id={"timer-#{seconds}"}
                phx-click="start_timer"
                phx-value-seconds={seconds}
                class="btn btn-ghost btn-xs"
              >
                {label}
              </.button>
              <.button id="pause-timer" phx-click="pause_timer" class="btn btn-ghost btn-xs">
                {gettext("Pause")}
              </.button>
              <.button id="reset-timer" phx-click="reset_timer" class="btn btn-ghost btn-xs">
                {gettext("Reset")}
              </.button>
            </div>
          </section>

          <section
            id="presence"
            aria-label={gettext("Who is here")}
            class="rounded-box border border-base-300 p-3"
          >
            <p class="mb-2 text-sm opacity-70" id="ready-count">
              {gettext("%{ready} of %{total} ready", ready: @ready_count, total: @present_count)}
            </p>

            <ul class="space-y-1">
              <li :for={{user_id, meta} <- @participants} id={"participant-#{user_id}"}>
                <span class={["badge badge-xs", meta[:ready] && "badge-success"]} />
                <span>{meta[:display_name]}</span>
                <span :if={user_id == @session.facilitator_id} class="badge badge-xs badge-primary">
                  {gettext("Facilitator")}
                </span>
                <.button
                  :if={@is_facilitator and user_id != @session.facilitator_id}
                  id={"hand-over-#{user_id}"}
                  phx-click="transfer_facilitator"
                  phx-value-user-id={user_id}
                  class="btn btn-ghost btn-xs"
                >
                  {gettext("Hand over")}
                </.button>
              </li>
            </ul>

            <.button
              :if={Session.state(@session) == :active}
              id="toggle-ready"
              phx-click="toggle_ready"
              class="btn btn-soft btn-sm mt-3 w-full"
              aria-pressed={to_string(@ready)}
            >
              {if @ready, do: gettext("Not ready"), else: gettext("I am ready")}
            </.button>
          </section>
        </aside>
      </div>
    </Layouts.app>
    """
  end

  @impl Phoenix.LiveView
  def mount(%{"id" => id}, _session, socket) do
    case Retro.fetch_session(socket.assigns.current_scope, id) do
      {:ok, session} ->
        {:ok, join(socket, session)}

      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, gettext("That resource does not exist."))
         |> push_navigate(to: ~p"/home")}
    end
  end

  defp join(socket, session) do
    user = socket.assigns.current_scope.user

    if connected?(socket) do
      Events.subscribe(session.id)
      Phoenix.PubSub.subscribe(SprintLens.PubSub, Presence.topic(session.id))

      Presence.track_user(self(), session.id, user.id, %{
        display_name: user.display_name,
        joined_at: System.system_time(:millisecond)
      })

      {:ok, _pid} = SessionServer.ensure_started(session.id)
      SessionServer.presence_changed(session.id)
    end

    socket
    |> assign(:page_title, session.title)
    |> assign(:ready, false)
    |> apply_snapshot(session)
    |> assign_presence()
  end

  # Everything the board shows is derived from one snapshot, so a reconnect
  # and a fresh mount produce the same state (FR-309).
  defp apply_snapshot(socket, session) do
    snapshot = Retro.snapshot(session)

    socket
    |> assign(:session, session)
    |> assign(:phase, snapshot.phase)
    |> assign(:columns, snapshot.columns)
    |> assign(:timer, snapshot.timer)
    |> assign(:is_facilitator, Retro.facilitator?(socket.assigns.current_scope, session))
  end

  @impl Phoenix.LiveView
  def handle_info({:retro_event, "phase.changed", _payload}, socket),
    do: {:noreply, reload(socket)}

  def handle_info({:retro_event, "timer.updated", _payload}, socket),
    do: {:noreply, reload(socket)}

  def handle_info({:retro_event, "presence.updated", _payload}, socket) do
    {:noreply, socket |> reload() |> assign_presence()}
  end

  def handle_info({:retro_event, "session.closed", _payload}, socket) do
    {:noreply,
     socket
     |> reload()
     |> put_flash(:info, gettext("This session is closed."))}
  end

  def handle_info({:retro_event, _event, _payload}, socket), do: {:noreply, socket}

  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff"}, socket) do
    SessionServer.presence_changed(socket.assigns.session.id)

    {:noreply, assign_presence(socket)}
  end

  @impl Phoenix.LiveView
  def handle_event("start", _params, socket) do
    respond(socket, Retro.start_session(socket.assigns.current_scope, socket.assigns.session))
  end

  def handle_event("close", _params, socket) do
    respond(socket, Retro.close_session(socket.assigns.current_scope, socket.assigns.session))
  end

  def handle_event("advance_phase", _params, socket) do
    respond(socket, Retro.advance_phase(socket.assigns.current_scope, socket.assigns.session))
  end

  def handle_event("revert_phase", _params, socket) do
    respond(socket, Retro.revert_phase(socket.assigns.current_scope, socket.assigns.session))
  end

  def handle_event("set_phase", %{"phase" => phase}, socket) do
    respond(
      socket,
      Retro.set_phase(socket.assigns.current_scope, socket.assigns.session, to_phase(phase))
    )
  end

  def handle_event("start_timer", %{"seconds" => seconds}, socket) do
    respond(
      socket,
      Retro.start_timer(
        socket.assigns.current_scope,
        socket.assigns.session,
        String.to_integer(seconds)
      )
    )
  end

  def handle_event("pause_timer", _params, socket) do
    respond(socket, Retro.pause_timer(socket.assigns.current_scope, socket.assigns.session))
  end

  def handle_event("reset_timer", _params, socket) do
    respond(socket, Retro.reset_timer(socket.assigns.current_scope, socket.assigns.session))
  end

  def handle_event("transfer_facilitator", %{"user-id" => user_id}, socket) do
    respond(
      socket,
      Retro.transfer_facilitator(
        socket.assigns.current_scope,
        socket.assigns.session,
        String.to_integer(user_id)
      )
    )
  end

  def handle_event("toggle_ready", _params, socket) do
    ready = not socket.assigns.ready

    Presence.update_user(
      self(),
      socket.assigns.session.id,
      socket.assigns.current_scope.user.id,
      %{
        ready: ready
      }
    )

    {:noreply, socket |> assign(:ready, ready) |> assign_presence()}
  end

  defp respond(socket, {:ok, session}), do: {:noreply, apply_snapshot(socket, session)}

  defp respond(socket, {:error, %Ecto.Changeset{}}) do
    {:noreply, put_flash(socket, :error, gettext("Some fields need attention."))}
  end

  defp respond(socket, {:error, reason}) do
    {:noreply, put_flash(socket, :error, error_message(reason))}
  end

  defp error_message(:unauthorized), do: gettext("You do not have permission to do that.")
  defp error_message(:wrong_phase), do: gettext("That action is not available in this phase.")
  defp error_message(:wrong_state), do: gettext("That action is not available right now.")
  defp error_message(:not_found), do: gettext("That resource does not exist.")

  # Re-reads rather than trusting the broadcast payload: the payload says what
  # changed, the database says what is true.
  defp reload(socket) do
    case Retro.fetch_session(socket.assigns.current_scope, socket.assigns.session.id) do
      {:ok, session} -> apply_snapshot(socket, session)
      {:error, :not_found} -> socket
    end
  end

  defp assign_presence(socket) do
    participants = Presence.list_users(socket.assigns.session.id)
    {ready, total} = Presence.ready_count(socket.assigns.session.id)

    socket
    |> assign(:participants, Enum.sort_by(participants, fn {_id, meta} -> meta[:joined_at] end))
    |> assign(:ready_count, ready)
    |> assign(:present_count, total)
  end

  defp to_phase(phase) do
    Enum.find(Session.phases(), &(Atom.to_string(&1) == phase))
  end

  defp timer_presets do
    [{gettext("1 min"), 60}, {gettext("5 min"), 300}, {gettext("10 min"), 600}]
  end

  defp format_remaining(nil), do: "—"

  defp format_remaining(seconds) do
    minutes = div(seconds, 60)
    rest = rem(seconds, 60)

    "#{minutes}:#{String.pad_leading(Integer.to_string(rest), 2, "0")}"
  end

  defp phase_label(:checkin), do: gettext("Check-in")
  defp phase_label(:brainstorm), do: gettext("Brainstorm")
  defp phase_label(:group), do: gettext("Group")
  defp phase_label(:vote), do: gettext("Vote")
  defp phase_label(:discuss), do: gettext("Discuss")
  defp phase_label(:wrapup), do: gettext("Wrap-up")

  defp state_label(:created), do: gettext("Not started")
  defp state_label(:active), do: gettext("Running")
  defp state_label(:closed), do: gettext("Closed")

  defp state_class(session) do
    case Session.state(session) do
      :active -> "badge-primary"
      :closed -> "badge-ghost"
      _created -> "badge-outline"
    end
  end
end
