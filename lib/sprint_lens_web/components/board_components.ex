defmodule SprintLensWeb.BoardComponents do
  @moduledoc """
  The board's own pieces: columns, cards, and the controls for moving them.

  ## Mobile is not a smaller desktop

  FR-902 asks for one column at a time on a narrow screen with a clear
  indicator of which is active, and FR-905 forbids the page scrolling
  sideways. Both are handled here by rendering *one* column list and letting
  CSS decide how many are on screen, rather than by shipping two boards and
  hoping they stay in step.

  ## Every drag has a tap

  FR-903 requires a tap-based equivalent for drag and drop, and FR-914 wants
  every action reachable from the keyboard. So the card's move controls are
  real `<button>`s in the markup — the drag handle is an enhancement on top of
  them, not the only way through.
  """

  use SprintLensWeb, :html

  alias SprintLens.Retro.Card
  alias SprintLens.Retro.DiscussionNote
  alias SprintLens.Retro.Session
  alias SprintLens.Retro.Topic

  @doc """
  The column tabs a narrow screen uses to move between columns (FR-902).
  """
  attr :columns, :list, required: true
  attr :active, :any, required: true

  def column_tabs(assigns) do
    ~H"""
    <div
      id="column-tabs"
      role="tablist"
      aria-label={gettext("Columns")}
      class="tabs tabs-box mb-3 flex sm:hidden"
    >
      <button
        :for={column <- @columns}
        type="button"
        role="tab"
        id={"tab-#{column.id}"}
        aria-selected={to_string(column.id == @active)}
        aria-controls={"column-#{column.id}"}
        class={["tab flex-1", column.id == @active && "tab-active"]}
        phx-click="select_column"
        phx-value-column-id={column.id}
      >
        {column.name}
      </button>
    </div>
    """
  end

  @doc """
  One column of the board, with its cards and its writing box.
  """
  attr :column, :map, required: true
  attr :cards, :list, required: true
  attr :session, :map, required: true
  attr :active, :any, required: true
  attr :can_write, :boolean, default: false
  attr :can_move, :boolean, default: false
  attr :columns, :list, required: true
  attr :current_user_id, :any, required: true
  attr :is_facilitator, :boolean, default: false
  attr :editing, :any, default: nil
  attr :can_group, :boolean, default: false
  attr :selected, :any, default: nil

  def board_column(assigns) do
    ~H"""
    <section
      id={"column-#{@column.id}"}
      role="tabpanel"
      aria-labelledby={"tab-#{@column.id}"}
      class={
        [
          "min-w-0 rounded-box border border-base-300 p-3",
          # One column at a time on a narrow screen (FR-902); all of them once
          # there is room.
          @column.id == @active || "hidden sm:block"
        ]
      }
    >
      <h3 class="font-semibold">{@column.name}</h3>
      <p :if={@column.hint} class="mb-2 text-sm opacity-70">{@column.hint}</p>

      <.form
        :if={@can_write}
        for={to_form(%{}, as: :card)}
        id={"card-form-#{@column.id}"}
        phx-submit="create_card"
      >
        <input type="hidden" name="card[column_id]" value={@column.id} />
        <textarea
          name="card[text]"
          rows="2"
          maxlength={Card.max_text()}
          class="w-full textarea"
          aria-label={gettext("Write a card in %{column}", column: @column.name)}
          phx-hook=".CardCounter"
          id={"card-text-#{@column.id}"}
        ></textarea>
        <div class="flex items-center justify-between gap-2">
          <span class="text-xs opacity-60" id={"card-counter-#{@column.id}"} aria-live="polite">
            0/{Card.max_text()}
          </span>
          <.button id={"add-card-#{@column.id}"} variant="primary" class="btn btn-primary btn-xs">
            {gettext("Add")}
          </.button>
        </div>
      </.form>

      <ul id={"cards-#{@column.id}"} class="mt-3 space-y-2">
        <li
          :for={card <- @cards}
          id={"card-#{card.id}"}
          class="rounded-box border border-base-200 bg-base-100 p-2"
        >
          <.card_body
            card={card}
            session={@session}
            columns={@columns}
            can_move={@can_move}
            current_user_id={@current_user_id}
            is_facilitator={@is_facilitator}
            editing={@editing}
            can_group={@can_group}
            selected={@selected}
          />
        </li>
      </ul>

      <p :if={@cards == []} class="mt-3 text-sm opacity-60" id={"column-empty-#{@column.id}"}>
        {gettext("Nothing here yet.")}
      </p>
    </section>

    <script :type={Phoenix.LiveView.ColocatedHook} name=".CardCounter">
      export default {
        mounted() { this.update() },
        updated() { this.update() },
        update() {
          const counter = document.getElementById(this.el.id.replace("card-text-", "card-counter-"))
          if (!counter) return
          const render = () => counter.textContent = `${this.el.value.length}/${this.el.maxLength}`
          render()
          this.el.addEventListener("input", render)
        }
      }
    </script>
    """
  end

  @doc """
  One card: its text, who wrote it, and what can be done with it.
  """
  attr :card, :map, required: true
  attr :session, :map, required: true
  attr :columns, :list, required: true
  attr :can_move, :boolean, default: false
  attr :current_user_id, :any, required: true
  attr :is_facilitator, :boolean, default: false
  attr :editing, :any, default: nil
  attr :can_group, :boolean, default: false
  attr :selected, :any, default: nil

  def card_body(assigns) do
    assigns = assign(assigns, :mine, assigns.card.author_id == assigns.current_user_id)

    ~H"""
    <.form
      :if={@editing == @card.id}
      for={to_form(%{}, as: :card)}
      id={"edit-card-#{@card.id}"}
      phx-submit="update_card"
    >
      <input type="hidden" name="card[id]" value={@card.id} />
      <textarea name="card[text]" rows="2" maxlength={Card.max_text()} class="w-full textarea">{@card.text}</textarea>
      <div class="flex gap-1">
        <.button id={"save-card-#{@card.id}"} variant="primary" class="btn btn-primary btn-xs">
          {gettext("Save")}
        </.button>
        <.button
          id={"cancel-edit-#{@card.id}"}
          phx-click="cancel_edit"
          class="btn btn-ghost btn-xs"
        >
          {gettext("Cancel")}
        </.button>
      </div>
    </.form>

    <div :if={@editing != @card.id}>
      <p class="whitespace-pre-wrap break-words">{@card.text}</p>

      <p class="mt-1 text-xs opacity-60">
        <%!--
          Authorship is never shown in an anonymous session — not to the
          facilitator, not to an Org Admin (FR-210).
        --%>
        <span :if={not @session.is_anonymous and @card.author}>{@card.author.display_name}</span>
        <span :if={@session.is_anonymous}>{gettext("Anonymous")}</span>
      </p>

      <%!--
        Merging is choosing *which* cards belong together (FR-304), so the
        cards have to be selectable. A real checkbox, so it is reachable by
        keyboard and announced as what it is (FR-914).
      --%>
      <label :if={@can_group} class="mt-1 flex w-fit items-center gap-1 text-xs">
        <input
          type="checkbox"
          id={"select-card-#{@card.id}"}
          class="checkbox checkbox-xs"
          checked={@selected && MapSet.member?(@selected, @card.id)}
          phx-click="toggle_card"
          phx-value-id={@card.id}
        />
        {gettext("Merge this")}
      </label>

      <div class="mt-1 flex flex-wrap gap-1">
        <.button
          :if={@mine}
          id={"edit-card-button-#{@card.id}"}
          phx-click="edit_card"
          phx-value-id={@card.id}
          class="btn btn-ghost btn-xs"
        >
          {gettext("Edit")}
        </.button>

        <.button
          :if={@mine or @is_facilitator}
          id={"delete-card-#{@card.id}"}
          phx-click="delete_card"
          phx-value-id={@card.id}
          data-confirm={gettext("Delete this card?")}
          class="btn btn-ghost btn-xs"
        >
          {gettext("Delete")}
        </.button>

        <%!--
          The tap-based equivalent of dragging (FR-903), and the keyboard path
          to the same thing (FR-914). Rendered as real buttons rather than as
          a fallback that only appears without a pointer.
        --%>
        <.button
          :for={target <- Enum.reject(@columns, &(&1.id == @card.column_id))}
          :if={@can_move}
          id={"move-card-#{@card.id}-to-#{target.id}"}
          phx-click="move_card"
          phx-value-id={@card.id}
          phx-value-column-id={target.id}
          class="btn btn-ghost btn-xs"
        >
          {gettext("→ %{column}", column: target.name)}
        </.button>
      </div>
    </div>
    """
  end

  @doc """
  The vote and discuss phases: topics, budgets, the spotlight and the record
  (FR-403 to FR-408).

  One panel for both phases, because they are two views of the same list. What
  changes is what you can do to it — spend votes, or follow the facilitator.
  """
  attr :topics, :list, required: true
  attr :summary, :map, required: true
  attr :phase, :atom, required: true
  attr :can_vote, :boolean, default: false
  attr :is_facilitator, :boolean, default: false
  attr :editing_note, :any, default: nil

  def topics_panel(assigns) do
    ~H"""
    <section id="topics-panel" class="rounded-box border border-base-300 p-3">
      <div class="flex flex-wrap items-center gap-2">
        <h3 class="font-semibold">{gettext("Topics")}</h3>

        <%!--
          Your own budget, always (FR-403). Nobody else's, ever: one person's
          spending is not the room's business.
        --%>
        <span :if={@can_vote} id="vote-remaining" class="badge badge-outline">
          {gettext("%{remaining} of %{budget} votes left",
            remaining: @summary.remaining,
            budget: @summary.budget
          )}
        </span>

        <span :if={not @summary.revealed} id="votes-hidden" class="text-sm opacity-70">
          {gettext("Totals are hidden until the facilitator reveals them.")}
        </span>

        <.button
          :if={@is_facilitator and not @summary.revealed}
          id="reveal-votes"
          variant="primary"
          phx-click="reveal_votes"
          class="btn btn-primary btn-xs"
        >
          {gettext("Reveal totals")}
        </.button>
      </div>

      <ol id="topics" class="mt-3 space-y-2">
        <li
          :for={topic <- @topics}
          id={"topic-#{Topic.dom_id(topic)}"}
          aria-current={to_string(topic.focused?)}
          class={[
            "rounded-box border p-2",
            if(topic.focused?, do: "border-primary bg-primary/5", else: "border-base-200")
          ]}
        >
          <div class="flex flex-wrap items-start gap-2">
            <p class="grow whitespace-pre-wrap break-words">{topic.title}</p>

            <span
              :if={not is_nil(topic.votes)}
              id={"topic-total-#{Topic.dom_id(topic)}"}
              class="badge badge-primary badge-sm"
            >
              {ngettext("%{count} vote", "%{count} votes", topic.votes, count: topic.votes)}
            </span>

            <span
              :if={topic.my_votes > 0}
              id={"topic-mine-#{Topic.dom_id(topic)}"}
              class="badge badge-sm"
            >
              {gettext("you: %{count}", count: topic.my_votes)}
            </span>
          </div>

          <ul :if={topic.kind == :group and topic.cards != []} class="mt-1 space-y-1 pl-3">
            <li :for={card <- topic.cards} class="text-sm opacity-70">{card.text}</li>
          </ul>

          <p
            :if={topic.note}
            id={"topic-note-#{Topic.dom_id(topic)}"}
            class="mt-2 rounded-box bg-base-200 p-2 text-sm"
          >
            {topic.note}
          </p>

          <div class="mt-2 flex flex-wrap gap-1">
            <.button
              :if={@can_vote}
              id={"vote-up-#{Topic.dom_id(topic)}"}
              phx-click="cast_vote"
              phx-value-topic={topic.key}
              class="btn btn-ghost btn-xs"
            >
              {gettext("Vote")}
            </.button>

            <.button
              :if={@can_vote and topic.my_votes > 0}
              id={"vote-down-#{Topic.dom_id(topic)}"}
              phx-click="retract_vote"
              phx-value-topic={topic.key}
              class="btn btn-ghost btn-xs"
            >
              {gettext("Take back")}
            </.button>

            <.button
              :if={@is_facilitator and not topic.focused?}
              id={"focus-#{Topic.dom_id(topic)}"}
              phx-click="set_focus"
              phx-value-topic={topic.key}
              class="btn btn-ghost btn-xs"
            >
              {gettext("Discuss this")}
            </.button>

            <.button
              :if={@is_facilitator and topic.focused?}
              id="clear-focus"
              phx-click="clear_focus"
              class="btn btn-ghost btn-xs"
            >
              {gettext("Stop discussing")}
            </.button>

            <.button
              :if={@is_facilitator and @editing_note != topic.key}
              id={"note-#{Topic.dom_id(topic)}"}
              phx-click="edit_note"
              phx-value-topic={topic.key}
              class="btn btn-ghost btn-xs"
            >
              {if topic.note, do: gettext("Edit note"), else: gettext("Add note")}
            </.button>
          </div>

          <.form
            :if={@editing_note == topic.key}
            for={to_form(%{}, as: :note)}
            id={"note-form-#{Topic.dom_id(topic)}"}
            phx-submit="save_note"
            class="mt-2"
          >
            <input type="hidden" name="note[topic]" value={topic.key} />
            <textarea
              id={"note-body-#{Topic.dom_id(topic)}"}
              name="note[body]"
              rows="2"
              maxlength={DiscussionNote.max_body()}
              class="w-full textarea"
              aria-label={gettext("Discussion note")}
            >{topic.note}</textarea>
            <div class="flex gap-1">
              <.button
                id={"save-note-#{Topic.dom_id(topic)}"}
                variant="primary"
                class="btn btn-primary btn-xs"
              >
                {gettext("Save")}
              </.button>
              <.button id="cancel-note" phx-click="cancel_note" class="btn btn-ghost btn-xs">
                {gettext("Cancel")}
              </.button>
            </div>
          </.form>
        </li>
      </ol>

      <p :if={@topics == []} id="topics-empty" class="mt-2 text-sm opacity-60">
        {gettext("There is nothing on the board to discuss yet.")}
      </p>
    </section>
    """
  end

  @doc """
  The check-in mood question, and the aggregate everyone sees (FR-211).
  """
  attr :summary, :map, required: true
  attr :mine, :any, default: nil
  attr :kind, :atom, required: true
  attr :prompt, :string, required: true
  attr :open, :boolean, default: true

  def mood_panel(assigns) do
    ~H"""
    <section
      id={"mood-#{@kind}"}
      aria-label={@prompt}
      class="rounded-box border border-base-300 p-3"
    >
      <h3 class="font-semibold">{@prompt}</h3>

      <div :if={@open} class="mt-2 flex gap-1" role="group" aria-label={@prompt}>
        <.button
          :for={score <- 1..5}
          id={"#{@kind}-score-#{score}"}
          phx-click="record_mood"
          phx-value-kind={@kind}
          phx-value-score={score}
          aria-pressed={to_string(@mine && @mine.score == score)}
          class={["btn btn-sm", @mine && @mine.score == score && "btn-primary"]}
        >
          {score}
        </.button>
      </div>

      <%!--
        Only the aggregate is ever shown; the individual answers exist so a
        person can change their own (FR-211).
      --%>
      <p class="mt-2 text-sm opacity-70" id={"mood-summary-#{@kind}"}>
        <span :if={@summary.count == 0}>{gettext("No answers yet.")}</span>
        <span :if={@summary.count > 0}>
          {gettext("Average %{average} from %{count} people",
            average: @summary.average,
            count: @summary.count
          )}
        </span>
      </p>

      <ul :if={@summary.words != []} class="mt-1 flex flex-wrap gap-1">
        <li :for={word <- @summary.words} class="badge badge-outline badge-sm">{word}</li>
      </ul>
    </section>
    """
  end

  @doc """
  An icebreaker prompt for the check-in (FR-212).

  Drawn from a built-in bank rather than generated: the AI module is optional
  and everything outside it must work with AI switched off (AI-001).
  """
  attr :session, :map, required: true

  def icebreaker(assigns) do
    ~H"""
    <p id="icebreaker" class="rounded-box border border-base-300 p-3 text-sm">
      <span class="font-semibold">{gettext("Icebreaker")}:</span>
      {icebreaker_for(@session)}
    </p>
    """
  end

  @doc """
  The built-in icebreaker bank (FR-212).
  """
  @spec icebreakers() :: [String.t()]
  def icebreakers do
    [
      gettext("What is one thing that made you smile this sprint?"),
      gettext("If this sprint were weather, what would it be?"),
      gettext("What is one thing you learned that you did not expect?"),
      gettext("Which teammate helped you most this sprint?"),
      gettext("What would you tell the team from two weeks ago?")
    ]
  end

  # Chosen from the session id rather than at random, so everyone in the same
  # session sees the same prompt and a reload does not change it.
  defp icebreaker_for(%Session{id: id}) do
    bank = icebreakers()

    Enum.at(bank, rem(id, length(bank)))
  end
end
