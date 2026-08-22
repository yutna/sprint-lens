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
  alias SprintLens.Webhooks
  alias SprintLens.Webhooks.Delivery
  alias SprintLens.Webhooks.Subscription

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
      breadcrumbs={[{gettext("Teams"), ~p"/teams"}, {@team.name, ~p"/teams/#{@team}"}]}
    >
      <.header>
        {@team.name}
        <:subtitle>
          <span :if={@team.description}>{@team.description}</span>
        </:subtitle>
        <:actions>
          <.badge :if={@team.is_archived} tone="warning">{gettext("Archived")}</.badge>
          <.button
            :if={@can_toggle_archive and not @team.is_archived}
            id="archive-team"
            phx-click="archive"
            size="sm"
            data-confirm={gettext("Archive this team? It becomes read-only.")}
          >
            {gettext("Archive")}
          </.button>
          <.button
            :if={@can_toggle_archive and @team.is_archived}
            id="restore-team"
            phx-click="restore"
            variant="primary"
            size="sm"
          >
            {gettext("Restore")}
          </.button>
        </:actions>
      </.header>

      <Layouts.notice :if={@team.is_archived} id="team-archived-notice">
        {gettext("This team is archived. Its history stays readable and nothing new can be added.")}
      </Layouts.notice>

      <.panel id="team-members" title={gettext("Members")}>
        <:subtitle>
          {ngettext("%{count} person", "%{count} people", length(@members), count: length(@members))}
        </:subtitle>

        <.form
          :if={@can_manage_members}
          for={@member_form}
          id="add_member_form"
          phx-submit="add_member"
          class="flex flex-wrap items-end gap-3 rounded-panel border border-base-200 bg-base-100 p-4 shadow-resting"
        >
          <div class="min-w-56 grow">
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

        <ul
          id="members"
          class="divide-y divide-base-200 overflow-hidden rounded-panel border border-base-200 bg-base-100"
        >
          <li
            :for={membership <- @members}
            id={"member-#{membership.user_id}"}
            class="flex flex-wrap items-center gap-3 p-3"
          >
            <.avatar name={membership.user.display_name} />
            <span class="min-w-0 grow truncate font-medium">
              {membership.user.display_name}
            </span>
            <.badge tone={role_tone(membership.role)}>{role_label(membership.role)}</.badge>
            <.button
              :if={@can_manage_members and membership.user_id != @current_scope.user.id}
              id={"remove-member-#{membership.user_id}"}
              phx-click="remove_member"
              phx-value-user-id={membership.user_id}
              variant="ghost"
              size="sm"
            >
              {gettext("Remove")}
            </.button>
            <.button
              :if={membership.user_id == @current_scope.user.id}
              id="leave-team"
              phx-click="leave"
              data-confirm={gettext("Leave this team?")}
              variant="ghost"
              size="sm"
            >
              {gettext("Leave")}
            </.button>
          </li>
        </ul>
      </.panel>

      <.panel
        :if={@can_manage_settings}
        id="team-settings"
        title={gettext("Settings")}
        class="max-w-md"
      >
        <:subtitle>{gettext("What a new retrospective starts with.")}</:subtitle>

        <.form
          for={@settings_form}
          id="team_settings_form"
          phx-change="validate_settings"
          phx-submit="save_settings"
          class="rounded-panel border border-base-200 bg-base-100 p-4 shadow-resting sm:p-6"
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
      </.panel>

      <%!--
        SCR-04's webhook section (FR-704 to FR-706). Lead-only, because
        section 3.1 puts `manage_webhooks` there, and because the shared
        secret is the sort of thing a smaller audience is better for.
      --%>
      <.panel :if={@can_manage_webhooks} id="team-webhook" title={gettext("Webhook")}>
        <:subtitle>{gettext("Tell another system when something happens here.")}</:subtitle>

        <.form
          for={@webhook_form}
          id="webhook_form"
          phx-submit="save_webhook"
          class="max-w-md space-y-2 rounded-panel border border-base-200 bg-base-100 p-4 shadow-resting sm:p-6"
        >
          <.input
            field={@webhook_form[:url]}
            type="url"
            label={gettext("Where to POST")}
            placeholder="https://hooks.example.com/sprintlens"
            required
          />

          <%!--
            Never rendered with the stored value: a shared secret that
            appears on every page render has a much larger surface than it
            needs. Leaving it blank keeps the one already saved.
          --%>
          <.input
            field={@webhook_form[:secret]}
            type="password"
            label={gettext("Shared secret")}
            value=""
            autocomplete="off"
          />

          <fieldset class="space-y-1.5 pt-1">
            <legend class="pb-1 text-label font-medium">{gettext("Send these events")}</legend>
            <label :for={event <- Subscription.events()} class="flex items-center gap-2">
              <input
                type="checkbox"
                id={"webhook-event-#{event}"}
                name="webhook[events][]"
                value={event}
                checked={event in @webhook_events}
                class="size-4 rounded-sm border-base-300 accent-primary"
              />
              <span class="font-mono text-label">{event}</span>
            </label>
          </fieldset>

          <.input
            field={@webhook_form[:is_active]}
            type="checkbox"
            label={gettext("Send deliveries")}
          />

          <div class="flex gap-2">
            <.button id="save-webhook" variant="primary" phx-disable-with={gettext("Saving...")}>
              {gettext("Save webhook")}
            </.button>
            <.button
              :if={@webhook}
              id="delete-webhook"
              phx-click="delete_webhook"
              variant="ghost"
              data-confirm={gettext("Remove this webhook?")}
            >
              {gettext("Remove")}
            </.button>
          </div>
        </.form>

        <h3 class="pt-2 text-label font-semibold">{gettext("Recent deliveries")}</h3>

        <p :if={@deliveries == []} id="deliveries-empty" class="text-label text-base-content/60">
          {gettext("Nothing has been sent yet.")}
        </p>

        <ul :if={@deliveries != []} id="deliveries" class="space-y-1">
          <li
            :for={delivery <- @deliveries}
            id={"delivery-#{delivery.id}"}
            class="flex flex-wrap items-center gap-2 rounded-card border border-base-200 p-2 text-label"
          >
            <.badge tone={if(Delivery.status(delivery) == :delivered, do: "success", else: "danger")}>
              {delivery.status}
            </.badge>
            <span class="font-mono">{delivery.event}</span>
            <span class="text-base-content/70">
              {gettext("attempt %{n}", n: delivery.attempt)}
            </span>
            <span :if={delivery.error} class="text-base-content/70">{delivery.error}</span>
            <span class="ml-auto text-base-content/60">
              {SprintLensWeb.Locale.format_datetime(delivery.inserted_at)}
            </span>
          </li>
        </ul>
      </.panel>
    </Layouts.app>
    """
  end

  # A blank secret box means "keep the one already saved", because the form
  # never renders the stored secret back (see the section above).
  defp webhook_attrs(params, subscription) do
    secret =
      case String.trim(params["secret"] || "") do
        "" -> subscription && subscription.secret
        typed -> typed
      end

    %{
      "url" => params["url"],
      "secret" => secret,
      "events" => params["events"] || [],
      "is_active" => params["is_active"] || "false"
    }
  end

  defp assign_webhook(socket, team) do
    subscription = Webhooks.get_subscription(team)

    socket
    |> assign(:webhook, subscription)
    |> assign(:webhook_events, subscription_events(subscription))
    |> assign(
      :webhook_form,
      to_form(Webhooks.change_subscription(subscription || %Subscription{}), as: "webhook")
    )
    |> assign(:deliveries, (subscription && Webhooks.list_deliveries(subscription)) || [])
  end

  defp subscription_events(nil), do: Enum.map(Subscription.events(), &Atom.to_string/1)

  defp subscription_events(subscription) do
    Enum.map(Subscription.subscribed(subscription), &Atom.to_string/1)
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

  def handle_event("save_webhook", %{"webhook" => params}, socket) do
    attrs = webhook_attrs(params, socket.assigns.webhook)

    case Webhooks.configure(socket.assigns.current_scope, socket.assigns.team, attrs) do
      {:ok, _subscription} ->
        {:noreply,
         socket |> load(socket.assigns.team) |> put_flash(:info, gettext("Webhook saved."))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         assign(
           socket,
           :webhook_form,
           to_form(Map.put(changeset, :action, :insert), as: "webhook")
         )}

      {:error, :unauthorized} ->
        {:noreply, refuse(socket)}
    end
  end

  def handle_event("delete_webhook", _params, socket) do
    case Webhooks.delete_subscription(socket.assigns.current_scope, socket.assigns.team) do
      :ok ->
        {:noreply,
         socket |> load(socket.assigns.team) |> put_flash(:info, gettext("Webhook removed."))}

      {:error, :not_found} ->
        {:noreply, load(socket, socket.assigns.team)}

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
    |> assign(
      :can_manage_webhooks,
      Policy.manage?(scope, :manage_webhooks, role, team.is_archived)
    )
    |> assign_webhook(team)
    |> assign(:settings_form, to_form(Teams.change_team_settings(team), as: "team"))
    |> assign(:member_form, to_form(Teams.change_membership(), as: "membership"))
  end

  defp role_options do
    [{gettext("Member"), "member"}, {gettext("Lead"), "lead"}]
  end

  defp role_label("lead"), do: gettext("Lead")
  defp role_label("member"), do: gettext("Member")

  # A lead is the one role that changes what you can do here, so it is the one
  # that gets a colour. Marking everybody would mean marking nobody.
  defp role_tone("lead"), do: "primary"
  defp role_tone("member"), do: "neutral"

  defp template_options(templates), do: Enum.map(templates, &{&1.name, &1.id})
end
