defmodule SprintLensWeb.SessionLive.Index do
  @moduledoc """
  SCR-05 Session list and SCR-06 Create session (FR-201, FR-203).

  One screen rather than two: the list is short and the form is short, and a
  team member arriving to start a retro should not have to navigate twice to
  do the only thing this page is for.
  """

  use SprintLensWeb, :live_view

  alias SprintLens.Insights
  alias SprintLens.Retro
  alias SprintLens.Retro.Session
  alias SprintLens.Teams
  alias SprintLensWeb.Locale
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
      team={@team}
      breadcrumbs={[
        {gettext("Teams"), ~p"/teams"},
        {@team.name, ~p"/teams/#{@team}"},
        {gettext("Retrospectives"), ~p"/teams/#{@team}/sessions"}
      ]}
    >
      <.header>
        {gettext("Retrospectives")}
        <:subtitle>{gettext("Everything this team has run, and what is next.")}</:subtitle>
      </.header>

      <.panel id="sessions-open" title={gettext("Open")}>
        <:subtitle>{gettext("A room you can walk into, or one waiting to start.")}</:subtitle>

        <ul :if={@sessions != []} id="sessions" class="grid gap-3">
          <li :for={session <- @sessions} id={"session-#{session.id}"}>
            <.link
              navigate={~p"/sessions/#{session}"}
              class="flex flex-wrap items-center gap-x-3 gap-y-1 rounded-card border border-base-200 p-4 transition-colors hover:border-base-content/25"
            >
              <span class="min-w-0 grow">
                <span class="block truncate font-semibold">{session.title}</span>
                <span class="block text-label text-base-content/70">
                  <span :if={session.scheduled_at}>
                    {gettext("Scheduled for %{at}",
                      at: Locale.format_datetime(session.scheduled_at)
                    )}
                  </span>
                  <span :if={is_nil(session.scheduled_at)}>
                    {gettext("Created %{at}", at: Locale.format_datetime(session.inserted_at))}
                  </span>
                </span>
              </span>
              <.badge :if={session.is_anonymous}>{gettext("Anonymous")}</.badge>
              <.badge tone={state_tone(session)}>{state_label(Session.state(session))}</.badge>
            </.link>
          </li>
        </ul>

        <.empty_state
          :if={@sessions == []}
          id="sessions-empty"
          pose="waiting"
          title={gettext("No retrospectives yet.")}
        >
          {gettext("Start one below. It takes a title and nothing else.")}
        </.empty_state>
      </.panel>

      <%!--
        The archive (FR-601): every retrospective that has finished, with what
        it came to. Separate from the list above because a closed session is
        read rather than joined.
      --%>
      <.panel id="sessions-archive" title={gettext("Archive")}>
        <:subtitle>{gettext("Finished, and read-only from here on.")}</:subtitle>

        <ul :if={@archive != []} id="archive" class="grid gap-3">
          <li :for={entry <- @archive} id={"archive-#{entry.session.id}"}>
            <.link
              navigate={~p"/sessions/#{entry.session}/recap"}
              class="block rounded-card border border-base-200 p-4 transition-colors hover:border-base-content/25"
            >
              <span class="flex flex-wrap items-center gap-2">
                <span class="min-w-0 grow truncate font-semibold">{entry.session.title}</span>
                <.badge :if={entry.template}>
                  {TemplateText.translate_if_builtin(entry.template, entry.template_builtin?)}
                </.badge>
                <.badge :if={entry.session.is_anonymous}>{gettext("Anonymous")}</.badge>
              </span>

              <span class="mt-1 flex flex-wrap gap-x-4 gap-y-1 text-label text-base-content/70">
                <span :if={entry.closed_at}>
                  {gettext("Closed %{at}", at: Locale.format_datetime(entry.closed_at))}
                </span>
                <span id={"archive-participants-#{entry.session.id}"}>
                  {ngettext("%{count} person", "%{count} people", entry.participant_count,
                    count: entry.participant_count
                  )}
                </span>
                <span id={"archive-cards-#{entry.session.id}"}>
                  {ngettext("%{count} card", "%{count} cards", entry.card_count,
                    count: entry.card_count
                  )}
                </span>
                <span id={"archive-mood-#{entry.session.id}"}>
                  {gettext("mood %{score}", score: entry.mood || "—")}
                </span>
              </span>
            </.link>
          </li>
        </ul>

        <.empty_state
          :if={@archive == []}
          id="archive-empty"
          title={gettext("No retrospective has finished yet.")}
        >
          {gettext("A session moves here when the facilitator closes it.")}
        </.empty_state>
      </.panel>

      <%!--
        Below the lists rather than above them: most visits are to walk into a
        room that already exists. It stays on the page rather than behind a
        disclosure because it is the whole reason the screen has a form.
      --%>
      <.panel
        :if={not @team.is_archived}
        id="session-new"
        title={gettext("Start a retrospective")}
        class="max-w-xl"
      >
        <.form
          for={@form}
          id="session_form"
          phx-change="validate"
          phx-submit="save"
          class="rounded-panel border border-base-200 bg-base-100 p-4 shadow-resting sm:p-6"
        >
          <.input field={@form[:title]} type="text" label={gettext("Title")} required />
          <.input
            field={@form[:template_id]}
            type="select"
            label={gettext("Template")}
            options={template_options(@templates)}
          />
          <.input
            field={@form[:scheduled_at]}
            type="datetime-local"
            label={gettext("Scheduled for (optional)")}
          />
          <.input
            field={@form[:vote_budget]}
            type="number"
            label={gettext("Vote budget")}
            min="1"
            max="20"
          />
          <.input
            field={@form[:multi_vote]}
            type="checkbox"
            label={gettext("Allow more than one vote on the same card")}
          />
          <.input
            field={@form[:is_blind]}
            type="checkbox"
            label={gettext("Hide cards until the facilitator reveals them")}
          />
          <.input
            field={@form[:is_anonymous]}
            type="checkbox"
            label={gettext("Anonymous — authorship is hidden from everyone, permanently")}
          />

          <.button variant="primary" phx-disable-with={gettext("Creating...")}>
            {gettext("Create session")}
          </.button>
        </.form>
      </.panel>
    </Layouts.app>
    """
  end

  @impl Phoenix.LiveView
  def mount(%{"team_id" => team_id}, _session, socket) do
    case Teams.fetch_team(socket.assigns.current_scope, team_id) do
      {:ok, team} ->
        {:ok,
         socket
         |> assign(:page_title, gettext("Retrospectives"))
         |> assign(:team, team)
         |> assign(:templates, Teams.list_templates(team))
         |> assign_sessions()
         |> assign_form(Retro.change_session())}

      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, gettext("That resource does not exist."))
         |> push_navigate(to: ~p"/teams")}
    end
  end

  @impl Phoenix.LiveView
  def handle_event("validate", %{"session" => params}, socket) do
    changeset = Retro.change_session(%Session{}, params) |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"session" => params}, socket) do
    case Retro.create_session(socket.assigns.current_scope, socket.assigns.team, params) do
      {:ok, session} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Session created."))
         |> push_navigate(to: ~p"/sessions/#{session}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, Map.put(changeset, :action, :insert))}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, error_message(reason))}
    end
  end

  defp error_message(:not_found), do: gettext("That resource does not exist.")
  defp error_message(:unauthorized), do: gettext("You do not have permission to do that.")

  # The two lists are disjoint on purpose. `list_sessions/1` returns every
  # session including the finished ones, and rendering that whole list above
  # the archive put each closed retrospective on the screen twice — once under
  # a heading that called it open, and once with the numbers it ended on.
  defp assign_sessions(socket) do
    sessions = Retro.list_sessions(socket.assigns.team)

    socket
    |> assign(:sessions, Enum.reject(sessions, &(Session.state(&1) == :closed)))
    |> assign(:archive, Insights.archive(socket.assigns.team))
  end

  defp assign_form(socket, changeset) do
    assign(socket, :form, to_form(changeset, as: "session"))
  end

  # The label a person picks by, which for a built-in is the product's own
  # wording and therefore translated (FR-906). A team's template keeps the
  # name the team typed (FR-909).
  defp template_options(templates) do
    Enum.map(templates, &{TemplateText.template_name(&1), &1.id})
  end

  # Two states, not three: a closed session is in the archive below, which
  # says when it closed and what it came to. If one ever reaches this list
  # again there is no clause for it, and a crash is the right answer — the
  # badge would otherwise quietly disagree with the heading above it.
  defp state_label(:created), do: gettext("Not started")
  defp state_label(:active), do: gettext("Running")

  defp state_tone(session) do
    if Session.state(session) == :active, do: "primary", else: "neutral"
  end
end
