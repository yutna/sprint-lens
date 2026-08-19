defmodule SprintLensWeb.HomeLive do
  @moduledoc """
  SCR-02 Home: the teams you belong to, the sessions coming up, and the
  actions still assigned to you.

  "My open actions" is the same question the check-in asks (FR-505): what does
  this person still owe, across every team they are in. An item that was
  carried forward appears once, as the newer commitment, rather than twice.
  """

  use SprintLensWeb, :live_view

  import SprintLensWeb.ActionComponents

  alias SprintLens.Actions
  alias SprintLens.Retro
  alias SprintLens.Teams

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} locale={@locale} theme={@theme}>
      <.header>
        {gettext("Hello, %{name}", name: @current_scope.user.display_name)}
        <:subtitle>{gettext("Your teams and what is waiting for you.")}</:subtitle>
        <:actions>
          <.link navigate={~p"/teams"} class="btn btn-primary btn-sm">
            {gettext("All teams")}
          </.link>
        </:actions>
      </.header>

      <section aria-labelledby="my-teams-heading">
        <h2 id="my-teams-heading" class="mb-2 text-sm font-semibold uppercase opacity-70">
          {gettext("My teams")}
        </h2>

        <div :if={@teams == []} class="rounded-box border border-base-300 p-6 text-center">
          <p class="mb-3">{gettext("You are not in a team yet.")}</p>
          <.link navigate={~p"/teams"} class="btn btn-primary btn-sm">
            {gettext("Create your first team")}
          </.link>
        </div>

        <ul :if={@teams != []} id="home-teams" class="grid gap-3 sm:grid-cols-2">
          <li :for={team <- @teams}>
            <.link
              navigate={~p"/teams/#{team}"}
              id={"home-team-#{team.id}"}
              class="block rounded-box border border-base-300 p-4 hover:border-primary"
            >
              <span class="font-semibold">{team.name}</span>
              <span :if={team.is_archived} class="badge badge-ghost badge-sm ml-2">
                {gettext("Archived")}
              </span>
              <p class="text-sm opacity-70">
                {ngettext("%{count} member", "%{count} members", length(team.memberships),
                  count: length(team.memberships)
                )}
              </p>
            </.link>
          </li>
        </ul>
      </section>

      <section aria-labelledby="upcoming-heading">
        <h2 id="upcoming-heading" class="mb-2 text-sm font-semibold uppercase opacity-70">
          {gettext("Upcoming sessions")}
        </h2>
        <ul :if={@sessions != []} id="home-sessions" class="space-y-2">
          <li :for={session <- @sessions}>
            <.link
              navigate={~p"/sessions/#{session}"}
              id={"home-session-#{session.id}"}
              class="flex flex-wrap items-center gap-2 rounded-box border border-base-300 p-3 hover:border-primary"
            >
              <span class="grow font-medium">{session.title}</span>
              <span class="text-sm opacity-70">{session.team.name}</span>
              <span :if={session.scheduled_at} class="badge badge-ghost badge-sm">
                {SprintLensWeb.Locale.format_datetime(session.scheduled_at)}
              </span>
              <span :if={is_nil(session.scheduled_at)} class="badge badge-primary badge-sm">
                {gettext("Running now")}
              </span>
            </.link>
          </li>
        </ul>

        <p
          :if={@sessions == []}
          id="home-upcoming-empty"
          class="rounded-box border border-base-300 p-6 text-center"
        >
          {gettext("No sessions scheduled.")}
        </p>
      </section>

      <section aria-labelledby="my-actions-heading">
        <h2 id="my-actions-heading" class="mb-2 text-sm font-semibold uppercase opacity-70">
          {gettext("My open actions")}
        </h2>
        <ul :if={@actions != []} id="home-actions" class="space-y-2">
          <.action_row :for={action <- @actions} action={action} now={@now}>
            <:controls :let={action}>
              <.link
                :if={action.session}
                navigate={~p"/teams/#{action.team_id}/actions"}
                id={"home-action-team-#{action.id}"}
                class="badge badge-ghost badge-sm"
              >
                {action.session.title}
              </.link>
            </:controls>
          </.action_row>
        </ul>

        <p
          :if={@actions == []}
          id="home-actions-empty"
          class="rounded-box border border-base-300 p-6 text-center"
        >
          {gettext("Nothing assigned to you.")}
        </p>
      </section>
    </Layouts.app>
    """
  end

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    teams = Teams.list_teams(socket.assigns.current_scope)

    {:ok,
     socket
     |> assign(:page_title, gettext("Home"))
     |> assign(:now, DateTime.utc_now())
     |> assign(:teams, teams)
     |> assign(:sessions, Enum.flat_map(teams, &Retro.list_open_sessions/1))
     |> assign(:actions, Actions.list_my_actions(socket.assigns.current_scope))}
  end
end
