defmodule SprintLensWeb.RoomComponents do
  @moduledoc """
  The things the room watches while it works: where it is, how long it has,
  and who is in it (FR-206, FR-208, FR-213, FR-915).

  These are the parts of the board that are true in every phase, which is why
  they are together and separate from the cards. `SprintLensWeb.BoardComponents`
  owns what the team writes; this owns the frame around it.
  """

  use SprintLensWeb, :html

  alias SprintLens.Retro.Session

  @doc """
  Where the retrospective is, out of the six places it goes (FR-206).

  ## Why this is a stepper and not a row of badges

  It rendered as six equal badges with the current one filled in, which says
  "one of these is selected" — the shape of a filter. A retrospective is a
  sequence: three of those six are behind you and cannot be returned to by
  accident, one is now, and two are ahead. Numbering them is not decoration
  here; the order *is* the information, and a participant who has never done
  this before reads "4 of 6" and knows how much is left.

  The facilitator's steps are buttons, because they may jump. Everyone else
  gets the same shape without the affordance, rather than a different
  component that will drift.

  `aria-live` is on the region so a phase change is announced once rather than
  read as six separate changes, and `aria-current="true"` marks the active
  step — the selector two suites use to find it.
  """
  attr :phase, :atom, required: true
  attr :session, :map, required: true
  attr :is_facilitator, :boolean, required: true

  def phase_stepper(assigns) do
    assigns =
      assigns
      |> assign(:steps, steps(assigns.phase))
      |> assign(:steerable?, assigns.is_facilitator and Session.state(assigns.session) == :active)

    ~H"""
    <section
      id="phase-bar"
      aria-live="polite"
      aria-label={gettext("Phase")}
      class="space-y-3 rounded-panel border border-base-200 bg-base-100 p-4"
    >
      <div class="flex flex-wrap items-center gap-x-4 gap-y-2">
        <%!--
          The strip scrolls itself. Six labels do not fit across a phone, and
          the document is not allowed to scroll sideways (FR-905).
        --%>
        <ol class="-mx-1 flex flex-1 items-center gap-1 overflow-x-auto px-1">
          <li :for={step <- @steps} class="flex shrink-0 items-center">
            <.step step={step} steerable?={@steerable?} />

            <%!-- A rule between steps, so the six read as one line rather than six chips. --%>
            <span
              :if={not step.last?}
              aria-hidden="true"
              class={[
                "mx-1 h-px w-4",
                if(step.done?, do: "bg-primary/40", else: "bg-base-300")
              ]}
            ></span>
          </li>
        </ol>

        <div :if={@steerable?} class="flex shrink-0 gap-1">
          <.button id="revert-phase" phx-click="revert_phase" variant="ghost" size="sm">
            {gettext("Back")}
          </.button>
          <.button id="advance-phase" phx-click="advance_phase" variant="primary" size="sm">
            {gettext("Next")}
          </.button>
        </div>
      </div>

      <%!--
        What this phase is for, in one sentence. The six names are jargon to
        anybody who has not run a retrospective before, and "Group" on its own
        does not tell them what to do next.
      --%>
      <p id="phase-goal" class="text-label text-base-content/70">
        {phase_goal(@phase)}
      </p>
    </section>
    """
  end

  attr :step, :map, required: true
  attr :steerable?, :boolean, required: true

  defp step(assigns) do
    ~H"""
    <button
      :if={@steerable?}
      type="button"
      id={"phase-#{@step.phase}"}
      aria-current={to_string(@step.here?)}
      phx-click="set_phase"
      phx-value-phase={@step.phase}
      data-slot="button"
      class={["cursor-pointer", step_class(@step)]}
    >
      <.marker step={@step} />
      {phase_label(@step.phase)}
    </button>

    <span
      :if={not @steerable?}
      aria-current={to_string(@step.here?)}
      class={step_class(@step)}
    >
      <.marker step={@step} />
      {phase_label(@step.phase)}
    </span>
    """
  end

  attr :step, :map, required: true

  defp marker(assigns) do
    ~H"""
    <span
      aria-hidden="true"
      class={[
        "grid size-5 shrink-0 place-items-center rounded-full text-caption font-semibold",
        cond do
          @step.done? -> "bg-primary/15 text-primary-content"
          @step.here? -> "bg-primary-content/20 text-primary-content"
          true -> "bg-base-300 text-base-content/70"
        end
      ]}
    >
      <.icon :if={@step.done?} name="hero-check-micro" class="size-3.5 text-base-content" />
      <span :if={not @step.done?}>{@step.number}</span>
    </span>
    """
  end

  @doc """
  The four sounds, and the one element that plays them (FR-921).

  ## What decides whether anything is heard

  The server does. A person who has not turned sound on is never sent the
  event, so there is nothing for the browser to suppress and no way for a
  preference to be out of date on a page that has been open all afternoon.

  Rendered only when the preference is on, which is also why there is no
  `muted` state to get wrong: if the element is on the page, the person asked
  for it.

  ## Never two at once

  The plan's rule, and the reason this is one `<audio>` element rather than
  four. Playing a new sound rewinds and repoints the same element, so a vote
  landing while the reveal is still ringing cuts the reveal off rather than
  stacking on top of it.
  """
  attr :enabled, :boolean, required: true

  def sound_player(assigns) do
    ~H"""
    <audio
      :if={@enabled}
      id="sound-player"
      phx-hook=".Sounds"
      preload="auto"
      aria-hidden="true"
      class="hidden"
    ></audio>

    <script :type={Phoenix.LiveView.ColocatedHook} name=".Sounds">
      export default {
        mounted() {
          this.handleEvent("sound", ({name}) => {
            if (!name) return

            // One element, so a second sound replaces the first rather than
            // playing over it. `pause` before repointing, or Safari keeps
            // decoding the old source.
            this.el.pause()
            this.el.src = `/sounds/${name}.mp3`
            this.el.currentTime = 0

            // A browser that has not seen a user gesture yet refuses to play,
            // and says so by rejecting. That is not an error worth reporting:
            // the person has lost a chime, not their work.
            this.el.play().catch(() => {})
          })
        }
      }
    </script>
    """
  end

  @doc """
  The countdown the whole room is watching (FR-208).
  """
  attr :timer, :map, required: true
  attr :is_facilitator, :boolean, required: true
  attr :expired, :boolean, default: false

  def timer_panel(assigns) do
    ~H"""
    <section
      id="timer"
      aria-live="polite"
      aria-label={gettext("Timer")}
      class="space-y-3 rounded-panel border border-base-200 bg-base-100 p-4"
    >
      <%!--
        The dash on its own was the whole panel when no timer was running: a
        number with nothing saying what it counts.
      --%>
      <p class="text-caption font-medium tracking-wide text-base-content/60 uppercase">
        {gettext("Timer")}
      </p>
      <%!--
        The number counts down in the browser.
        
        It did not before: `remaining_s` is worked out on the server when the
        board renders, and the board renders when something happens — so a
        five-minute timer showed "5:00" until somebody wrote a card. Nobody
        noticed because the value is right every time anything checks it.

        Which also means there was no moment of expiry, so FR-915's promise
        that expiry is announced had nothing to announce and the sound this
        commit adds would have had nothing to play on. The ticker is what
        makes both true.
      --%>
      <p
        id="timer-remaining"
        phx-hook=".Ticker"
        data-remaining={@timer.remaining_s}
        data-running={to_string(@timer.running)}
        class="font-mono text-title tabular-nums"
      >
        {format_remaining(@timer.remaining_s)}
      </p>

      <p :if={@expired} id="timer-expired" class="text-label font-medium text-error">
        {gettext("Time is up.")}
      </p>

      <div :if={@is_facilitator} class="flex flex-wrap gap-1">
        <.button
          :for={{label, seconds} <- timer_presets()}
          id={"timer-#{seconds}"}
          phx-click="start_timer"
          phx-value-seconds={seconds}
          variant="ghost"
          size="sm"
        >
          {label}
        </.button>
        <.button id="pause-timer" phx-click="pause_timer" variant="ghost" size="sm">
          {gettext("Pause")}
        </.button>
        <.button id="reset-timer" phx-click="reset_timer" variant="ghost" size="sm">
          {gettext("Reset")}
        </.button>
      </div>
    </section>

    <script :type={Phoenix.LiveView.ColocatedHook} name=".Ticker">
      export default {
        mounted() { this.restart() },
        updated() { this.restart() },
        destroyed() { clearInterval(this.handle) },

        restart() {
          clearInterval(this.handle)

          this.left = parseInt(this.el.dataset.remaining, 10)
          if (this.el.dataset.running !== "true" || !(this.left > 0)) return

          this.handle = setInterval(() => {
            this.left -= 1
            this.el.textContent = this.clock(this.left)

            if (this.left <= 0) {
              clearInterval(this.handle)
              // Told once, by each browser for its own person: the sound and
              // the announcement both belong to whoever is watching, not to
              // whoever happened to start it.
              this.pushEvent("timer_expired", {})
            }
          }, 1000)
        },

        clock(seconds) {
          const rest = seconds % 60
          return `${Math.floor(seconds / 60)}:${String(rest).padStart(2, "0")}`
        }
      }
    </script>
    """
  end

  @doc """
  Who is in the room, and how many of them are ready (FR-213).
  """
  attr :session, :map, required: true
  attr :participants, :list, required: true
  attr :present_count, :integer, required: true
  attr :ready_count, :integer, required: true
  attr :ready, :boolean, required: true
  attr :is_facilitator, :boolean, required: true

  def presence_panel(assigns) do
    ~H"""
    <section
      id="presence"
      aria-label={gettext("Who is here")}
      class="space-y-3 rounded-panel border border-base-200 bg-base-100 p-4"
    >
      <p id="ready-count" class="text-label text-base-content/70">
        {gettext("%{ready} of %{total} ready", ready: @ready_count, total: @present_count)}
      </p>

      <ul class="space-y-1.5">
        <li
          :for={{user_id, meta} <- @participants}
          id={"participant-#{user_id}"}
          class="flex flex-wrap items-center gap-2"
        >
          <%!--
            The dot is a second reading of what the badge already says, not
            the only one: a colour on its own is not a state (FR-913).
          --%>
          <span
            aria-hidden="true"
            class={[
              "size-2 shrink-0 rounded-full",
              if(meta[:ready], do: "bg-success", else: "bg-base-300")
            ]}
          ></span>
          <span class="min-w-0 grow truncate text-label">{meta[:display_name]}</span>
          <.badge :if={meta[:ready]} tone="success">{gettext("Ready")}</.badge>
          <.badge :if={user_id == @session.facilitator_id} tone="primary">
            {gettext("Facilitator")}
          </.badge>
          <.button
            :if={@is_facilitator and user_id != @session.facilitator_id}
            id={"hand-over-#{user_id}"}
            phx-click="transfer_facilitator"
            phx-value-user-id={user_id}
            variant="ghost"
            size="sm"
          >
            {gettext("Hand over")}
          </.button>
        </li>
      </ul>

      <.button
        :if={Session.state(@session) == :active}
        id="toggle-ready"
        phx-click="toggle_ready"
        variant={if @ready, do: nil, else: "primary"}
        aria-pressed={to_string(@ready)}
        class="w-full"
      >
        {if @ready, do: gettext("Not ready"), else: gettext("I am ready")}
      </.button>
    </section>
    """
  end

  defp steps(current) do
    phases = Session.phases()
    at = Enum.find_index(phases, &(&1 == current))
    last = length(phases) - 1

    for {phase, index} <- Enum.with_index(phases) do
      %{
        phase: phase,
        number: index + 1,
        done?: index < at,
        here?: phase == current,
        last?: index == last
      }
    end
  end

  defp step_class(step) do
    [
      "flex items-center gap-1.5 rounded-control px-2 py-1.5 text-label whitespace-nowrap",
      "transition-colors duration-(--sl-duration-quick)",
      cond do
        step.here? -> "bg-primary font-semibold text-primary-content"
        step.done? -> "text-base-content"
        true -> "text-base-content/60"
      end
    ]
  end

  @doc """
  The name a phase goes by.
  """
  @spec phase_label(Session.phase()) :: String.t()
  def phase_label(:checkin), do: gettext("Check-in")
  def phase_label(:brainstorm), do: gettext("Brainstorm")
  def phase_label(:group), do: gettext("Group")
  def phase_label(:vote), do: gettext("Vote")
  def phase_label(:discuss), do: gettext("Discuss")
  def phase_label(:wrapup), do: gettext("Wrap-up")

  # Written for somebody who has never sat in one of these. The name of a
  # phase is jargon; the sentence is the instruction.
  defp phase_goal(:checkin) do
    gettext("Arrive, say how the sprint felt, and pick up what is still open from last time.")
  end

  defp phase_goal(:brainstorm) do
    gettext("Write down what you noticed. One thought per card, no discussion yet.")
  end

  defp phase_goal(:group) do
    gettext("Put the cards that are about the same thing together, and name the pile.")
  end

  defp phase_goal(:vote) do
    gettext("Spend your votes on what is worth the room's time.")
  end

  defp phase_goal(:discuss) do
    gettext("Take the topics in turn, and write down anything the team agrees to do.")
  end

  defp phase_goal(:wrapup) do
    gettext("Check the actions have owners, and say whether this was time well spent.")
  end

  # A dash rather than `0:00` when no timer is running: zero seconds left is a
  # different thing from nobody having started one.
  defp format_remaining(nil), do: "—"

  defp format_remaining(seconds) do
    minutes = div(seconds, 60)
    rest = rem(seconds, 60)

    "#{minutes}:#{String.pad_leading(Integer.to_string(rest), 2, "0")}"
  end

  defp timer_presets do
    [{gettext("1 min"), 60}, {gettext("5 min"), 300}, {gettext("10 min"), 600}]
  end
end
