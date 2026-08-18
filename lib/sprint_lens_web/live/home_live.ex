defmodule SprintLensWeb.HomeLive do
  @moduledoc """
  SCR-02 Home: the teams you belong to, the sessions coming up, and the
  actions still assigned to you.

  Sessions and actions arrive with the milestones that own them; until then
  their sections show the empty state FR-917 asks for rather than being
  absent, so the shape of the page is stable.
  """

  use SprintLensWeb, :live_view

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
        <p id="home-upcoming-empty" class="rounded-box border border-base-300 p-6 text-center">
          {gettext("No sessions scheduled.")}
        </p>
      </section>

      <section aria-labelledby="my-actions-heading">
        <h2 id="my-actions-heading" class="mb-2 text-sm font-semibold uppercase opacity-70">
          {gettext("My open actions")}
        </h2>
        <p id="home-actions-empty" class="rounded-box border border-base-300 p-6 text-center">
          {gettext("Nothing assigned to you.")}
        </p>
      </section>
    </Layouts.app>
    """
  end

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Home"))
     |> assign(:teams, Teams.list_teams(socket.assigns.current_scope))}
  end
end
