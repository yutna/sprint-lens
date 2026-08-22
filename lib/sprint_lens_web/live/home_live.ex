defmodule SprintLensWeb.HomeLive do
  @moduledoc """
  SCR-02 Home: what is waiting for this person, in the order it is waiting.

  ## Why it is not a list of things the system stores

  It used to be three sections — teams, sessions, actions — which is the shape
  of the database rather than the shape of a morning. Someone opening the app
  is asking one question, and it is not "what teams am I in". It is "is
  anything happening right now, and what do I owe".

  So the page answers that in order: a room that is open this minute, then the
  work assigned to this person, then what is coming, and only then the teams —
  which are context, not a task. A section with nothing in it stays, with a
  designed empty state rather than a gap (FR-917), because "nothing is
  overdue" is an answer and a blank space is not.

  "My open actions" is the same question the check-in asks (FR-505): what does
  this person still owe, across every team they are in. An item that was
  carried forward appears once, as the newer commitment, rather than twice.

  ## Open, and open right now

  `Retro.list_open_sessions/1` returns everything that is not closed, which is
  two different situations: a session somebody is sitting in, and one that has
  not started. The old page told them apart by asking whether a date was set,
  which is a proxy — a scheduled retrospective that is currently under way
  would have filed itself under "upcoming". The state is the real answer, so
  that is what splits them.
  """

  use SprintLensWeb, :live_view

  import SprintLensWeb.ActionComponents

  alias SprintLens.Actions
  alias SprintLens.Retro
  alias SprintLens.Retro.Session
  alias SprintLens.Teams

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
        {gettext("Hello, %{name}", name: @current_scope.user.display_name)}
        <:subtitle>{home_subtitle(@teams, @live_sessions, @actions)}</:subtitle>
      </.header>

      <.teams_panel :if={@teams == []} teams={@teams} />

      <%!--
        No empty state, on purpose. "No room is open" is the normal state of
        this section for most of the week, and saying so every time would put
        a permanent apology at the top of the page.
      --%>
      <.panel
        :if={@live_sessions != []}
        id="home-live"
        title={gettext("Happening now")}
        class="rounded-panel border border-primary/30 bg-primary/5 p-4 sm:p-6"
      >
        <ul class="space-y-2">
          <li :for={session <- @live_sessions}>
            <.link
              navigate={~p"/sessions/#{session}"}
              id={"home-session-#{session.id}"}
              class="flex flex-wrap items-center gap-x-3 gap-y-1 rounded-card border border-base-200 bg-base-100 p-4 shadow-resting transition-shadow hover:shadow-lifted"
            >
              <span class="min-w-0 grow">
                <span class="block truncate font-semibold">{session.title}</span>
                <span class="block truncate text-label text-base-content/70">
                  {session.team.name}
                </span>
              </span>
              <.badge tone="primary">{gettext("In progress")}</.badge>
              <span aria-hidden="true" class="text-label font-medium text-primary">
                {gettext("Join")} &rarr;
              </span>
            </.link>
          </li>
        </ul>
      </.panel>

      <.panel id="home-actions-panel" title={gettext("Yours to do")}>
        <:subtitle :if={@actions != []}>
          {action_summary(@actions, @now)}
        </:subtitle>

        <ul :if={@actions != []} id="home-actions" class="space-y-2">
          <.action_row :for={action <- @actions} action={action} now={@now}>
            <:controls :let={action}>
              <.link
                :if={action.session}
                navigate={~p"/teams/#{action.team_id}/actions"}
                id={"home-action-team-#{action.id}"}
                class="text-caption text-base-content/60 underline-offset-2 hover:underline"
              >
                {action.session.title}
              </.link>
            </:controls>
          </.action_row>
        </ul>

        <.empty_state
          :if={@actions == []}
          id="home-actions-empty"
          pose="done"
          title={gettext("Nothing assigned to you.")}
        >
          {gettext("Anything the team asks you to take on will show up here.")}
        </.empty_state>
      </.panel>

      <.panel id="home-upcoming" title={gettext("Coming up")}>
        <ul :if={@upcoming_sessions != []} id="home-sessions" class="space-y-2">
          <li :for={session <- @upcoming_sessions}>
            <.link
              navigate={~p"/sessions/#{session}"}
              id={"home-session-#{session.id}"}
              class="flex flex-wrap items-center gap-x-3 gap-y-1 rounded-card border border-base-200 p-3 transition-colors hover:border-base-content/25"
            >
              <span class="min-w-0 grow">
                <span class="block truncate font-medium">{session.title}</span>
                <span class="block truncate text-label text-base-content/70">
                  {session.team.name}
                </span>
              </span>
              <.badge :if={session.scheduled_at}>
                {SprintLensWeb.Locale.format_datetime(session.scheduled_at)}
              </.badge>
              <.badge :if={is_nil(session.scheduled_at)}>{gettext("No date yet")}</.badge>
            </.link>
          </li>
        </ul>

        <.empty_state
          :if={@upcoming_sessions == []}
          id="home-upcoming-empty"
          pose="waiting"
          title={gettext("No sessions scheduled.")}
        >
          {gettext("A retrospective one of your teams plans will appear here.")}
        </.empty_state>
      </.panel>

      <.teams_panel :if={@teams != []} teams={@teams} />
    </Layouts.app>
    """
  end

  # Rendered at the top for someone with no teams and at the bottom for
  # everyone else. A team is context rather than a task, so it belongs under
  # the work — except on the one day when getting into a team *is* the work.
  attr :teams, :list, required: true

  defp teams_panel(assigns) do
    ~H"""
    <.panel id="home-teams-panel" title={gettext("Your teams")}>
      <:actions :if={@teams != []}>
        <.button navigate={~p"/teams"} variant="ghost" size="sm">
          {gettext("New team")}
        </.button>
      </:actions>

      <ul :if={@teams != []} id="home-teams" class="grid gap-3 sm:grid-cols-2">
        <li :for={team <- @teams}>
          <.link
            navigate={~p"/teams/#{team}"}
            id={"home-team-#{team.id}"}
            class="flex h-full flex-wrap items-center gap-2 rounded-card border border-base-200 p-4 transition-colors hover:border-base-content/25"
          >
            <span class="min-w-0 grow">
              <span class="block truncate font-semibold">{team.name}</span>
              <span class="block text-label text-base-content/70">
                {ngettext("%{count} member", "%{count} members", length(team.memberships),
                  count: length(team.memberships)
                )}
              </span>
            </span>
            <.badge :if={team.is_archived}>{gettext("Archived")}</.badge>
          </.link>
        </li>
      </ul>

      <.empty_state
        :if={@teams == []}
        id="home-teams-empty"
        title={gettext("You are not in a team yet.")}
      >
        {gettext("A team is where retrospectives, actions and history live.")}
        <:actions>
          <.button navigate={~p"/teams"} variant="primary">
            {gettext("Create your first team")}
          </.button>
        </:actions>
      </.empty_state>
    </.panel>
    """
  end

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    teams = Teams.list_teams(socket.assigns.current_scope)
    {live_sessions, upcoming} = split_by_state(teams)

    {:ok,
     socket
     |> assign(:page_title, gettext("Home"))
     |> assign(:now, DateTime.utc_now())
     |> assign(:teams, teams)
     |> assign(:live_sessions, live_sessions)
     |> assign(:upcoming_sessions, upcoming)
     |> assign(:actions, Actions.list_my_actions(socket.assigns.current_scope))}
  end

  defp split_by_state(teams) do
    {live, upcoming} =
      teams
      |> Enum.flat_map(&Retro.list_open_sessions/1)
      |> Enum.split_with(&(Session.state(&1) == :active))

    {Enum.sort_by(live, & &1.inserted_at, {:desc, NaiveDateTime}),
     Enum.sort_by(upcoming, &when?/1)}
  end

  # Across teams rather than within one: `list_open_sessions/1` sorts each
  # team's own, and a person in three teams wants the soonest of all of them
  # first, not the soonest of the team that happens to be listed first. A
  # session with no date is not urgent, so it sorts after every one that has
  # one.
  defp when?(%Session{scheduled_at: nil}), do: {1, 0}
  defp when?(%Session{scheduled_at: at}), do: {0, DateTime.to_unix(at)}

  defp home_subtitle([], _live, _actions), do: gettext("Start by creating a team.")

  defp home_subtitle(_teams, [_ | _], _actions), do: gettext("A room is open right now.")

  defp home_subtitle(_teams, _live, []), do: gettext("Nothing needs you at the moment.")

  defp home_subtitle(_teams, _live, actions) do
    ngettext(
      "%{count} thing is waiting for you.",
      "%{count} things are waiting for you.",
      length(actions),
      count: length(actions)
    )
  end

  # Said once at the top rather than left to be counted off the list. Overdue
  # is the number that changes what someone does next (FR-506).
  defp action_summary(actions, now) do
    case Enum.count(actions, &Actions.overdue?(&1, now)) do
      0 ->
        ngettext("%{count} open item", "%{count} open items", length(actions),
          count: length(actions)
        )

      overdue ->
        gettext("%{open} open, %{overdue} past due", open: length(actions), overdue: overdue)
    end
  end
end
