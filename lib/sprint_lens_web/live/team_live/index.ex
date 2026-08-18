defmodule SprintLensWeb.TeamLive.Index do
  @moduledoc """
  SCR-03 Team list: the teams you belong to, and a form to create another
  (FR-101, FR-103).
  """

  use SprintLensWeb, :live_view

  alias SprintLens.Teams

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} locale={@locale} theme={@theme}>
      <.header>
        {gettext("Teams")}
        <:subtitle>{gettext("Anyone can start a team and lead it.")}</:subtitle>
      </.header>

      <.form for={@form} id="team_form" phx-change="validate" phx-submit="save" class="max-w-md">
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

      <div :if={@teams == []} id="teams-empty" class="rounded-box border border-base-300 p-6">
        <p>{gettext("You are not in a team yet. Create one above to get started.")}</p>
      </div>

      <ul :if={@teams != []} id="teams" class="grid gap-3 sm:grid-cols-2">
        <li :for={team <- @teams}>
          <.link
            navigate={~p"/teams/#{team}"}
            id={"team-#{team.id}"}
            class="block rounded-box border border-base-300 p-4 hover:border-primary"
          >
            <div class="flex items-center gap-2">
              <span class="font-semibold">{team.name}</span>
              <span :if={team.is_archived} class="badge badge-ghost badge-sm">
                {gettext("Archived")}
              </span>
            </div>
            <p :if={team.description} class="text-sm opacity-70">{team.description}</p>
            <p class="text-sm opacity-70">
              {ngettext("%{count} member", "%{count} members", length(team.memberships),
                count: length(team.memberships)
              )}
            </p>
          </.link>
        </li>
      </ul>
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
