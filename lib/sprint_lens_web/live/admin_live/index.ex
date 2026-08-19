defmodule SprintLensWeb.AdminLive.Index do
  @moduledoc """
  SCR-12 Admin — people, settings, retention and the audit log (FR-801 to
  FR-807).

  ## Everything destructive asks first

  FR-804 wants "an explicit confirmation" before a purge, and the same is true
  of erasing somebody: both are irreversible and neither has an undo anywhere
  in this app. `data-confirm` is the browser's own dialogue, which cannot be
  missed the way an inline "are you sure?" can.

  ## The page is one LiveView, not four

  An administrator's questions run together — who is this person, which teams
  do they lead, what happened last week — so the answers are on one page. It
  mounts behind `manage_users`, which section 3.1 already gives to the Org
  Admin alone.
  """

  use SprintLensWeb, :live_view

  alias SprintLens.Accounts.User
  alias SprintLens.Admin
  alias SprintLens.Admin.AuditEvent
  alias SprintLens.Admin.OrgSettings
  alias SprintLens.Policy
  alias SprintLens.Repo
  alias SprintLens.Retro
  alias SprintLens.Retro.Session
  alias SprintLens.Teams.Team

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} locale={@locale} theme={@theme}>
      <.header>
        {gettext("Administration")}
        <:subtitle>{gettext("People, settings, retention and the audit log.")}</:subtitle>
      </.header>

      <section aria-labelledby="org-settings-heading">
        <h2 id="org-settings-heading" class="mb-2 text-sm font-semibold uppercase opacity-70">
          {gettext("Organisation settings")}
        </h2>

        <.form
          for={@settings_form}
          id="org_settings_form"
          phx-submit="save_settings"
          class="max-w-md space-y-2"
        >
          <.input
            field={@settings_form[:default_language]}
            type="select"
            label={gettext("Default language")}
            options={language_options()}
          />
          <.input
            field={@settings_form[:default_vote_budget]}
            type="number"
            label={gettext("Default vote budget")}
            min="1"
            max="20"
          />
          <.input
            field={@settings_form[:retention_days]}
            type="number"
            label={gettext("Keep closed retrospectives for (days)")}
            min="30"
            max="3650"
          />

          <%!--
            The two kill switches of FR-806. Named as switches rather than as
            preferences: turning one off stops work that is already queued.
          --%>
          <.input
            field={@settings_form[:ai_enabled]}
            type="checkbox"
            label={gettext("AI features are available")}
          />
          <.input
            field={@settings_form[:webhooks_enabled]}
            type="checkbox"
            label={gettext("Webhook deliveries are sent")}
          />

          <.button id="save-settings" variant="primary" phx-disable-with={gettext("Saving...")}>
            {gettext("Save settings")}
          </.button>
        </.form>
      </section>

      <section aria-labelledby="users-heading">
        <h2 id="users-heading" class="mb-2 text-sm font-semibold uppercase opacity-70">
          {gettext("People")}
        </h2>

        <ul id="admin-users" class="space-y-2">
          <li
            :for={user <- @users}
            id={"admin-user-#{user.id}"}
            class="flex flex-wrap items-center gap-2 rounded-box border border-base-200 p-2"
          >
            <div class="min-w-0 grow">
              <p class="font-medium">{user.display_name}</p>
              <p class="text-xs opacity-70">{user.email}</p>
            </div>

            <span :if={user.is_org_admin} class="badge badge-sm badge-primary">
              {gettext("Org Admin")}
            </span>
            <span :if={not user.is_active} id={"admin-inactive-#{user.id}"} class="badge badge-sm">
              {gettext("Deactivated")}
            </span>
            <span :if={User.erased?(user)} id={"admin-erased-#{user.id}"} class="badge badge-sm">
              {gettext("Erased")}
            </span>

            <.button
              :if={user.is_active}
              id={"deactivate-#{user.id}"}
              phx-click="deactivate"
              phx-value-id={user.id}
              data-confirm={gettext("Deactivate this person? They will be signed out.")}
              class="btn btn-ghost btn-xs"
            >
              {gettext("Deactivate")}
            </.button>

            <.button
              :if={not user.is_active and not User.erased?(user)}
              id={"reactivate-#{user.id}"}
              phx-click="reactivate"
              phx-value-id={user.id}
              class="btn btn-ghost btn-xs"
            >
              {gettext("Reactivate")}
            </.button>

            <.button
              :if={not User.erased?(user)}
              id={"erase-#{user.id}"}
              phx-click="erase"
              phx-value-id={user.id}
              data-confirm={gettext("Erase this person's personal data? This cannot be undone.")}
              class="btn btn-ghost btn-xs"
            >
              {gettext("Erase")}
            </.button>
          </li>
        </ul>
      </section>

      <section aria-labelledby="leadership-heading">
        <h2 id="leadership-heading" class="mb-2 text-sm font-semibold uppercase opacity-70">
          {gettext("Team leadership")}
        </h2>

        <.form
          for={@leadership_form}
          id="leadership_form"
          phx-submit="reassign"
          class="flex max-w-2xl flex-wrap items-end gap-2"
        >
          <div class="grow">
            <.input
              field={@leadership_form[:team_id]}
              type="select"
              label={gettext("Team")}
              options={team_options(@teams)}
            />
          </div>
          <div class="grow">
            <.input
              field={@leadership_form[:user_id]}
              type="select"
              label={gettext("New lead")}
              options={user_options(@users)}
            />
          </div>
          <.button id="reassign-lead" variant="primary" class="mb-2">
            {gettext("Make lead")}
          </.button>
        </.form>
      </section>

      <section aria-labelledby="retention-heading">
        <h2 id="retention-heading" class="mb-2 text-sm font-semibold uppercase opacity-70">
          {gettext("Purge on demand")}
        </h2>

        <p :if={@teams == []} id="purge-empty" class="text-sm opacity-60">
          {gettext("There is nothing to purge.")}
        </p>

        <ul :if={@teams != []} id="admin-teams" class="space-y-2">
          <li
            :for={team <- @teams}
            id={"admin-team-#{team.id}"}
            class="rounded-box border border-base-200 p-2"
          >
            <div class="flex flex-wrap items-center gap-2">
              <span class="grow font-medium">{team.name}</span>
              <.button
                id={"purge-team-#{team.id}"}
                phx-click="purge_team"
                phx-value-id={team.id}
                data-confirm={gettext("Purge this team and everything in it? This cannot be undone.")}
                class="btn btn-ghost btn-xs"
              >
                {gettext("Purge team")}
              </.button>
            </div>

            <ul class="mt-1 space-y-1 pl-3">
              <li
                :for={session <- closed_sessions(@sessions, team)}
                id={"admin-session-#{session.id}"}
                class="flex flex-wrap items-center gap-2 text-sm"
              >
                <span class="grow">{session.title}</span>
                <span class="opacity-60">
                  {SprintLensWeb.Locale.format_datetime(session.closed_at)}
                </span>
                <.button
                  id={"purge-session-#{session.id}"}
                  phx-click="purge_session"
                  phx-value-id={session.id}
                  data-confirm={gettext("Purge this retrospective? This cannot be undone.")}
                  class="btn btn-ghost btn-xs"
                >
                  {gettext("Purge")}
                </.button>
              </li>
            </ul>
          </li>
        </ul>
      </section>

      <section aria-labelledby="audit-heading">
        <h2 id="audit-heading" class="mb-2 text-sm font-semibold uppercase opacity-70">
          {gettext("Audit log")}
        </h2>

        <p :if={@events == []} id="audit-empty" class="text-sm opacity-60">
          {gettext("Nothing has been done yet.")}
        </p>

        <ul :if={@events != []} id="audit-events" class="space-y-1">
          <li
            :for={event <- @events}
            id={"audit-#{event.id}"}
            class="flex flex-wrap items-center gap-2 rounded-box border border-base-200 p-2 text-sm"
          >
            <span class="font-mono">{event.action}</span>
            <span class="opacity-70">{event.target}</span>
            <span class="opacity-70">{actor_name(event)}</span>
            <span :if={AuditEvent.detail(event) != %{}} class="font-mono text-xs opacity-60">
              {inspect(AuditEvent.detail(event))}
            </span>
            <span class="ml-auto opacity-60">
              {SprintLensWeb.Locale.format_datetime(event.inserted_at)}
            </span>
          </li>
        </ul>
      </section>
    </Layouts.app>
    """
  end

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    if Policy.can?(socket.assigns.current_scope, :manage_users) do
      {:ok, socket |> assign(:page_title, gettext("Administration")) |> load()}
    else
      {:ok,
       socket
       |> put_flash(:error, gettext("You do not have permission to do that."))
       |> push_navigate(to: ~p"/home")}
    end
  end

  @impl Phoenix.LiveView
  def handle_event("save_settings", %{"settings" => params}, socket) do
    case Admin.update_settings(socket.assigns.current_scope, params) do
      {:ok, _settings} ->
        {:noreply, socket |> load() |> put_flash(:info, gettext("Settings saved."))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         assign(
           socket,
           :settings_form,
           to_form(Map.put(changeset, :action, :insert), as: "settings")
         )}

      {:error, :unauthorized} ->
        {:noreply, refuse(socket)}
    end
  end

  def handle_event("deactivate", %{"id" => id}, socket) do
    with_user(socket, id, &Admin.deactivate_user(socket.assigns.current_scope, &1))
  end

  def handle_event("reactivate", %{"id" => id}, socket) do
    with_user(socket, id, &Admin.reactivate_user(socket.assigns.current_scope, &1))
  end

  def handle_event("erase", %{"id" => id}, socket) do
    with_user(socket, id, &Admin.erase_user(socket.assigns.current_scope, &1))
  end

  def handle_event("reassign", %{"leadership" => %{"team_id" => team, "user_id" => user}}, socket) do
    with {:ok, team} <- fetch_team(team),
         {:ok, user} <- fetch_user(user),
         {:ok, _membership} <-
           Admin.reassign_leadership(socket.assigns.current_scope, team, user) do
      {:noreply, socket |> load() |> put_flash(:info, gettext("Leadership reassigned."))}
    else
      error -> {:noreply, report(socket, error)}
    end
  end

  def handle_event("purge_session", %{"id" => id}, socket) do
    with {:ok, session} <- fetch_session(id),
         {:ok, _purged} <- Admin.purge_session(socket.assigns.current_scope, session) do
      {:noreply, socket |> load() |> put_flash(:info, gettext("Retrospective purged."))}
    else
      error -> {:noreply, report(socket, error)}
    end
  end

  def handle_event("purge_team", %{"id" => id}, socket) do
    with {:ok, team} <- fetch_team(id),
         {:ok, _purged} <- Admin.purge_team(socket.assigns.current_scope, team) do
      {:noreply, socket |> load() |> put_flash(:info, gettext("Team purged."))}
    else
      error -> {:noreply, report(socket, error)}
    end
  end

  defp with_user(socket, id, fun) do
    with {:ok, user} <- fetch_user(id),
         {:ok, _result} <- fun.(user) do
      {:noreply, load(socket)}
    else
      error -> {:noreply, report(socket, error)}
    end
  end

  defp load(socket) do
    scope = socket.assigns.current_scope
    {:ok, users} = Admin.list_users(scope)
    {:ok, events} = Admin.list_audit_events(scope)
    teams = Repo.all(Team)

    socket
    |> assign(:users, users)
    |> assign(:teams, teams)
    |> assign(:sessions, Enum.flat_map(teams, &Retro.list_sessions/1))
    |> assign(:events, events)
    |> assign(:settings_form, to_form(Admin.change_settings(), as: "settings"))
    |> assign(:leadership_form, to_form(%{}, as: "leadership"))
  end

  defp report(socket, {:error, :last_lead, details}) do
    put_flash(
      socket,
      :error,
      gettext("Reassign leadership of %{count} team(s) first.",
        count: length(details.team_ids)
      )
    )
  end

  defp report(socket, {:error, :unauthorized}), do: refuse(socket)

  defp report(socket, {:error, :wrong_state}) do
    put_flash(socket, :error, gettext("Close the retrospective before purging it."))
  end

  defp report(socket, {:error, _reason}) do
    put_flash(socket, :error, gettext("That resource does not exist."))
  end

  defp refuse(socket) do
    put_flash(socket, :error, gettext("You do not have permission to do that."))
  end

  defp fetch_user(id) do
    case Repo.fetch(User, id) do
      nil -> {:error, :not_found}
      user -> {:ok, user}
    end
  end

  defp fetch_team(id) do
    case Repo.fetch(SprintLens.Teams.Team, id) do
      nil -> {:error, :not_found}
      team -> {:ok, team}
    end
  end

  defp fetch_session(id) do
    case Repo.fetch(Session, id) do
      nil -> {:error, :not_found}
      session -> {:ok, session}
    end
  end

  defp closed_sessions(sessions, team) do
    Enum.filter(sessions, &(&1.team_id == team.id and not is_nil(&1.closed_at)))
  end

  defp language_options do
    Enum.map(OrgSettings.languages(), &{language_label(&1), &1})
  end

  defp language_label("th"), do: gettext("Thai")
  defp language_label("en"), do: gettext("English")

  defp team_options(teams), do: Enum.map(teams, &{&1.name, &1.id})
  defp user_options(users), do: Enum.map(users, &{&1.display_name, &1.id})

  defp actor_name(%{actor: %{display_name: name}}), do: name
  defp actor_name(_event), do: gettext("system")
end
