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
  alias SprintLensWeb.TemplateText

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
      class="mb-3 flex gap-1 overflow-x-auto rounded-control bg-base-200 p-1 sm:hidden"
    >
      <button
        :for={column <- @columns}
        type="button"
        role="tab"
        id={"tab-#{column.id}"}
        aria-selected={to_string(column.id == @active)}
        aria-controls={"column-#{column.id}"}
        data-slot="button"
        class={[
          "flex-1 rounded-control px-3 py-2 text-label font-medium whitespace-nowrap",
          "transition-colors duration-(--sl-duration-quick)",
          if(column.id == @active,
            do: "bg-base-100 text-base-content shadow-resting",
            else: "text-base-content/70"
          )
        ]}
        phx-click="select_column"
        phx-value-column-id={column.id}
      >
        {TemplateText.column_name(column)}
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
          "min-w-0 space-y-3 rounded-panel border border-base-200 bg-base-100 p-3",
          # One column at a time on a narrow screen (FR-902); all of them once
          # there is room.
          @column.id == @active || "hidden sm:block"
        ]
      }
    >
      <div class="space-y-0.5">
        <h3 class="font-semibold">{TemplateText.column_name(@column)}</h3>
        <p :if={@column.hint} class="text-label text-base-content/70">
          {TemplateText.column_hint(@column)}
        </p>
      </div>

      <%!--
        FR-920: the box empties the moment you submit, and fills itself back
        in if the server says no. The clearing is optimistic — the card is
        not saved yet — and the restoring is the rollback, which arrives with
        the notice the requirement asks for.
      --%>
      <.form
        :if={@can_write}
        for={to_form(%{}, as: :card)}
        id={"card-form-#{@column.id}"}
        phx-submit="create_card"
        phx-hook=".OptimisticCard"
      >
        <input type="hidden" name="card[column_id]" value={@column.id} />
        <textarea
          name="card[text]"
          rows="2"
          maxlength={Card.max_text()}
          class="w-full rounded-control border border-base-300 bg-base-100 px-3 py-2 text-body transition-colors placeholder:text-base-content/40 hover:border-base-content/30"
          aria-label={gettext("Write a card in %{column}", column: TemplateText.column_name(@column))}
          phx-hook=".CardCounter"
          id={"card-text-#{@column.id}"}
        ></textarea>
        <div class="flex items-center justify-between gap-2">
          <span
            id={"card-counter-#{@column.id}"}
            aria-live="polite"
            class="text-caption tabular-nums text-base-content/60"
          >
            0/{Card.max_text()}
          </span>
          <.button id={"add-card-#{@column.id}"} variant="primary" size="sm">
            {gettext("Add")}
          </.button>
        </div>
      </.form>

      <ul id={"cards-#{@column.id}"} class="space-y-2">
        <%!--
          `data-arrive` is only set on a board that was hidden and has just
          been shown. Everywhere else the cards are simply there, and a card
          somebody has just written should not fade in as though it were
          somebody else's secret.
        --%>
        <li
          :for={{card, index} <- Enum.with_index(@cards)}
          id={"card-#{card.id}"}
          data-arrive={revealed?(@session) || nil}
          style={revealed?(@session) && "--sl-arrive-index: #{index}"}
          class="rounded-card border border-base-200 bg-base-100 p-3 shadow-resting"
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

      <p :if={@cards == []} class="text-label text-base-content/60" id={"column-empty-#{@column.id}"}>
        {gettext("Nothing here yet.")}
      </p>
    </section>

    <script :type={Phoenix.LiveView.ColocatedHook} name=".OptimisticCard">
      export default {
        mounted() {
          this.el.addEventListener("submit", () => {
            // Optimistic: the words leave the box as soon as you commit to
            // them, so the next card can be typed while the first is saving.
            //
            // Deferred by one task on purpose. LiveView serialises the form
            // in its own submit handler, synchronously; clearing the box
            // before that runs would send an empty card, which is a much
            // worse bug than the one this is here to avoid.
            this.pending = this.textarea().value

            setTimeout(() => {
              this.textarea().value = ""
              this.textarea().dispatchEvent(new Event("input", {bubbles: true}))
            }, 0)
          })

          // Rollback: the server refused, so the words come back exactly as
          // they were, next to the flash that says why (FR-920).
          this.handleEvent("card:rejected", ({column_id, text}) => {
            if (String(column_id) !== this.columnId()) return

            this.textarea().value = text || this.pending || ""
            this.textarea().dispatchEvent(new Event("input", {bubbles: true}))
            this.textarea().focus()
          })
        },
        columnId() { return this.el.id.replace("card-form-", "") },
        textarea() { return this.el.querySelector("textarea") }
      }
    </script>

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

  # A blind board that has been revealed, which is the only situation the
  # cards are staged for.
  defp revealed?(session), do: session.is_blind and session.cards_revealed

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
      <textarea
        name="card[text]"
        rows="2"
        maxlength={Card.max_text()}
        class="w-full rounded-control border border-base-300 bg-base-100 px-3 py-2 text-body transition-colors placeholder:text-base-content/40 hover:border-base-content/30"
      >{@card.text}</textarea>
      <div class="flex gap-1">
        <.button id={"save-card-#{@card.id}"} variant="primary" size="sm">
          {gettext("Save")}
        </.button>
        <.button id={"cancel-edit-#{@card.id}"} phx-click="cancel_edit" variant="ghost" size="sm">
          {gettext("Cancel")}
        </.button>
      </div>
    </.form>

    <div :if={@editing != @card.id}>
      <p class="whitespace-pre-wrap break-words">{@card.text}</p>

      <p class="mt-1 text-caption text-base-content/60">
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
      <label :if={@can_group} class="mt-2 flex w-fit items-center gap-1.5 text-caption">
        <input
          type="checkbox"
          id={"select-card-#{@card.id}"}
          class="size-4 rounded-sm border-base-300 accent-primary"
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
          variant="ghost"
          size="sm"
        >
          {gettext("Edit")}
        </.button>

        <.button
          :if={@mine or @is_facilitator}
          id={"delete-card-#{@card.id}"}
          phx-click="delete_card"
          phx-value-id={@card.id}
          data-confirm={gettext("Delete this card?")}
          variant="ghost"
          size="sm"
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
          variant="ghost"
          size="sm"
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
    <section id="topics-panel" class="space-y-3 rounded-panel border border-base-200 bg-base-100 p-4">
      <div class="flex flex-wrap items-center gap-3">
        <h3 class="text-heading font-semibold">{gettext("Topics")}</h3>

        <%!--
          Your own budget, always (FR-403). Nobody else's, ever: one person's
          spending is not the room's business.
        --%>
        <span
          :if={@can_vote}
          id="vote-remaining"
          class="flex flex-wrap items-center gap-2 text-label"
        >
          <%!--
            The budget as a row of tokens rather than a sentence. It is a
            fixed pool spent down over the phase, and a pool is a thing you
            watch getting smaller — the number is still there in the label
            underneath, for anybody who is counting rather than glancing.
          --%>
          <span aria-hidden="true" class="flex gap-1">
            <span
              :for={token <- 1..@summary.budget//1}
              class={[
                "size-2.5 rounded-full",
                if(token <= @summary.remaining, do: "bg-primary", else: "bg-base-300")
              ]}
            ></span>
          </span>
          <span class="text-base-content/70">
            {gettext("%{remaining} of %{budget} votes left",
              remaining: @summary.remaining,
              budget: @summary.budget
            )}
          </span>
        </span>

        <span :if={not @summary.revealed} id="votes-hidden" class="text-label text-base-content/70">
          {gettext("Totals are hidden until the facilitator reveals them.")}
        </span>

        <.button
          :if={@is_facilitator and not @summary.revealed}
          id="reveal-votes"
          phx-click="reveal_votes"
          variant="primary"
          size="sm"
        >
          {gettext("Reveal totals")}
        </.button>
      </div>

      <ol id="topics" class="space-y-2">
        <li
          :for={topic <- @topics}
          id={"topic-#{Topic.dom_id(topic)}"}
          aria-current={to_string(topic.focused?)}
          class={[
            "rounded-card border p-3 transition-colors duration-(--sl-duration-base)",
            if(topic.focused?,
              do: "border-primary bg-primary/5 shadow-resting",
              else: "border-base-200"
            )
          ]}
        >
          <div class="flex flex-wrap items-start gap-2">
            <p class="grow break-words whitespace-pre-wrap">{topic.title}</p>

            <span
              :if={not is_nil(topic.votes)}
              id={"topic-total-#{Topic.dom_id(topic)}"}
              class="shrink-0 rounded-control bg-primary px-2 py-0.5 text-caption font-medium text-primary-content"
            >
              {ngettext("%{count} vote", "%{count} votes", topic.votes, count: topic.votes)}
            </span>

            <span
              :if={topic.my_votes > 0}
              id={"topic-mine-#{Topic.dom_id(topic)}"}
              class="shrink-0 rounded-control border border-base-300 bg-base-200 px-2 py-0.5 text-caption text-base-content/80"
            >
              {gettext("you: %{count}", count: topic.my_votes)}
            </span>
          </div>

          <ul :if={topic.kind == :group and topic.cards != []} class="mt-1 space-y-1 pl-3">
            <li :for={card <- topic.cards} class="text-label text-base-content/70">{card.text}</li>
          </ul>

          <p
            :if={topic.note}
            id={"topic-note-#{Topic.dom_id(topic)}"}
            class="mt-2 rounded-card bg-base-200 p-3 text-label"
          >
            {topic.note}
          </p>

          <div class="mt-2 flex flex-wrap gap-1">
            <.button
              :if={@can_vote}
              id={"vote-up-#{Topic.dom_id(topic)}"}
              phx-click="cast_vote"
              phx-value-topic={topic.key}
              variant="ghost"
              size="sm"
            >
              {gettext("Vote")}
            </.button>

            <.button
              :if={@can_vote and topic.my_votes > 0}
              id={"vote-down-#{Topic.dom_id(topic)}"}
              phx-click="retract_vote"
              phx-value-topic={topic.key}
              variant="ghost"
              size="sm"
            >
              {gettext("Take back")}
            </.button>

            <.button
              :if={@is_facilitator and not topic.focused?}
              id={"focus-#{Topic.dom_id(topic)}"}
              phx-click="set_focus"
              phx-value-topic={topic.key}
              variant="ghost"
              size="sm"
            >
              {gettext("Discuss this")}
            </.button>

            <.button
              :if={@is_facilitator and topic.focused?}
              id="clear-focus"
              phx-click="clear_focus"
              variant="ghost"
              size="sm"
            >
              {gettext("Stop discussing")}
            </.button>

            <.button
              :if={@is_facilitator and @editing_note != topic.key}
              id={"note-#{Topic.dom_id(topic)}"}
              phx-click="edit_note"
              phx-value-topic={topic.key}
              variant="ghost"
              size="sm"
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
              class="w-full rounded-control border border-base-300 bg-base-100 px-3 py-2 text-body transition-colors placeholder:text-base-content/40 hover:border-base-content/30"
              aria-label={gettext("Discussion note")}
            >{topic.note}</textarea>
            <div class="flex gap-1">
              <.button
                id={"save-note-#{Topic.dom_id(topic)}"}
                variant="primary"
                size="sm"
              >
                {gettext("Save")}
              </.button>
              <.button id="cancel-note" phx-click="cancel_note" variant="ghost" size="sm">
                {gettext("Cancel")}
              </.button>
            </div>
          </.form>
        </li>
      </ol>

      <p :if={@topics == []} id="topics-empty" class="text-label text-base-content/60">
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
      class="space-y-3 rounded-panel border border-base-200 bg-base-100 p-4"
    >
      <h3 class="text-heading font-semibold">{@prompt}</h3>

      <div :if={@open} class="flex flex-wrap gap-2" role="group" aria-label={@prompt}>
        <.button
          :for={score <- 1..5}
          id={"#{@kind}-score-#{score}"}
          phx-click="record_mood"
          phx-value-kind={@kind}
          phx-value-score={score}
          aria-pressed={to_string(@mine && @mine.score == score)}
          variant={if @mine && @mine.score == score, do: "primary", else: nil}
          class="w-11 justify-center tabular-nums"
        >
          {score}
        </.button>
      </div>

      <%!--
        Only the aggregate is ever shown; the individual answers exist so a
        person can change their own (FR-211).
      --%>
      <p class="text-label text-base-content/70" id={"mood-summary-#{@kind}"}>
        <span :if={@summary.count == 0}>{gettext("No answers yet.")}</span>
        <span :if={@summary.count > 0}>
          {gettext("Average %{average} from %{count} people",
            average: @summary.average,
            count: @summary.count
          )}
        </span>
      </p>

      <ul :if={@summary.words != []} class="flex flex-wrap gap-1.5">
        <li
          :for={word <- @summary.words}
          class="rounded-control border border-base-300 px-2 py-0.5 text-caption"
        >
          {word}
        </li>
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
    <div
      id="icebreaker"
      class="flex items-start gap-3 rounded-panel border border-base-200 bg-base-200/60 p-4"
    >
      <.icon name="hero-chat-bubble-left-right" class="mt-0.5 size-5 shrink-0 text-base-content/50" />
      <p class="min-w-0">
        <span class="block text-caption font-semibold tracking-wide text-base-content/60 uppercase">
          {gettext("Icebreaker")}
        </span>
        <%!--
          The opening move rather than a footnote: it is the first thing the
          room is asked, and it was set in small grey type under a border.
        --%>
        <span class="text-heading">{icebreaker_for(@session)}</span>
      </p>
    </div>
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
