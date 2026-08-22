defmodule SprintLensWeb.InsightsLive.Index do
  @moduledoc """
  SCR-09 Insights — how a team's retrospectives are going over time (FR-604),
  and the org-wide roll-up for an Org Admin (FR-605).

  ## Why the trends are drawn as bars and not a chart library

  A sparkline of five numbers does not need a charting dependency, and one
  would have to be inlined to satisfy the artifact CSP anyway. The bars are
  `div`s with a width, each carrying its number in text — which also means a
  screen reader gets the series rather than an image with no alternative
  (FR-913).
  """

  use SprintLensWeb, :live_view

  alias SprintLens.Insights
  alias SprintLens.Policy
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
        {gettext("Insights")}
        <:subtitle>{@team.name}</:subtitle>
        <:actions>
          <.button navigate={~p"/teams/#{@team}"} variant="ghost" size="sm">
            {gettext("Back to team")}
          </.button>
        </:actions>
      </.header>

      <p
        :if={@metrics.session_count == 0}
        id="insights-empty"
        class="rounded-box border border-base-300 p-6 text-center"
      >
        {gettext("Numbers appear once the team has finished a retrospective.")}
      </p>

      <div :if={@metrics.session_count > 0} class="space-y-6">
        <.trend
          id="mood-trend"
          title={gettext("Mood at check-in")}
          points={@metrics.mood_trend}
          max={5}
          unit=""
        />
        <.trend
          id="roti-trend"
          title={gettext("Return on time invested")}
          points={@metrics.roti_trend}
          max={5}
          unit=""
        />
        <.trend
          id="cards-trend"
          title={gettext("Cards per session")}
          points={@metrics.cards_per_session}
          max={max_of(@metrics.cards_per_session)}
          unit=""
        />
        <.trend
          id="participation-trend"
          title={gettext("Participation")}
          points={@metrics.participation}
          max={100}
          unit="%"
        />

        <section
          id="action-health"
          aria-labelledby="action-health-heading"
          class="rounded-box border border-base-300 p-3"
        >
          <h2 id="action-health-heading" class="text-sm font-semibold uppercase opacity-70">
            {gettext("Actions")}
          </h2>

          <dl class="mt-2 grid grid-cols-2 gap-2 sm:grid-cols-4">
            <div>
              <dt class="text-xs opacity-70">{gettext("Completed")}</dt>
              <dd id="insight-completion" class="text-lg font-semibold">
                {gettext("%{rate}%", rate: @metrics.actions.completion_rate)}
              </dd>
            </div>
            <div>
              <dt class="text-xs opacity-70">{gettext("Still open")}</dt>
              <dd id="insight-open" class="text-lg font-semibold">{@metrics.actions.open_count}</dd>
            </div>
            <div>
              <dt class="text-xs opacity-70">{gettext("Average age")}</dt>
              <dd id="insight-age" class="text-lg font-semibold">
                {@metrics.actions.average_age_days}
              </dd>
            </div>
            <div>
              <dt class="text-xs opacity-70">{gettext("Overdue")}</dt>
              <dd id="insight-overdue" class="text-lg font-semibold">
                {@metrics.actions.overdue_count}
              </dd>
            </div>
          </dl>
        </section>
      </div>

      <%!--
        FR-605: aggregates across teams, and nothing that says who wrote
        what. The Org Admin's own team appears here as a row of numbers like
        any other, not as a board they can open.
      --%>
      <section
        :if={@org}
        id="org-insights"
        aria-labelledby="org-insights-heading"
        class="rounded-box border border-base-300 p-3"
      >
        <h2 id="org-insights-heading" class="text-sm font-semibold uppercase opacity-70">
          {gettext("Across the organisation")}
        </h2>

        <p class="mt-1 text-sm opacity-70">
          {gettext("Aggregates only — no card text and nobody's name.")}
        </p>

        <div class="mt-2 overflow-x-auto">
          <table class="table table-sm">
            <thead>
              <tr>
                <th>{gettext("Team")}</th>
                <th>{gettext("Retrospectives")}</th>
                <th>{gettext("Mood")}</th>
                <th>{gettext("Completed")}</th>
                <th>{gettext("Still open")}</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={row <- @org.teams} id={"org-team-#{row.team_id}"}>
                <td>{row.team_name}</td>
                <td>{row.session_count}</td>
                <td>{row.mood_average || "—"}</td>
                <td>{gettext("%{rate}%", rate: row.action_completion_rate)}</td>
                <td>{row.open_actions}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>
    </Layouts.app>
    """
  end

  @doc """
  One trend: a point per closed session, oldest first (FR-604).
  """
  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :points, :list, required: true
  attr :max, :any, required: true
  attr :unit, :string, default: ""

  def trend(assigns) do
    ~H"""
    <section
      id={@id}
      aria-labelledby={"#{@id}-heading"}
      class="rounded-box border border-base-300 p-3"
    >
      <h2 id={"#{@id}-heading"} class="text-sm font-semibold uppercase opacity-70">{@title}</h2>

      <ol class="mt-2 flex items-end gap-1">
        <li
          :for={point <- @points}
          id={"#{@id}-#{point.session_id}"}
          class="flex min-w-0 flex-1 flex-col items-center gap-1"
          title={point.title}
        >
          <span class="text-xs">{label(point.value, @unit)}</span>
          <div
            class="w-full rounded-t bg-primary"
            style={"height: #{height(point.value, @max)}px"}
            aria-hidden="true"
          >
          </div>
        </li>
      </ol>
    </section>
    """
  end

  @impl Phoenix.LiveView
  def mount(%{"team_id" => team_id}, _session, socket) do
    with {:ok, team} <- Teams.fetch_team(socket.assigns.current_scope, team_id),
         {:ok, metrics} <- Insights.team_metrics(socket.assigns.current_scope, team) do
      {:ok,
       socket
       |> assign(:page_title, gettext("Insights"))
       |> assign(:team, team)
       |> assign(:metrics, metrics)
       |> assign(:org, org_metrics(socket.assigns.current_scope))}
    else
      {:error, _reason} ->
        {:ok,
         socket
         |> put_flash(:error, gettext("That resource does not exist."))
         |> push_navigate(to: ~p"/teams")}
    end
  end

  defp org_metrics(scope) do
    if Policy.can?(scope, :view_org_insights) do
      {:ok, metrics} = Insights.org_metrics(scope)
      metrics
    end
  end

  # A gap in the line rather than a zero: nobody answered is not the same as
  # everybody hated it.
  defp label(nil, _unit), do: "—"
  defp label(value, unit), do: "#{value}#{unit}"

  defp height(nil, _max), do: 2
  defp height(_value, max) when max in [nil, 0], do: 2
  defp height(value, max), do: max(round(value / max * 60), 2)

  defp max_of(points) do
    points |> Enum.map(&(&1.value || 0)) |> Enum.max(fn -> 0 end)
  end
end
