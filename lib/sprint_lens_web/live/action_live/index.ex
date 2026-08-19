defmodule SprintLensWeb.ActionLive.Index do
  @moduledoc """
  SCR-10 Actions — the team's action list, filterable by status, assignee and
  the session it came from (FR-504).

  ## This view shows everything, including what has been superseded

  The check-in review and the Home page ask "what does the team still owe?"
  and leave out an item that something newer was carried from. This one asks
  "what has the team decided?", which is a different question: an item that
  was carried forward is part of the record, and hiding it would make the
  history look like the commitment appeared out of nowhere in the later
  session.
  """

  use SprintLensWeb, :live_view

  import SprintLensWeb.ActionComponents

  alias SprintLens.Actions
  alias SprintLens.Retro
  alias SprintLens.Teams

  @filters ~w(status assignee_id session_id)

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} locale={@locale} theme={@theme}>
      <.header>
        {gettext("Actions")}
        <:subtitle>{@team.name}</:subtitle>
        <:actions>
          <.link navigate={~p"/teams/#{@team}"} class="btn btn-ghost btn-sm">
            {gettext("Back to team")}
          </.link>
        </:actions>
      </.header>

      <.form
        for={@filter_form}
        id="action-filters"
        phx-change="filter"
        class="grid gap-2 sm:grid-cols-3"
      >
        <.input
          field={@filter_form[:status]}
          type="select"
          label={gettext("Status")}
          options={[{gettext("Any status"), ""} | status_options()]}
        />
        <.input
          field={@filter_form[:assignee_id]}
          type="select"
          label={gettext("Owner")}
          options={[{gettext("Anyone"), ""} | member_options(@members)]}
        />
        <.input
          field={@filter_form[:session_id]}
          type="select"
          label={gettext("From session")}
          options={[{gettext("Any session"), ""} | session_options(@sessions)]}
        />
      </.form>

      <section aria-labelledby="action-summary-heading" class="rounded-box border border-base-300 p-3">
        <h2 id="action-summary-heading" class="text-sm font-semibold uppercase opacity-70">
          {gettext("How the team is doing")}
        </h2>

        <dl class="mt-2 grid grid-cols-2 gap-2 sm:grid-cols-4">
          <div>
            <dt class="text-xs opacity-70">{gettext("Still open")}</dt>
            <dd id="stat-open" class="text-lg font-semibold">{@stats.open_count}</dd>
          </div>
          <div>
            <dt class="text-xs opacity-70">{gettext("Completed")}</dt>
            <dd id="stat-completion" class="text-lg font-semibold">
              {gettext("%{rate}%", rate: @stats.completion_rate)}
            </dd>
          </div>
          <div>
            <dt class="text-xs opacity-70">{gettext("Average age")}</dt>
            <dd id="stat-age" class="text-lg font-semibold">
              {ngettext("%{count} day", "%{count} days", trunc(@stats.average_age_days),
                count: @stats.average_age_days
              )}
            </dd>
          </div>
          <div>
            <dt class="text-xs opacity-70">{gettext("Overdue")}</dt>
            <dd id="stat-overdue" class="text-lg font-semibold">{@stats.overdue_count}</dd>
          </div>
        </dl>
      </section>

      <ul :if={@actions != []} id="actions" class="space-y-2">
        <.action_row :for={action <- @actions} action={action} editable={true} now={@now}>
          <:controls :let={action}>
            <span
              :if={action.session}
              id={"action-session-#{action.id}"}
              class="badge badge-ghost badge-sm"
            >
              {action.session.title}
            </span>
          </:controls>
        </.action_row>
      </ul>

      <p
        :if={@actions == []}
        id="actions-empty"
        class="rounded-box border border-base-300 p-6 text-center"
      >
        {gettext("Nothing here. Actions come out of a retrospective's discussion.")}
      </p>
    </Layouts.app>
    """
  end

  @impl Phoenix.LiveView
  def mount(%{"team_id" => team_id}, _session, socket) do
    case Teams.fetch_team(socket.assigns.current_scope, team_id) do
      {:ok, team} ->
        {:ok,
         socket
         |> assign(:page_title, gettext("Actions"))
         |> assign(:team, team)
         |> assign(:members, Enum.map(Teams.list_members(team), & &1.user))
         |> assign(:sessions, Retro.list_sessions(team))
         |> assign(:filters, %{})
         |> load()}

      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, gettext("That resource does not exist."))
         |> push_navigate(to: ~p"/teams")}
    end
  end

  @impl Phoenix.LiveView
  def handle_event("filter", params, socket) do
    filters = Map.new(@filters, &{&1, params[&1] || ""})

    {:noreply, socket |> assign(:filters, filters) |> load()}
  end

  def handle_event("update_action_status", %{"action_id" => id, "status" => status}, socket) do
    with {:ok, item} <- Actions.fetch_action(socket.assigns.current_scope, id),
         {:ok, _updated} <-
           Actions.update_action(socket.assigns.current_scope, item, %{status: status}) do
      {:noreply, load(socket)}
    else
      {:error, %Ecto.Changeset{}} ->
        {:noreply, put_flash(socket, :error, gettext("Some fields need attention."))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("That resource does not exist."))}
    end
  end

  defp load(socket) do
    filters =
      Enum.map(socket.assigns.filters, fn {key, value} -> {String.to_atom(key), value} end)

    socket
    |> assign(:now, DateTime.utc_now())
    |> assign(:actions, Actions.list_actions(socket.assigns.team, filters))
    |> assign(:stats, Actions.stats(socket.assigns.team))
    |> assign(:filter_form, to_form(socket.assigns.filters, as: :filter))
  end

  defp member_options(members), do: Enum.map(members, &{&1.display_name, &1.id})
  defp session_options(sessions), do: Enum.map(sessions, &{&1.title, &1.id})
end
