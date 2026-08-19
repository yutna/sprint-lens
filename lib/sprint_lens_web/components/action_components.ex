defmodule SprintLensWeb.ActionComponents do
  @moduledoc """
  Action items wherever they appear: on the board, at check-in, and in the
  team's own list (FR-501 to FR-505, SCR-10).

  ## One row, three places

  An action looks the same on the board, in the carry-over review and on the
  team list, and what changes is only which controls are beside it. Rendering
  it three times would guarantee that the status a person can set in one place
  drifts from the status they can set in another, so `action_row/1` is one
  component with slots.
  """

  use SprintLensWeb, :html

  alias SprintLens.Actions
  alias SprintLens.Actions.ActionItem

  @doc """
  The form for writing down something the team agreed to do (FR-501, FR-502).

  `topic` is the focused topic, if there is one — an action written while the
  room is looking at something keeps the link to it.
  """
  attr :members, :list, required: true
  attr :topic, :any, default: nil
  attr :form, :any, required: true

  def action_form(assigns) do
    ~H"""
    <.form for={@form} id="action-form" phx-submit="create_action" class="space-y-2">
      <input :if={@topic} type="hidden" name="action[topic]" value={@topic.key} />

      <.input
        field={@form[:title]}
        type="text"
        label={gettext("What will the team do?")}
        maxlength={ActionItem.max_title()}
        required
      />

      <div class="grid gap-2 sm:grid-cols-2">
        <.input
          field={@form[:assignee_id]}
          type="select"
          label={gettext("Owner")}
          options={[{gettext("Nobody yet"), ""} | member_options(@members)]}
        />
        <.input field={@form[:due_date]} type="date" label={gettext("Due")} />
      </div>

      <p :if={@topic} id="action-topic" class="text-sm opacity-70">
        {gettext("Linked to: %{topic}", topic: @topic.title)}
      </p>

      <.button variant="primary" class="btn btn-primary btn-sm">{gettext("Add action")}</.button>
    </.form>
    """
  end

  @doc """
  One action item, with whatever controls belong where it is being shown.
  """
  attr :action, :map, required: true
  attr :members, :list, default: []
  attr :editable, :boolean, default: false
  attr :now, :any, required: true
  slot :controls

  def action_row(assigns) do
    ~H"""
    <li
      id={"action-#{@action.id}"}
      class="flex flex-wrap items-center gap-2 rounded-box border border-base-200 p-2"
    >
      <div class="min-w-0 grow">
        <p class="break-words font-medium">{@action.title}</p>

        <p class="flex flex-wrap items-center gap-2 text-xs opacity-70">
          <span id={"action-owner-#{@action.id}"}>
            {if @action.assignee, do: @action.assignee.display_name, else: gettext("Unassigned")}
          </span>

          <span :if={@action.due_date} id={"action-due-#{@action.id}"}>
            {gettext("due %{date}", date: SprintLensWeb.Locale.format_datetime(@action.due_date))}
          </span>

          <%!--
            Overdue is a fact about an unfinished item, so it is stated rather
            than left to the reader to work out from a date (FR-506).
          --%>
          <span
            :if={Actions.overdue?(@action, @now)}
            id={"action-overdue-#{@action.id}"}
            class="badge badge-error badge-xs"
          >
            {gettext("Overdue")}
          </span>

          <span
            :if={@action.carried_from_id}
            id={"action-carried-#{@action.id}"}
            class="badge badge-ghost badge-xs"
          >
            {gettext("Carried over")}
          </span>
        </p>
      </div>

      <form
        :if={@editable}
        phx-change="update_action_status"
        id={"action-status-form-#{@action.id}"}
        class="flex items-center gap-1"
      >
        <%!--
          Named `action_id` rather than `id`: a form field called `id` shadows
          the DOM id LiveView patches by, and the change event then arrives
          for the wrong row.
        --%>
        <input type="hidden" name="action_id" value={@action.id} />
        <label for={"action-status-#{@action.id}"} class="sr-only">{gettext("Status")}</label>
        <select
          id={"action-status-#{@action.id}"}
          name="status"
          class="select select-xs"
        >
          <option
            :for={status <- ActionItem.statuses()}
            value={status}
            selected={ActionItem.status(@action) == status}
          >
            {status_label(status)}
          </option>
        </select>
      </form>

      <span
        :if={not @editable}
        id={"action-status-badge-#{@action.id}"}
        class={["badge badge-sm", status_class(ActionItem.status(@action))]}
      >
        {status_label(ActionItem.status(@action))}
      </span>

      {render_slot(@controls, @action)}
    </li>
    """
  end

  @doc """
  The carry-over review the check-in phase opens with (FR-505).

  Shown to everyone, because it is the team's list rather than the
  facilitator's, and a quick status update is something anyone in the room can
  give.
  """
  attr :actions, :list, required: true
  attr :now, :any, required: true
  attr :can_carry, :boolean, default: false

  def carry_over_review(assigns) do
    ~H"""
    <section
      id="carry-over-review"
      aria-labelledby="carry-over-heading"
      class="rounded-box border border-base-300 p-3"
    >
      <h3 id="carry-over-heading" class="font-semibold">
        {gettext("Still open from last time")}
      </h3>

      <p :if={@actions == []} id="carry-over-empty" class="mt-2 text-sm opacity-60">
        {gettext("Nothing is outstanding. Good place to start.")}
      </p>

      <ul :if={@actions != []} id="carry-over-list" class="mt-2 space-y-2">
        <.action_row :for={action <- @actions} action={action} editable={@can_carry} now={@now}>
          <:controls :let={action}>
            <.button
              :if={@can_carry}
              id={"carry-over-#{action.id}"}
              phx-click="carry_over"
              phx-value-id={action.id}
              class="btn btn-ghost btn-xs"
            >
              {gettext("Carry over")}
            </.button>
          </:controls>
        </.action_row>
      </ul>
    </section>
    """
  end

  @doc """
  The label a status is shown under.
  """
  @spec status_label(ActionItem.status() | nil) :: String.t()
  def status_label(:open), do: gettext("Open")
  def status_label(:in_progress), do: gettext("In progress")
  def status_label(:done), do: gettext("Done")
  def status_label(:dropped), do: gettext("Dropped")

  @doc """
  The options a status filter offers, with a blank one meaning "any".
  """
  @spec status_options() :: [{String.t(), String.t()}]
  def status_options do
    Enum.map(ActionItem.statuses(), &{status_label(&1), Atom.to_string(&1)})
  end

  # The badge is only rendered where the row is read-only, which is the Home
  # page, which lists only what is still open — so `done` and `dropped` never
  # reach here.
  defp status_class(:in_progress), do: "badge-info"
  defp status_class(_open), do: "badge-outline"

  defp member_options(members) do
    Enum.map(members, &{&1.display_name, &1.id})
  end
end
