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

      <p :if={@topic} id="action-topic" class="text-label text-base-content/70">
        {gettext("Linked to: %{topic}", topic: @topic.title)}
      </p>

      <.button variant="primary" size="sm">{gettext("Add action")}</.button>
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
      class="flex flex-wrap items-center gap-2 rounded-card border border-base-200 p-3"
    >
      <div class="min-w-0 grow">
        <p class="break-words font-medium">{@action.title}</p>

        <p class="flex flex-wrap items-center gap-2 text-caption text-base-content/70">
          <span id={"action-owner-#{@action.id}"}>
            {if @action.assignee, do: @action.assignee.display_name, else: gettext("Unassigned")}
          </span>

          <%!--
            A date, not a datetime. The field is filled by a `type="date"`
            input, so whatever time of day is stored with it is an artefact of
            how it got there — and "due 19 Aug 2026 08:27" invites someone to
            believe the 08:27 means something.
          --%>
          <span :if={@action.due_date} id={"action-due-#{@action.id}"}>
            {gettext("due %{date}",
              date: SprintLensWeb.Locale.format_date(DateTime.to_date(@action.due_date))
            )}
          </span>

          <%!--
            Overdue is a fact about an unfinished item, so it is stated rather
            than left to the reader to work out from a date (FR-506).
          --%>
          <.badge
            :if={Actions.overdue?(@action, @now)}
            id={"action-overdue-#{@action.id}"}
            tone="danger"
          >
            {gettext("Overdue")}
          </.badge>

          <.badge :if={@action.carried_from_id} id={"action-carried-#{@action.id}"}>
            {gettext("Carried over")}
          </.badge>
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
          data-slot="control"
          class="rounded-control border border-base-300 bg-base-100 px-2 py-1.5 text-label"
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

      <.badge
        :if={not @editable}
        id={"action-status-badge-#{@action.id}"}
        tone={status_tone(ActionItem.status(@action))}
      >
        {status_label(ActionItem.status(@action))}
      </.badge>

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
      class="rounded-panel border border-base-200 bg-base-100 p-4"
    >
      <h3 id="carry-over-heading" class="font-semibold">
        {gettext("Still open from last time")}
      </h3>

      <p :if={@actions == []} id="carry-over-empty" class="mt-2 text-label text-base-content/60">
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
              variant="ghost"
              size="sm"
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
  defp status_tone(:in_progress), do: "info"
  defp status_tone(_open), do: "neutral"

  defp member_options(members) do
    Enum.map(members, &{&1.display_name, &1.id})
  end
end
