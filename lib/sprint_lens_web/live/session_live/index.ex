defmodule SprintLensWeb.SessionLive.Index do
  @moduledoc """
  SCR-05 Session list and SCR-06 Create session (FR-201, FR-203).

  One screen rather than two: the list is short and the form is short, and a
  team member arriving to start a retro should not have to navigate twice to
  do the only thing this page is for.
  """

  use SprintLensWeb, :live_view

  alias SprintLens.Retro
  alias SprintLens.Retro.Session
  alias SprintLens.Teams
  alias SprintLensWeb.Locale

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} locale={@locale} theme={@theme}>
      <.header>
        {gettext("Retrospectives")}
        <:subtitle>{@team.name}</:subtitle>
        <:actions>
          <.link navigate={~p"/teams/#{@team}"} class="btn btn-ghost btn-sm">
            {gettext("Back to team")}
          </.link>
        </:actions>
      </.header>

      <.form
        :if={not @team.is_archived}
        for={@form}
        id="session_form"
        phx-change="validate"
        phx-submit="save"
        class="max-w-md"
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

      <section aria-labelledby="sessions-heading">
        <h2 id="sessions-heading" class="mb-2 text-sm font-semibold uppercase opacity-70">
          {gettext("Sessions")}
        </h2>

        <p :if={@sessions == []} id="sessions-empty" class="rounded-box border border-base-300 p-6">
          {gettext("No retrospectives yet. Create one above.")}
        </p>

        <ul :if={@sessions != []} id="sessions" class="grid gap-3">
          <li :for={session <- @sessions} id={"session-#{session.id}"}>
            <.link
              navigate={~p"/sessions/#{session}"}
              class="block rounded-box border border-base-300 p-4 hover:border-primary"
            >
              <div class="flex flex-wrap items-center gap-2">
                <span class="font-semibold">{session.title}</span>
                <span class={["badge badge-sm", state_class(session)]}>
                  {state_label(Session.state(session))}
                </span>
                <span :if={session.is_anonymous} class="badge badge-ghost badge-sm">
                  {gettext("Anonymous")}
                </span>
              </div>
              <p class="text-sm opacity-70">
                <span :if={session.scheduled_at}>
                  {gettext("Scheduled for %{at}",
                    at: Locale.format_datetime(session.scheduled_at)
                  )}
                </span>
                <span :if={is_nil(session.scheduled_at)}>
                  {gettext("Created %{at}", at: Locale.format_datetime(session.inserted_at))}
                </span>
              </p>
            </.link>
          </li>
        </ul>
      </section>
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

  defp assign_sessions(socket) do
    assign(socket, :sessions, Retro.list_sessions(socket.assigns.team))
  end

  defp assign_form(socket, changeset) do
    assign(socket, :form, to_form(changeset, as: "session"))
  end

  defp template_options(templates), do: Enum.map(templates, &{&1.name, &1.id})

  defp state_label(:created), do: gettext("Not started")
  defp state_label(:active), do: gettext("Running")
  defp state_label(:closed), do: gettext("Closed")

  defp state_class(session) do
    case Session.state(session) do
      :active -> "badge-primary"
      :closed -> "badge-ghost"
      _created -> "badge-outline"
    end
  end
end
