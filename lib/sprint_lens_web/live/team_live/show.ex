defmodule SprintLensWeb.TeamLive.Show do
  @moduledoc """
  SCR-04 Team detail: members, settings and the AI opt-in (FR-102, FR-105,
  FR-106, AI-003).

  Every control is rendered only when `SprintLens.Policy` allows it *and*
  refused again in the context when used, so hiding a button is a courtesy
  rather than the security boundary (NFR-201).
  """

  use SprintLensWeb, :live_view

  alias SprintLens.Policy
  alias SprintLens.Teams

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} locale={@locale} theme={@theme}>
      <.header>
        {@team.name}
        <:subtitle>
          <span :if={@team.is_archived} class="badge badge-ghost">{gettext("Archived")}</span>
          <span :if={@team.description}>{@team.description}</span>
        </:subtitle>
        <:actions>
          <.link navigate={~p"/teams/#{@team}/sessions"} class="btn btn-primary btn-sm">
            {gettext("Retrospectives")}
          </.link>
          <.link
            navigate={~p"/teams/#{@team}/actions"}
            id="team-actions-link"
            class="btn btn-ghost btn-sm"
          >
            {gettext("Actions")}
          </.link>
          <.link
            navigate={~p"/teams/#{@team}/insights"}
            id="team-insights-link"
            class="btn btn-ghost btn-sm"
          >
            {gettext("Insights")}
          </.link>
          <.link
            navigate={~p"/teams/#{@team}/search"}
            id="team-search-link"
            class="btn btn-ghost btn-sm"
          >
            {gettext("Search")}
          </.link>
          <.link navigate={~p"/teams/#{@team}/templates"} class="btn btn-ghost btn-sm">
            {gettext("Templates")}
          </.link>
          <.button
            :if={@can_toggle_archive and not @team.is_archived}
            id="archive-team"
            phx-click="archive"
            data-confirm={gettext("Archive this team? It becomes read-only.")}
          >
            {gettext("Archive")}
          </.button>
          <.button
            :if={@can_toggle_archive and @team.is_archived}
            id="restore-team"
            phx-click="restore"
          >
            {gettext("Restore")}
          </.button>
        </:actions>
      </.header>

      <section aria-labelledby="members-heading">
        <h2 id="members-heading" class="mb-2 text-sm font-semibold uppercase opacity-70">
          {gettext("Members")}
        </h2>

        <.form
          :if={@can_manage_members}
          for={@member_form}
          id="add_member_form"
          phx-submit="add_member"
          class="mb-4 flex flex-wrap items-end gap-2"
        >
          <div class="grow">
            <.input
              field={@member_form[:email]}
              type="email"
              label={gettext("Add someone by email")}
              spellcheck="false"
              required
            />
          </div>
          <div class="w-40">
            <.input
              field={@member_form[:role]}
              type="select"
              label={gettext("Role")}
              options={role_options()}
            />
          </div>
          <.button variant="primary" phx-disable-with={gettext("Adding...")} class="mb-2">
            {gettext("Add")}
          </.button>
        </.form>

        <ul id="members" class="list rounded-box border border-base-300">
          <li :for={membership <- @members} id={"member-#{membership.user_id}"} class="list-row">
            <div class="list-col-grow">
              <span class="font-semibold">{membership.user.display_name}</span>
              <span class="badge badge-sm ml-2">{role_label(membership.role)}</span>
            </div>
            <.button
              :if={@can_manage_members and membership.user_id != @current_scope.user.id}
              id={"remove-member-#{membership.user_id}"}
              phx-click="remove_member"
              phx-value-user-id={membership.user_id}
              class="btn btn-ghost btn-xs"
            >
              {gettext("Remove")}
            </.button>
            <.button
              :if={membership.user_id == @current_scope.user.id}
              id="leave-team"
              phx-click="leave"
              data-confirm={gettext("Leave this team?")}
              class="btn btn-ghost btn-xs"
            >
              {gettext("Leave")}
            </.button>
          </li>
        </ul>
      </section>

      <section :if={@can_manage_settings} aria-labelledby="settings-heading">
        <h2 id="settings-heading" class="mb-2 text-sm font-semibold uppercase opacity-70">
          {gettext("Settings")}
        </h2>

        <.form
          for={@settings_form}
          id="team_settings_form"
          phx-change="validate_settings"
          phx-submit="save_settings"
          class="max-w-md"
        >
          <.input field={@settings_form[:name]} type="text" label={gettext("Team name")} required />
          <.input
            field={@settings_form[:description]}
            type="textarea"
            label={gettext("Description")}
            rows="2"
          />
          <.input
            field={@settings_form[:default_template_id]}
            type="select"
            label={gettext("Default template")}
            prompt={gettext("No default")}
            options={template_options(@templates)}
          />
          <.input
            field={@settings_form[:default_vote_budget]}
            type="number"
            label={gettext("Default vote budget")}
            min="1"
            max="20"
          />
          <.input
            field={@settings_form[:ai_opt_in]}
            type="checkbox"
            label={gettext("Allow AI assistance for this team")}
          />
          <.button variant="primary" phx-disable-with={gettext("Saving...")}>
            {gettext("Save settings")}
          </.button>
        </.form>
      </section>
    </Layouts.app>
    """
  end

  @impl Phoenix.LiveView
  def mount(%{"id" => id}, _session, socket) do
    case Teams.fetch_team(socket.assigns.current_scope, id) do
      {:ok, team} ->
        {:ok, socket |> assign(:page_title, team.name) |> load(team)}

      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, gettext("That resource does not exist."))
         |> push_navigate(to: ~p"/teams")}
    end
  end

  @impl Phoenix.LiveView
  def handle_event("validate_settings", %{"team" => params}, socket) do
    changeset =
      socket.assigns.team
      |> Teams.change_team_settings(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :settings_form, to_form(changeset, as: "team"))}
  end

  def handle_event("save_settings", %{"team" => params}, socket) do
    case Teams.update_team_settings(socket.assigns.current_scope, socket.assigns.team, params) do
      {:ok, team} ->
        {:noreply, socket |> load(team) |> put_flash(:info, gettext("Settings saved."))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         assign(socket, :settings_form, to_form(Map.put(changeset, :action, :insert), as: "team"))}

      {:error, :unauthorized} ->
        {:noreply, refuse(socket)}
    end
  end

  def handle_event("add_member", %{"membership" => %{"email" => email} = params}, socket) do
    role = Map.get(params, "role", "member")

    case Teams.add_member_by_email(socket.assigns.current_scope, socket.assigns.team, email, role) do
      {:ok, _membership} ->
        {:noreply,
         socket |> load(socket.assigns.team) |> put_flash(:info, gettext("Member added."))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         assign(
           socket,
           :member_form,
           to_form(Map.put(changeset, :action, :insert), as: "membership")
         )}

      {:error, :unauthorized} ->
        {:noreply, refuse(socket)}
    end
  end

  def handle_event("remove_member", %{"user-id" => user_id}, socket) do
    socket.assigns.current_scope
    |> Teams.remove_member(socket.assigns.team, String.to_integer(user_id))
    |> respond_to_membership_change(socket)
  end

  def handle_event("leave", _params, socket) do
    case Teams.leave_team(socket.assigns.current_scope, socket.assigns.team) do
      :ok ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("You have left the team."))
         |> push_navigate(to: ~p"/teams")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, membership_error(reason))}
    end
  end

  def handle_event("archive", _params, socket) do
    case Teams.archive_team(socket.assigns.current_scope, socket.assigns.team) do
      {:ok, team} ->
        {:noreply, socket |> load(team) |> put_flash(:info, gettext("Team archived."))}

      {:error, :unauthorized} ->
        {:noreply, refuse(socket)}
    end
  end

  def handle_event("restore", _params, socket) do
    case Teams.restore_team(socket.assigns.current_scope, socket.assigns.team) do
      {:ok, team} ->
        {:noreply, socket |> load(team) |> put_flash(:info, gettext("Team restored."))}

      {:error, :unauthorized} ->
        {:noreply, refuse(socket)}
    end
  end

  defp respond_to_membership_change(:ok, socket) do
    {:noreply,
     socket |> load(socket.assigns.team) |> put_flash(:info, gettext("Member removed."))}
  end

  defp respond_to_membership_change({:error, reason}, socket) do
    {:noreply, put_flash(socket, :error, membership_error(reason))}
  end

  defp membership_error(:last_lead), do: gettext("A team needs at least one lead.")
  defp membership_error(:not_found), do: gettext("That resource does not exist.")
  defp membership_error(:unauthorized), do: gettext("You do not have permission to do that.")

  defp refuse(socket) do
    put_flash(socket, :error, gettext("You do not have permission to do that."))
  end

  defp load(socket, team) do
    scope = socket.assigns.current_scope
    role = Teams.role(scope, team)

    socket
    |> assign(:team, team)
    |> assign(:members, Teams.list_members(team))
    |> assign(:templates, Teams.list_templates(team))
    |> assign(:can_manage_members, Policy.manage?(scope, :manage_members, role, team.is_archived))
    # Editing settings and restoring the team are different rights: an
    # archived team is read-only (FR-106), so its settings form is gone, but
    # a lead must still be able to bring it back.
    |> assign(
      :can_manage_settings,
      Policy.manage?(scope, :edit_team_settings, role, team.is_archived)
    )
    |> assign(:can_toggle_archive, Policy.can?(scope, :edit_team_settings, role))
    |> assign(:settings_form, to_form(Teams.change_team_settings(team), as: "team"))
    |> assign(:member_form, to_form(Teams.change_membership(), as: "membership"))
  end

  defp role_options do
    [{gettext("Member"), "member"}, {gettext("Lead"), "lead"}]
  end

  defp role_label("lead"), do: gettext("Lead")
  defp role_label("member"), do: gettext("Member")

  defp template_options(templates), do: Enum.map(templates, &{&1.name, &1.id})
end
