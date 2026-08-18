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
  alias SprintLens.Retro.Session

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
