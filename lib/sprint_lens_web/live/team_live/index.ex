defmodule SprintLensWeb.TeamLive.Index do
  @moduledoc """
  SCR-03 Team list: the teams you belong to, and a form to create another
  (FR-101, FR-103).

  The list comes before the form now. Both were on the page before, in the
  other order, which put the rare thing — starting a team, which most people
  do once — above the thing they came for. The form stays visible rather than
  hiding behind a disclosure: it is two fields, and a person who has no teams
  yet needs it to be the obvious next move.
  """

  use SprintLensWeb, :live_view

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
        {gettext("Teams")}
        <:subtitle>{gettext("Anyone can start a team and lead it.")}</:subtitle>
      </.header>

      <.panel id="team-list" title={gettext("Your teams")}>
        <ul :if={@teams != []} id="teams" class="grid gap-3 sm:grid-cols-2">
          <li :for={team <- @teams}>
            <.link
              navigate={~p"/teams/#{team}"}
              id={"team-#{team.id}"}
              class="flex h-full flex-col gap-1 rounded-card border border-base-200 p-4 transition-colors hover:border-base-content/25"
            >
              <span class="flex flex-wrap items-center gap-2">
                <span class="min-w-0 truncate font-semibold">{team.name}</span>
                <.badge :if={team.is_archived}>{gettext("Archived")}</.badge>
              </span>
              <span :if={team.description} class="text-label text-base-content/70">
                {team.description}
              </span>
              <span class="mt-auto text-label text-base-content/60">
                {ngettext("%{count} member", "%{count} members", length(team.memberships),
                  count: length(team.memberships)
                )}
              </span>
            </.link>
          </li>
        </ul>

        <.empty_state
          :if={@teams == []}
          id="teams-empty"
          title={gettext("You are not in a team yet.")}
        >
          {gettext("Start one below, or ask a teammate to add you to theirs.")}
        </.empty_state>
      </.panel>

      <.panel id="team-new" title={gettext("Start a team")} class="max-w-md">
        <:subtitle>{gettext("You will be its lead.")}</:subtitle>

        <.form
          for={@form}
          id="team_form"
          phx-change="validate"
          phx-submit="save"
          class="rounded-panel border border-base-200 bg-base-100 p-4 shadow-resting sm:p-6"
        >
          <.input field={@form[:name]} type="text" label={gettext("Team name")} required />
          <.input
            field={@form[:description]}
            type="textarea"
            label={gettext("Description")}
            rows="2"
          />
          <.button variant="primary" phx-disable-with={gettext("Creating...")}>
            {gettext("Create team")}
          </.button>
        </.form>
      </.panel>
    </Layouts.app>
    """
  end

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Teams"))
     |> assign_teams()
     |> assign_form(Teams.change_team())}
  end

  @impl Phoenix.LiveView
  def handle_event("validate", %{"team" => params}, socket) do
    changeset = Teams.change_team(%SprintLens.Teams.Team{}, params)

    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  def handle_event("save", %{"team" => params}, socket) do
    case Teams.create_team(socket.assigns.current_scope, params) do
      {:ok, team} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Team created. You lead it."))
         |> push_navigate(to: ~p"/teams/#{team}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, Map.put(changeset, :action, :insert))}
    end

    # No `:unauthorized` clause on purpose. This route requires a session, and
    # section 3.1 grants `create_team` to every active user — the case is
    # pinned by the policy test asserting that a user with no team role may
    # still create one. If that ever changes, this should crash loudly rather
    # than quietly flash a message nobody reads.
  end

  defp assign_teams(socket) do
    assign(socket, :teams, Teams.list_teams(socket.assigns.current_scope))
  end

  defp assign_form(socket, changeset), do: assign(socket, :form, to_form(changeset, as: "team"))
end
