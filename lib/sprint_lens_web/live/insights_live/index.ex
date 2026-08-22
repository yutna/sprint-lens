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
      team={@team}
      breadcrumbs={[
        {gettext("Teams"), ~p"/teams"},
        {@team.name, ~p"/teams/#{@team}"},
        {gettext("Insights"), ~p"/teams/#{@team}/insights"}
      ]}
    >
      <.header>
        {gettext("Insights")}
        <:subtitle>{gettext("How this team's retrospectives are going, over time.")}</:subtitle>
      </.header>

      <.empty_state
        :if={@metrics.session_count == 0}
        id="insights-empty"
        title={gettext("Nothing to show yet.")}
      >
        {gettext("Numbers appear once the team has finished a retrospective.")}
      </.empty_state>

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

        <.panel id="action-health" title={gettext("Actions")}>
          <.stats>
            <.stat id="insight-completion" label={gettext("Completed")}>
              {gettext("%{rate}%", rate: @metrics.actions.completion_rate)}
            </.stat>
            <.stat id="insight-open" label={gettext("Still open")}>
              {@metrics.actions.open_count}
            </.stat>
            <.stat id="insight-age" label={gettext("Average age")}>
              {@metrics.actions.average_age_days}
            </.stat>
            <.stat id="insight-overdue" label={gettext("Overdue")}>
              {@metrics.actions.overdue_count}
            </.stat>
          </.stats>
        </.panel>
      </div>

      <%!--
        FR-605: aggregates across teams, and nothing that says who wrote
        what. The Org Admin's own team appears here as a row of numbers like
        any other, not as a board they can open.
      --%>
      <.panel :if={@org} id="org-insights" title={gettext("Across the organisation")}>
        <:subtitle>{gettext("Aggregates only — no card text and nobody's name.")}</:subtitle>

        <%!--
          The wrapper is what scrolls, not the page: five columns of numbers
          do not fit across a phone and FR-905 is about the document.
        --%>
        <div class="overflow-x-auto rounded-panel border border-base-200 bg-base-100 px-4">
          <.table id="org-teams" rows={@org.teams} row_id={&"org-team-#{&1.team_id}"}>
            <:col :let={row} label={gettext("Team")}>{row.team_name}</:col>
            <:col :let={row} label={gettext("Retrospectives")}>{row.session_count}</:col>
            <:col :let={row} label={gettext("Mood")}>{row.mood_average || "—"}</:col>
            <:col :let={row} label={gettext("Completed")}>
              {gettext("%{rate}%", rate: row.action_completion_rate)}
            </:col>
            <:col :let={row} label={gettext("Still open")}>{row.open_actions}</:col>
          </.table>
        </div>
      </.panel>
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
    <.panel id={@id} title={@title}>
      <%!--
        Each bar sits in a track of the full height, so a low number reads as
        low rather than as a missing bar, and the baseline is the same across
        all four charts on the page.

        A fixed bar width rather than a share of the row: a team with one
        finished retrospective was getting a single bar stretched across the
        whole page, which reads as a rule under a heading rather than as a
        measurement. Many of them scroll the strip instead of thinning it
        past the point where the number above stops fitting.
      --%>
      <ol class="flex items-end gap-2 overflow-x-auto rounded-panel border border-base-200 bg-base-100 p-4">
        <li
          :for={point <- @points}
          id={"#{@id}-#{point.session_id}"}
          class="flex w-14 shrink-0 flex-col items-center gap-1"
          title={point.title}
        >
          <span class="text-caption tabular-nums">{label(point.value, @unit)}</span>
          <span class="flex h-15 w-full items-end rounded-t-sm bg-base-200" aria-hidden="true">
            <span
              class="w-full rounded-t-sm bg-primary"
              style={"height: #{height(point.value, @max)}px"}
            ></span>
          </span>
        </li>
      </ol>
    </.panel>
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
