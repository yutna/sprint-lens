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
  import SprintLensWeb.BoardComponents, only: [column_grid: 1]
  import SprintLensWeb.AIComponents

  alias SprintLens.AI
  alias SprintLens.Insights
  alias SprintLens.Retro
  alias SprintLensWeb.TemplateText

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
          <span class="flex flex-wrap items-center gap-2">
            <.badge>{gettext("Closed")}</.badge>
            <span :if={@session.closed_at} id="recap-closed-at">
              {SprintLensWeb.Locale.format_datetime(@session.closed_at)}
            </span>
            <.badge :if={@session.is_anonymous}>{gettext("Anonymous")}</.badge>
          </span>
        </:subtitle>
        <:actions>
          <.button navigate={~p"/teams/#{@session.team_id}/sessions"} variant="ghost" size="sm">
            {gettext("Back to retrospectives")}
          </.button>
        </:actions>
      </.header>

      <.panel id="recap-summary" title={gettext("How it went")}>
        <.stats>
          <.stat id="recap-participants" label={gettext("Took part")}>
            {@recap.participant_count}
          </.stat>
          <.stat id="recap-card-count" label={gettext("Cards")}>{length(@recap.cards)}</.stat>
          <.stat id="recap-mood" label={gettext("Mood")}>{score(@recap.mood)}</.stat>
          <.stat id="recap-roti" label={gettext("ROTI")}>{score(@recap.roti)}</.stat>
        </.stats>
      </.panel>

      <%!--
        The accepted summary, if the facilitator kept one (AI-009). Shown
        before the board because it is what somebody opening a recap a month
        later actually wants.
      --%>
      <.panel :if={@session.summary} id="recap-narrative" title={gettext("Summary")}>
        <%!--
          Not a `<pre>`. The line breaks matter, which is what
          `whitespace-pre-wrap` is for, but a paragraph of prose set in a
          monospace face reads as a log file rather than as writing.
        --%>
        <div
          id="recap-summary-text"
          class="rounded-panel border border-base-200 bg-base-100 p-4 break-words whitespace-pre-wrap"
        >
          {@session.summary}
        </div>
      </.panel>

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

      <.panel id="recap-board-panel" title={gettext("The board")}>
        <div id="recap-board" class={["grid gap-3", column_grid(length(@recap.columns))]}>
          <section
            :for={column <- @recap.columns}
            id={"recap-column-#{column.id}"}
            class="space-y-3 rounded-panel border border-base-200 bg-base-100 p-4"
          >
            <h3 class="font-semibold">{TemplateText.column_name(column)}</h3>

            <ul class="space-y-2">
              <li
                :for={card <- cards_in(@recap.cards, column)}
                id={"recap-card-#{card.id}"}
                class="rounded-card border border-base-200 p-3"
              >
                <p class="break-words whitespace-pre-wrap">{card.text}</p>
                <p
                  :if={not @session.is_anonymous and card.author}
                  class="mt-1 text-caption text-base-content/60"
                >
                  {card.author.display_name}
                </p>
              </li>
            </ul>

            <p
              :if={cards_in(@recap.cards, column) == []}
              class="text-label text-base-content/60"
            >
              {gettext("Nothing here.")}
            </p>
          </section>
        </div>
      </.panel>

      <.panel id="recap-discussion" title={gettext("What the room discussed")}>
        <ol id="recap-topics" class="space-y-2">
          <li
            :for={topic <- @recap.topics}
            id={"recap-topic-#{topic.kind}-#{topic.id}"}
            class="space-y-2 rounded-card border border-base-200 bg-base-100 p-3"
          >
            <div class="flex flex-wrap items-start gap-2">
              <p class="grow font-medium break-words">{topic.title}</p>
              <%!--
                Quiet at zero. A pink pill announcing that nobody voted for
                something is the loudest thing on a row about the thing the
                room decided not to spend time on.
              --%>
              <span class={[
                "shrink-0 rounded-control px-2 py-0.5 text-caption font-medium",
                if((topic.votes || 0) > 0,
                  do: "bg-primary text-primary-content",
                  else: "border border-base-300 text-base-content/60"
                )
              ]}>
                {ngettext("%{count} vote", "%{count} votes", topic.votes || 0,
                  count: topic.votes || 0
                )}
              </span>
            </div>

            <ul :if={topic.kind == :group} class="space-y-1 pl-3">
              <li :for={card <- topic.cards} class="text-label text-base-content/70">
                {card.text}
              </li>
            </ul>

            <%!--
              The note is what the room concluded, so it is set apart from the
              topic it is about rather than run on from it.
            --%>
            <p :if={topic.note} class="rounded-card bg-base-200 p-3 text-label">{topic.note}</p>
          </li>
        </ol>

        <.empty_state
          :if={@recap.topics == []}
          id="recap-topics-empty"
          title={gettext("Nothing was brought up for discussion.")}
        >
          {gettext("Topics come from the cards the room voted on.")}
        </.empty_state>
      </.panel>

      <.panel id="recap-agreed" title={gettext("What the team agreed")}>
        <ul :if={@recap.actions != []} id="recap-actions" class="space-y-2">
          <.action_row :for={action <- @recap.actions} action={action} now={@now} />
        </ul>

        <.empty_state
          :if={@recap.actions == []}
          id="recap-actions-empty"
          pose="done"
          title={gettext("Nothing agreed yet.")}
        >
          {gettext("Actions written during a retrospective appear here.")}
        </.empty_state>
      </.panel>

      <%!--
        Plain links rather than LiveView navigation: these are downloads, and
        a socket cannot hand the browser a file (FR-701 to FR-703). They were
        four bare anchors carrying `variant` and `size` attributes that mean
        nothing to an `<a>` — invalid markup and no styling, which is what
        happens when a button's attributes are copied onto something that is
        not one.
      --%>
      <.panel id="recap-export" title={gettext("Take it with you")}>
        <:subtitle>{gettext("The same recap, in a file.")}</:subtitle>

        <div class="flex flex-wrap gap-2">
          <.button href={~p"/sessions/#{@session}/export?format=markdown"} id="export-markdown">
            {gettext("Markdown")}
          </.button>
          <.button
            href={~p"/sessions/#{@session}/export?format=csv&of=cards"}
            id="export-csv-cards"
          >
            {gettext("Cards CSV")}
          </.button>
          <.button
            href={~p"/sessions/#{@session}/export?format=csv&of=actions"}
            id="export-csv-actions"
          >
            {gettext("Actions CSV")}
          </.button>
          <.button href={~p"/sessions/#{@session}/export?format=json"} id="export-json">
            {gettext("JSON")}
          </.button>
        </div>
      </.panel>
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
