defmodule SprintLensWeb.SessionLive.Recap do
  @moduledoc """
  SCR-08 Recap — what a closed session came to (FR-602, FR-215).

  ## Read-only means read-only

  There is no event handler in this module. A recap is the record of a
  conversation that has finished, and a page that could change it would make
  the archive a place where history gets edited. Action items are the one
  thing that keeps moving after a session closes (FR-503), and they move on
  the team's list, not here.
  """

  use SprintLensWeb, :live_view

  import SprintLensWeb.ActionComponents
  import SprintLensWeb.AIComponents

  alias SprintLens.AI
  alias SprintLens.Insights
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
      <.header>
        {@session.title}
        <:subtitle>
          <span class="badge badge-ghost badge-sm">{gettext("Closed")}</span>
          <span :if={@session.closed_at} id="recap-closed-at">
            {SprintLensWeb.Locale.format_datetime(@session.closed_at)}
          </span>
          <span :if={@session.is_anonymous} class="badge badge-ghost badge-sm">
            {gettext("Anonymous")}
          </span>
        </:subtitle>
        <:actions>
          <%!--
            Plain links rather than LiveView navigation: these are downloads,
            and a socket cannot hand the browser a file (FR-701 to FR-703).
          --%>
          <a
            href={~p"/sessions/#{@session}/export?format=markdown"}
            id="export-markdown"
            class="btn btn-ghost btn-sm"
          >
            {gettext("Markdown")}
          </a>
          <a
            href={~p"/sessions/#{@session}/export?format=csv&of=cards"}
            id="export-csv-cards"
            class="btn btn-ghost btn-sm"
          >
            {gettext("Cards CSV")}
          </a>
          <a
            href={~p"/sessions/#{@session}/export?format=csv&of=actions"}
            id="export-csv-actions"
            class="btn btn-ghost btn-sm"
          >
            {gettext("Actions CSV")}
          </a>
          <a
            href={~p"/sessions/#{@session}/export?format=json"}
            id="export-json"
            class="btn btn-ghost btn-sm"
          >
            {gettext("JSON")}
          </a>
          <.link navigate={~p"/teams/#{@session.team_id}/sessions"} class="btn btn-ghost btn-sm">
            {gettext("Back to retrospectives")}
          </.link>
        </:actions>
      </.header>

      <section
        id="recap-summary"
        aria-labelledby="recap-summary-heading"
        class="rounded-box border border-base-300 p-3"
      >
        <h2 id="recap-summary-heading" class="text-sm font-semibold uppercase opacity-70">
          {gettext("How it went")}
        </h2>

        <dl class="mt-2 grid grid-cols-2 gap-2 sm:grid-cols-4">
          <div>
            <dt class="text-xs opacity-70">{gettext("Took part")}</dt>
            <dd id="recap-participants" class="text-lg font-semibold">{@recap.participant_count}</dd>
          </div>
          <div>
            <dt class="text-xs opacity-70">{gettext("Cards")}</dt>
            <dd id="recap-card-count" class="text-lg font-semibold">{length(@recap.cards)}</dd>
          </div>
          <div>
            <dt class="text-xs opacity-70">{gettext("Mood")}</dt>
            <dd id="recap-mood" class="text-lg font-semibold">{score(@recap.mood)}</dd>
          </div>
          <div>
            <dt class="text-xs opacity-70">{gettext("ROTI")}</dt>
            <dd id="recap-roti" class="text-lg font-semibold">{score(@recap.roti)}</dd>
          </div>
        </dl>
      </section>

      <%!--
        The accepted summary, if the facilitator kept one (AI-009). Shown
        before the board because it is what somebody opening a recap a month
        later actually wants.
      --%>
      <section :if={@session.summary} aria-labelledby="recap-narrative-heading">
        <h2 id="recap-narrative-heading" class="mb-2 text-sm font-semibold uppercase opacity-70">
          {gettext("Summary")}
        </h2>

        <pre
          id="recap-summary-text"
          class="whitespace-pre-wrap break-words rounded-box border border-base-300 p-3 text-sm"
        >{@session.summary}</pre>
      </section>

      <%!--
        Absent, not disabled, when the team has not opted in or the switch is
        off — AI-001's visible half.
      --%>
      <.suggestion_slot
        :if={@ai_available and @is_facilitator}
        id="ai-summary"
        type={:session_summary}
        title={gettext("Suggested summary")}
        hint={gettext("A draft for you to read. Nothing is attached until you accept it.")}
        suggestion={@summary_suggestion}
        editing={@editing_suggestion}
      />

      <section aria-labelledby="recap-board-heading">
        <h2 id="recap-board-heading" class="mb-2 text-sm font-semibold uppercase opacity-70">
          {gettext("The board")}
        </h2>

        <div id="recap-board" class="grid gap-3 sm:grid-cols-2">
          <section
            :for={column <- @recap.columns}
            id={"recap-column-#{column.id}"}
            class="rounded-box border border-base-300 p-3"
          >
            <h3 class="font-semibold">{column.name}</h3>

            <ul class="mt-2 space-y-1">
              <li
                :for={card <- cards_in(@recap.cards, column)}
                id={"recap-card-#{card.id}"}
                class="rounded-box border border-base-200 p-2 text-sm"
              >
                <p class="whitespace-pre-wrap break-words">{card.text}</p>
                <p :if={not @session.is_anonymous and card.author} class="text-xs opacity-60">
                  {card.author.display_name}
                </p>
              </li>
            </ul>

            <p :if={cards_in(@recap.cards, column) == []} class="mt-2 text-sm opacity-60">
              {gettext("Nothing here yet.")}
            </p>
          </section>
        </div>
      </section>

      <section aria-labelledby="recap-topics-heading">
        <h2 id="recap-topics-heading" class="mb-2 text-sm font-semibold uppercase opacity-70">
          {gettext("What the room discussed")}
        </h2>

        <ol id="recap-topics" class="space-y-2">
          <li
            :for={topic <- @recap.topics}
            id={"recap-topic-#{topic.kind}-#{topic.id}"}
            class="rounded-box border border-base-200 p-2"
          >
            <div class="flex flex-wrap items-start gap-2">
              <p class="grow break-words font-medium">{topic.title}</p>
              <span class="badge badge-primary badge-sm">
                {ngettext("%{count} vote", "%{count} votes", topic.votes || 0,
                  count: topic.votes || 0
                )}
              </span>
            </div>

            <ul :if={topic.kind == :group} class="mt-1 space-y-1 pl-3">
              <li :for={card <- topic.cards} class="text-sm opacity-70">{card.text}</li>
            </ul>

            <p :if={topic.note} class="mt-2 rounded-box bg-base-200 p-2 text-sm">{topic.note}</p>
          </li>
        </ol>

        <p :if={@recap.topics == []} id="recap-topics-empty" class="text-sm opacity-60">
          {gettext("There is nothing on the board to discuss yet.")}
        </p>
      </section>

      <section aria-labelledby="recap-actions-heading">
        <h2 id="recap-actions-heading" class="mb-2 text-sm font-semibold uppercase opacity-70">
          {gettext("What the team agreed")}
        </h2>

        <ul :if={@recap.actions != []} id="recap-actions" class="space-y-2">
          <.action_row :for={action <- @recap.actions} action={action} now={@now} />
        </ul>

        <p :if={@recap.actions == []} id="recap-actions-empty" class="text-sm opacity-60">
          {gettext("Nothing agreed yet.")}
        </p>
      </section>
    </Layouts.app>
    """
  end

  @impl Phoenix.LiveView
  def mount(%{"id" => id}, _session, socket) do
    case Insights.fetch_closed_session(socket.assigns.current_scope, id) do
      {:ok, session} ->
        if connected?(socket), do: AI.subscribe(session.team_id)

        {:ok,
         socket
         |> assign(:page_title, session.title)
         |> assign(:editing_suggestion, false)
         |> load(session)}

      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, gettext("That resource does not exist."))
         |> push_navigate(to: ~p"/home")}
    end
  end

  @impl Phoenix.LiveView
  def handle_info({:ai_suggestion, _payload}, socket) do
    {:noreply, reload(socket)}
  end

  @impl Phoenix.LiveView
  def handle_event("request_suggestion", %{"type" => type}, socket) do
    session = socket.assigns.session

    case AI.request(socket.assigns.current_scope, session.team, String.to_existing_atom(type), %{
           session: session
         }) do
      {:ok, _suggestion} -> {:noreply, reload(socket)}
      {:error, reason} -> {:noreply, report(socket, reason)}
    end
  end

  def handle_event("retry_suggestion", %{"id" => id}, socket) do
    with {:ok, suggestion} <- AI.fetch_suggestion(socket.assigns.current_scope, id),
         {:ok, _retried} <- AI.retry(socket.assigns.current_scope, suggestion) do
      {:noreply, reload(socket)}
    else
      {:error, reason} -> {:noreply, report(socket, reason)}
    end
  end

  def handle_event("edit_suggestion", _params, socket) do
    {:noreply, assign(socket, :editing_suggestion, true)}
  end

  def handle_event("cancel_edit_suggestion", _params, socket) do
    {:noreply, assign(socket, :editing_suggestion, false)}
  end

  def handle_event(
        "accept_suggestion",
        %{"suggestion" => %{"id" => id, "output" => output}},
        socket
      ) do
    decide(socket, id, &AI.accept(socket.assigns.current_scope, &1, output))
  end

  def handle_event("accept_suggestion", %{"id" => id}, socket) do
    decide(socket, id, &AI.accept(socket.assigns.current_scope, &1))
  end

  def handle_event("reject_suggestion", %{"id" => id}, socket) do
    decide(socket, id, &AI.reject(socket.assigns.current_scope, &1))
  end

  defp decide(socket, id, fun) do
    with {:ok, suggestion} <- AI.fetch_suggestion(socket.assigns.current_scope, id),
         {:ok, _decided} <- fun.(suggestion) do
      {:noreply, socket |> assign(:editing_suggestion, false) |> reload()}
    else
      {:error, reason} -> {:noreply, report(socket, reason)}
    end
  end

  defp reload(socket) do
    case Insights.fetch_closed_session(socket.assigns.current_scope, socket.assigns.session.id) do
      {:ok, session} -> load(socket, session)
      {:error, :not_found} -> socket
    end
  end

  defp load(socket, session) do
    scope = socket.assigns.current_scope

    socket
    |> assign(:session, session)
    |> assign(:now, DateTime.utc_now())
    |> assign(:recap, Insights.recap(session, scope))
    |> assign(:is_facilitator, Retro.facilitator?(scope, session))
    |> assign(:ai_available, AI.can_request?(scope, session.team))
    |> assign(:summary_suggestion, latest_summary(session))
  end

  defp latest_summary(session) do
    session |> AI.list_session_suggestions(:session_summary) |> List.first()
  end

  defp report(socket, :ai_disabled) do
    put_flash(socket, :error, gettext("AI features are turned off."))
  end

  defp report(socket, _reason) do
    put_flash(socket, :error, gettext("That resource does not exist."))
  end

  defp cards_in(cards, column), do: Enum.filter(cards, &(&1.column_id == column.id))

  defp score(%{count: 0}), do: "—"
  defp score(%{average: average}), do: average
end
