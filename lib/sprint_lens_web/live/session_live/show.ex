defmodule SprintLensWeb.SessionLive.Show do
  @moduledoc """
  SCR-07 Live board — the phase, timer, presence and facilitator controls.

  The phase bar, the timer, presence, the facilitator controls, and the board
  itself: columns, cards, clustering and the check-in mood.

  What a person can do here is decided by `SprintLens.Retro.Board`, not by
  this module. The controls are rendered from the same `authorize/3` the
  context enforces, so a hidden button and a refused event agree by
  construction rather than by being kept in step (NFR-201).

  ## Reconnection

  A LiveView that loses its socket remounts. `mount/3` always takes a fresh
  snapshot, so a client that missed events while away does not have to work
  out what it missed (FR-309, NFR-401).
  """

  use SprintLensWeb, :live_view

  import SprintLensWeb.ActionComponents
  import SprintLensWeb.BoardComponents

  alias SprintLens.Actions
  alias SprintLens.Retro
  alias SprintLens.Retro.Board
  alias SprintLens.Retro.Events
  alias SprintLens.Retro.Session
  alias SprintLens.Retro.SessionServer
  alias SprintLens.Teams
  alias SprintLensWeb.Presence

  import SprintLensWeb.LobbyComponents
  import SprintLensWeb.RoomComponents

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
        {@session.title}
        <:subtitle>
          <span :if={waiting?(@session)}>{@session.team.name}</span>
          <span :if={not waiting?(@session)} class="flex flex-wrap items-center gap-2">
            <.badge tone={state_tone(@session)}>{state_label(Session.state(@session))}</.badge>
            <.badge :if={@session.is_anonymous}>{gettext("Anonymous")}</.badge>
            <.badge :if={@session.is_blind}>{gettext("Cards hidden until revealed")}</.badge>
          </span>
        </:subtitle>
        <:actions>
          <span
            :if={not waiting?(@session)}
            id="join-code"
            class="rounded-control border border-base-300 px-2 py-1 font-mono text-caption"
          >
            {@session.join_code}
          </span>
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
        Before it starts there is no board to show — only empty columns, a
        phase bar pointing at a phase nobody is in, and timer controls for a
        timer nobody is running. So the room gets the screen instead, and
        everything below waits for the session to begin (see
        `SprintLensWeb.LobbyComponents`).
      --%>
      <.lobby
        :if={waiting?(@session)}
        session={@session}
        columns={@columns}
        participants={@participants}
        present_count={@present_count}
        ready_count={@ready_count}
        ready={@ready}
        is_facilitator={@is_facilitator}
        join_url={@join_url}
      />

      <.phase_stepper
        :if={not waiting?(@session)}
        phase={@phase}
        session={@session}
        is_facilitator={@is_facilitator}
      />

      <div :if={not waiting?(@session)} class="grid gap-4 sm:grid-cols-[2fr_1fr]">
        <div id="board" aria-label={gettext("Board")} class="space-y-4">
          <%!--
            The check-in opens with what the team still owes from last time
            (FR-505), before anything new is written.
          --%>
          <.carry_over_review
            :if={@phase == :checkin}
            actions={@open_actions}
            can_carry={@can_carry}
            now={@now}
          />

          <.icebreaker :if={@phase == :checkin} session={@session} />

          <.mood_panel
            :if={@phase == :checkin}
            kind={:checkin_mood}
            prompt={gettext("How are you feeling?")}
            summary={@mood}
            mine={@my_mood}
            open={@can_checkin}
          />

          <.mood_panel
            :if={@phase == :wrapup}
            kind={:roti}
            prompt={gettext("Was this time well spent?")}
            summary={@roti}
            mine={@my_roti}
            open={@can_roti}
          />

          <.topics_panel
            :if={@phase in [:vote, :discuss]}
            topics={@topics}
            summary={@vote_summary}
            phase={@phase}
            can_vote={@can_vote}
            is_facilitator={@is_facilitator}
            editing_note={@editing_note}
          />

          <section
            :if={@phase in [:discuss, :wrapup]}
            id="actions-panel"
            aria-labelledby="actions-heading"
            class="space-y-3 rounded-panel border border-base-200 bg-base-100 p-4"
          >
            <h3 id="actions-heading" class="text-heading font-semibold">
              {gettext("What the team will do")}
            </h3>

            <.action_form
              :if={@can_write_action}
              form={@action_form}
              members={@members}
              topic={@focused_topic}
            />

            <ul id="action-list" class="space-y-2">
              <.action_row
                :for={action <- @session_actions}
                action={action}
                editable={true}
                now={@now}
              />
            </ul>

            <p :if={@session_actions == []} id="actions-empty" class="text-label text-base-content/60">
              {gettext("Nothing agreed yet.")}
            </p>
          </section>

          <.column_tabs columns={@columns} active={@active_column} />

          <div class={["grid gap-3", column_grid(length(@columns))]}>
            <.board_column
              :for={column <- @columns}
              column={column}
              cards={cards_in(@cards, column)}
              session={@session}
              active={@active_column}
              columns={@columns}
              can_write={@can_write}
              can_move={@can_move}
              current_user_id={@current_scope.user.id}
              is_facilitator={@is_facilitator}
              editing={@editing}
              can_group={@can_group}
              selected={@selected}
            />
          </div>

          <div
            :if={@phase == :group}
            class="space-y-3 rounded-panel border border-base-200 bg-base-100 p-4"
          >
            <.form
              for={to_form(%{}, as: :group)}
              id="group_form"
              phx-submit="create_group"
              class="flex flex-wrap items-end gap-2"
            >
              <div class="grow">
                <.input
                  field={to_form(%{}, as: :group)[:label]}
                  type="text"
                  label={gettext("Merge the selected cards into a group named")}
                  required
                />
              </div>
              <.button variant="primary" class="mb-4">{gettext("Group")}</.button>
            </.form>

            <ul id="groups" class="space-y-1">
              <li
                :for={group <- @groups}
                id={"group-#{group.id}"}
                class="flex flex-wrap items-center gap-2"
              >
                <.badge>{group.label}</.badge>
                <span class="text-label text-base-content/60">
                  {ngettext("%{count} card", "%{count} cards", length(group.cards),
                    count: length(group.cards)
                  )}
                </span>
                <.button
                  id={"ungroup-#{group.id}"}
                  phx-click="delete_group"
                  phx-value-id={group.id}
                  variant="ghost"
                  size="sm"
                >
                  {gettext("Ungroup")}
                </.button>
              </li>
            </ul>
          </div>

          <%!--
            The one dramatic moment the product has: everybody's cards arrive
            at once. It is worth saying what is about to happen rather than
            leaving a note in small grey text under the board.
          --%>
          <div
            :if={@session.is_blind and not @session.cards_revealed}
            class="flex flex-wrap items-center gap-3 rounded-panel border border-primary/30 bg-primary/5 p-4"
          >
            <p id="blind-notice" class="min-w-0 grow text-label">
              {gettext("Cards are hidden until the facilitator reveals them.")}
            </p>
            <.button
              :if={@is_facilitator}
              id="reveal-cards"
              variant="primary"
              phx-click="reveal_cards"
            >
              {gettext("Reveal all cards")}
            </.button>
          </div>
        </div>

        <%!--
          The timer and who is ready are what the room is watching, so they
          stay on screen while the board scrolls under them (plan 02).
        --%>
        <aside class="space-y-4 sm:sticky sm:top-4 sm:self-start">
          <.timer_panel timer={@timer} is_facilitator={@is_facilitator} />

          <.presence_panel
            session={@session}
            participants={@participants}
            present_count={@present_count}
            ready_count={@ready_count}
            ready={@ready}
            is_facilitator={@is_facilitator}
          />
        </aside>
      </div>
    </Layouts.app>
    """
  end

  # The board and the lobby are the two halves of this screen, and exactly one
  # of them renders — which is what lets both use `join-code`, `participant-*`
  # and `toggle-ready` for the same things rather than two sets of names.
  defp waiting?(session), do: Session.state(session) == :created

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
    |> assign(:join_url, SprintLensWeb.Endpoint.url() <> ~p"/join/#{session.join_code}")
    |> assign(:ready, false)
    |> assign(:editing, nil)
    |> assign(:editing_note, nil)
    |> assign(:selected, MapSet.new())
    |> assign(:members, Enum.map(Teams.list_members(session.team), & &1.user))
    |> assign(:active_column, nil)
    |> apply_snapshot(session)
    |> assign_presence()
  end

  # Everything the board shows is derived from one snapshot, so a reconnect
  # and a fresh mount produce the same state (FR-309).
  defp apply_snapshot(socket, session) do
    snapshot = Retro.snapshot(session)
    scope = socket.assigns.current_scope

    socket
    |> assign(:session, session)
    |> assign(:phase, snapshot.phase)
    |> assign(:columns, snapshot.columns)
    |> assign(:timer, snapshot.timer)
    |> assign(:is_facilitator, Retro.facilitator?(scope, session))
    |> assign_active_column(snapshot.columns)
    |> assign_permissions(session)
    |> assign_board(session)
  end

  # What the person may do, asked of the same function that enforces it. A
  # hidden control and a refused event cannot disagree (NFR-201).
  defp assign_permissions(socket, session) do
    scope = socket.assigns.current_scope

    socket
    |> assign(:can_write, Board.authorize(scope, session, :write_card) == :ok)
    |> assign(:can_move, Board.authorize(scope, session, :move_card) == :ok)
    |> assign(:can_group, Board.authorize(scope, session, :group_cards) == :ok)
    |> assign(:can_checkin, Board.authorize(scope, session, :checkin_mood) == :ok)
    |> assign(:can_roti, Board.authorize(scope, session, :roti) == :ok)
    |> assign(:can_vote, Board.authorize(scope, session, :cast_vote) == :ok)
    |> assign(:can_write_action, Session.phase(session) in [:discuss, :wrapup] and open?(session))
    |> assign(:can_carry, Session.phase(session) == :checkin and open?(session))
  end

  defp open?(session), do: Session.state(session) == :active

  defp assign_board(socket, session) do
    scope = socket.assigns.current_scope

    socket
    |> assign(:cards, Board.visible_cards(session, scope))
    |> assign(:groups, Board.list_groups(session))
    |> assign(:mood, Board.mood_summary(session, :checkin_mood))
    |> assign(:roti, Board.mood_summary(session, :roti))
    |> assign(:my_mood, Board.my_mood(scope, session, :checkin_mood))
    |> assign(:my_roti, Board.my_mood(scope, session, :roti))
    |> assign(:topics, Board.topics(session, scope))
    |> assign(:vote_summary, Board.vote_summary(session, scope))
    |> assign_actions(session)
  end

  # Actions live beside the board rather than on it: the check-in review is
  # the *team's* open items (FR-505) while the panel below shows what this
  # session has produced so far (FR-501).
  defp assign_actions(socket, session) do
    socket
    |> assign(:now, DateTime.utc_now())
    |> assign(:open_actions, Actions.list_open_actions(session.team))
    |> assign(:session_actions, Actions.list_session_actions(session))
    |> assign(:focused_topic, Enum.find(socket.assigns.topics, & &1.focused?))
    |> assign_new(:action_form, fn -> to_form(Actions.change_action(), as: :action) end)
  end

  # The narrow-screen board shows one column at a time (FR-902); the first is
  # active until someone chooses another.
  defp assign_active_column(socket, columns) do
    active = socket.assigns[:active_column]

    if active && Enum.any?(columns, &(&1.id == active)) do
      socket
    else
      assign(socket, :active_column, columns |> List.first() |> then(&(&1 && &1.id)))
    end
  end

  defp cards_in(cards, column), do: Enum.filter(cards, &(&1.column_id == column.id))

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

  def handle_info({:retro_event, "mood.updated", _payload}, socket) do
    {:noreply, assign_board(socket, socket.assigns.session)}
  end

  # Cards, clusters and reveals all change what is on the board, and the
  # board is re-read rather than patched from the payload: the event says
  # something changed, the database says what is true.
  def handle_info({:retro_event, _event, _payload}, socket) do
    {:noreply, reload(socket)}
  end

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

  def handle_event("select_column", %{"column-id" => column_id}, socket) do
    {:noreply, assign(socket, :active_column, String.to_integer(column_id))}
  end

  def handle_event("create_card", %{"card" => params}, socket) do
    case Board.create_card(socket.assigns.current_scope, socket.assigns.session, params) do
      {:ok, _card} ->
        {:noreply, refresh(socket)}

      error ->
        # The box emptied itself when the form was submitted (FR-920). The
        # server said no, so the words go back where they were, beside the
        # notice that says why.
        {_noreply, socket} = board_result(error, socket)

        {:noreply,
         push_event(socket, "card:rejected", %{
           column_id: params["column_id"],
           text: params["text"]
         })}
    end
  end

  def handle_event("edit_card", %{"id" => id}, socket) do
    {:noreply, assign(socket, :editing, String.to_integer(id))}
  end

  def handle_event("cancel_edit", _params, socket) do
    {:noreply, assign(socket, :editing, nil)}
  end

  def handle_event("update_card", %{"card" => %{"id" => id, "text" => text}}, socket) do
    with {:ok, card} <- fetch_card(socket, id),
         {:ok, _updated} <-
           Board.update_card(socket.assigns.current_scope, socket.assigns.session, card, %{
             text: text
           }) do
      {:noreply, socket |> assign(:editing, nil) |> refresh()}
    else
      error -> board_result(error, socket)
    end
  end

  def handle_event("delete_card", %{"id" => id}, socket) do
    with {:ok, card} <- fetch_card(socket, id),
         :ok <- Board.delete_card(socket.assigns.current_scope, socket.assigns.session, card) do
      {:noreply, refresh(socket)}
    else
      error -> board_result(error, socket)
    end
  end

  def handle_event("move_card", %{"id" => id, "column-id" => column_id}, socket) do
    with {:ok, card} <- fetch_card(socket, id),
         {:ok, _moved} <-
           Board.move_card(
             socket.assigns.current_scope,
             socket.assigns.session,
             card,
             String.to_integer(column_id),
             0
           ) do
      {:noreply, socket |> assign(:active_column, String.to_integer(column_id)) |> refresh()}
    else
      error -> board_result(error, socket)
    end
  end

  def handle_event("toggle_card", %{"id" => id}, socket) do
    id = String.to_integer(id)
    selected = socket.assigns.selected

    selected =
      if MapSet.member?(selected, id),
        do: MapSet.delete(selected, id),
        else: MapSet.put(selected, id)

    {:noreply, assign(socket, :selected, selected)}
  end

  def handle_event("create_group", %{"group" => %{"label" => label}}, socket) do
    case MapSet.to_list(socket.assigns.selected) do
      [] ->
        {:noreply, put_flash(socket, :error, gettext("Choose the cards to merge first."))}

      card_ids ->
        socket.assigns.current_scope
        |> Board.create_group(socket.assigns.session, label, card_ids)
        |> group_result(socket)
    end
  end

  def handle_event("delete_group", %{"id" => id}, socket) do
    with {:ok, group} <- fetch_group(socket, id),
         :ok <- Board.delete_group(socket.assigns.current_scope, socket.assigns.session, group) do
      {:noreply, refresh(socket)}
    else
      error -> board_result(error, socket)
    end
  end

  def handle_event("reveal_cards", _params, socket) do
    case Board.reveal_cards(socket.assigns.current_scope, socket.assigns.session) do
      {:ok, session} -> {:noreply, apply_snapshot(socket, session)}
      error -> board_result(error, socket)
    end
  end

  def handle_event("record_mood", %{"kind" => kind, "score" => score}, socket) do
    socket.assigns.current_scope
    |> Board.record_mood(
      socket.assigns.session,
      to_mood_kind(kind),
      String.to_integer(score)
    )
    |> board_result(socket)
  end

  def handle_event("cast_vote", %{"topic" => topic}, socket) do
    socket.assigns.current_scope
    |> Board.cast_vote(socket.assigns.session, topic)
    |> board_result(socket)
  end

  def handle_event("retract_vote", %{"topic" => topic}, socket) do
    socket.assigns.current_scope
    |> Board.retract_vote(socket.assigns.session, topic)
    |> board_result(socket)
  end

  def handle_event("reveal_votes", _params, socket) do
    case Board.reveal_votes(socket.assigns.current_scope, socket.assigns.session) do
      {:ok, session} -> {:noreply, apply_snapshot(socket, session)}
      error -> board_result(error, socket)
    end
  end

  def handle_event("set_focus", %{"topic" => topic}, socket) do
    focus(socket, topic)
  end

  def handle_event("clear_focus", _params, socket) do
    focus(socket, nil)
  end

  def handle_event("edit_note", %{"topic" => topic}, socket) do
    {:noreply, assign(socket, :editing_note, topic)}
  end

  def handle_event("cancel_note", _params, socket) do
    {:noreply, assign(socket, :editing_note, nil)}
  end

  def handle_event("save_note", %{"note" => %{"topic" => topic, "body" => body}}, socket) do
    case Board.write_note(socket.assigns.current_scope, socket.assigns.session, topic, body) do
      {:ok, _note} -> {:noreply, socket |> assign(:editing_note, nil) |> refresh()}
      error -> board_result(error, socket)
    end
  end

  def handle_event("create_action", %{"action" => params}, socket) do
    case Actions.create_action(socket.assigns.current_scope, socket.assigns.session, params) do
      {:ok, _item} ->
        {:noreply,
         socket
         |> assign(:action_form, to_form(Actions.change_action(), as: :action))
         |> refresh()}

      error ->
        board_result(error, socket)
    end
  end

  def handle_event("update_action_status", %{"action_id" => id, "status" => status}, socket) do
    with {:ok, item} <- Actions.fetch_action(socket.assigns.current_scope, id),
         {:ok, _updated} <-
           Actions.update_action(socket.assigns.current_scope, item, %{status: status}) do
      {:noreply, refresh(socket)}
    else
      error -> board_result(error, socket)
    end
  end

  def handle_event("carry_over", %{"id" => id}, socket) do
    with {:ok, item} <- Actions.fetch_action(socket.assigns.current_scope, id),
         {:ok, _carried} <-
           Actions.carry_over(socket.assigns.current_scope, socket.assigns.session, item) do
      {:noreply, refresh(socket)}
    else
      error -> board_result(error, socket)
    end
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

  defp focus(socket, topic) do
    case Board.set_focus(socket.assigns.current_scope, socket.assigns.session, topic) do
      {:ok, session} -> {:noreply, apply_snapshot(socket, session)}
      error -> board_result(error, socket)
    end
  end

  defp group_result({:ok, _group}, socket) do
    {:noreply, socket |> assign(:selected, MapSet.new()) |> refresh()}
  end

  defp group_result(error, socket), do: board_result(error, socket)

  defp board_result(:ok, socket), do: {:noreply, refresh(socket)}
  defp board_result({:ok, _record}, socket), do: {:noreply, refresh(socket)}

  # The budget error carries what the budget was, because "you have no votes
  # left" is only useful next to the number (FR-403, FR-919).
  defp board_result({:error, :vote_budget_exceeded, details}, socket) do
    message =
      gettext("You have spent all %{budget} of your votes.", budget: details.budget)

    {:noreply, put_flash(socket, :error, message)}
  end

  defp board_result({:error, %Ecto.Changeset{} = changeset}, socket) do
    {:noreply, put_flash(socket, :error, changeset_message(changeset))}
  end

  defp board_result({:error, reason}, socket) do
    {:noreply, put_flash(socket, :error, error_message(reason))}
  end

  # The card that was clicked, looked up among the ones this person can
  # actually see — a card hidden by blind mode is not a card they can act on.
  defp fetch_card(socket, id) do
    id = String.to_integer(id)

    case Enum.find(socket.assigns.cards, &(&1.id == id)) do
      nil -> {:error, :not_found}
      card -> {:ok, card}
    end
  end

  defp fetch_group(socket, id) do
    id = String.to_integer(id)

    case Enum.find(socket.assigns.groups, &(&1.id == id)) do
      nil -> {:error, :not_found}
      group -> {:ok, group}
    end
  end

  defp refresh(socket), do: assign_board(socket, socket.assigns.session)

  defp changeset_message(changeset) do
    changeset
    |> SprintLensWeb.FallbackController.changeset_errors()
    |> Enum.map_join("; ", fn {field, messages} -> "#{field} #{Enum.join(messages, ", ")}" end)
  end

  defp to_mood_kind("checkin_mood"), do: :checkin_mood
  defp to_mood_kind("roti"), do: :roti

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
  defp error_message(:session_closed), do: gettext("This session is closed.")
  defp error_message(:already_voted), do: gettext("You have already voted on this topic.")

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

  # No `:created` clause: a session that has not started is the lobby, and the
  # lobby's whole subject is the room rather than the session's state. If one
  # ever reaches the board header there is nothing to render it, which is the
  # loud failure rather than a badge contradicting the screen around it.
  defp state_label(:active), do: gettext("Running")
  defp state_label(:closed), do: gettext("Closed")

  # Only ever asked about a session that has started: before that, the whole
  # screen is the lobby and its state is the one thing it does not have to say.
  defp state_tone(session) do
    if Session.state(session) == :active, do: "primary", else: "neutral"
  end
end
