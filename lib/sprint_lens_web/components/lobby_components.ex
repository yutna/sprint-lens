defmodule SprintLensWeb.LobbyComponents do
  @moduledoc """
  The room before it starts (SCR-07, FR-204, FR-213).

  ## Why this is its own screen

  A session that has not started rendered the whole board — six phase badges,
  every empty column, the timer controls — with a Start button in the corner.
  Everything on it was either inert or a lie: the columns had nothing in them,
  the phase bar pointed at a phase nobody was in, and the ready toggle, which
  is the one thing a person waiting actually wants, was hidden until after the
  session began.

  So the pre-start state gets a screen of its own. It has four jobs, and
  nothing else:

    * say the code out loud — large enough to read across a video call, with
      the whole link one tap away for the people in the chat;
    * fill up visibly, so arriving feels like other people arriving;
    * let a participant say they are ready, which is the only thing they can
      usefully do before the facilitator begins;
    * tell the facilitator when the room is ready, and let them start.

  The board takes over the moment the session does. `Session.state/1` is the
  switch, and the two are mutually exclusive — which is what lets this screen
  reuse `join-code`, `participant-*` and `toggle-ready` rather than inventing
  a second vocabulary for the same things.
  """

  use SprintLensWeb, :html

  alias SprintLensWeb.TemplateText

  @doc """
  The waiting room.
  """
  attr :session, :map, required: true
  attr :columns, :list, required: true
  attr :participants, :list, required: true
  attr :present_count, :integer, required: true
  attr :ready_count, :integer, required: true
  attr :ready, :boolean, required: true
  attr :is_facilitator, :boolean, required: true
  attr :join_url, :string, required: true

  def lobby(assigns) do
    assigns = assign(assigns, :room_ready?, room_ready?(assigns))

    ~H"""
    <div id="lobby" class="mx-auto grid w-full max-w-3xl gap-6">
      <.code_card code={@session.join_code} join_url={@join_url} />

      <.panel id="lobby-room" title={gettext("Who is here")}>
        <:subtitle>
          {gettext("%{ready} of %{total} ready", ready: @ready_count, total: @present_count)}
        </:subtitle>

        <ul class="grid gap-2 sm:grid-cols-2">
          <li
            :for={{user_id, meta} <- @participants}
            id={"participant-#{user_id}"}
            class="flex flex-wrap items-center gap-2 rounded-card border border-base-200 bg-base-100 p-3"
          >
            <.avatar name={meta[:display_name]} class="size-8 text-caption" />
            <span class="min-w-0 grow truncate font-medium">{meta[:display_name]}</span>

            <%!--
              Ready is said in words as well as marked with a dot. A colour on
              its own is not a state anybody can read (FR-913).
            --%>
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

        <%!--
          Only ever seen by the first person in, and only for as long as they
          are the only one. It is the one moment the room is genuinely empty.
        --%>
        <.empty_state
          :if={@present_count <= 1}
          id="lobby-waiting"
          pose="waiting"
          title={gettext("Nobody else yet.")}
          class="[&_svg]:size-16"
        >
          {gettext("Read the code out, or send the link. People appear here as they arrive.")}
        </.empty_state>
      </.panel>

      <.panel id="lobby-format" title={gettext("What this one is")}>
        <%!--
          The columns, in the order the board will lay them out. Someone who
          has never done this before now knows what they are about to be asked
          for, which is the question the check-in phase cannot answer for them.
        --%>
        <ol class="flex flex-wrap gap-2">
          <li
            :for={column <- @columns}
            class="rounded-control border border-base-300 px-3 py-1.5 text-label"
          >
            {TemplateText.column_name(column)}
          </li>
        </ol>

        <%!--
          A sentence rather than a bordered row. With no anonymous or blind
          badge to keep it company, a lone line of text inside a panel border
          reads as an empty input box waiting to be filled in.
        --%>
        <p class="flex flex-wrap items-center gap-2 text-label text-base-content/70">
          <span>
            {ngettext("%{count} vote each", "%{count} votes each", @session.vote_budget,
              count: @session.vote_budget
            )}
          </span>
          <.badge :if={@session.is_anonymous}>{gettext("Anonymous")}</.badge>
          <.badge :if={@session.is_blind}>{gettext("Cards hidden until revealed")}</.badge>
        </p>
      </.panel>

      <%!--
        The actions sit at the right in both roles. `justify-between` put a
        participant's single button on the left, where it read as left over
        rather than as the thing to do.
      --%>
      <div class="flex flex-wrap items-center justify-end gap-3 border-t border-base-200 pt-6">
        <p :if={@is_facilitator} id="lobby-cue" class="mr-auto text-label text-base-content/70">
          {facilitator_cue(@room_ready?, @present_count)}
        </p>

        <div class="flex flex-wrap items-center gap-3">
          <%!--
            The one thing a participant can do while waiting, so it is the
            primary control rather than a small toggle in a side panel.
          --%>
          <%!--
            Primary for a participant, for whom it is the only thing on the
            screen to do. Not for the facilitator, who has Start beside it —
            two primary buttons side by side is two of neither.
          --%>
          <.button
            id="toggle-ready"
            phx-click="toggle_ready"
            variant={if @ready or @is_facilitator, do: nil, else: "primary"}
            aria-pressed={to_string(@ready)}
          >
            {if @ready, do: gettext("Not ready"), else: gettext("I am ready")}
          </.button>

          <.button
            :if={@is_facilitator}
            id="start-session"
            variant="primary"
            phx-click="start"
            data-room-ready={to_string(@room_ready?)}
            class={@room_ready? && "ring-2 ring-primary/40 ring-offset-2 ring-offset-base-200"}
          >
            {gettext("Start the retrospective")}
          </.button>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  The join code, at the size of something read aloud.
  """
  attr :code, :string, required: true
  attr :join_url, :string, required: true

  def code_card(assigns) do
    ~H"""
    <div class="rounded-room border border-base-200 bg-base-100 p-6 text-center shadow-resting sm:p-10">
      <p id="lobby-code-label" class="text-label text-base-content/70">
        {gettext("Join code")}
      </p>

      <%!--
        Spaced with letter-spacing rather than with spaces in the text: the
        code has to stay copyable and comparable to what someone types, and a
        code that reads back as "A K 7 P 2 M" is a support ticket.

        `aria-label` spells it out, because a screen reader saying "akseven"
        helps nobody read it to a room.
      --%>
      <p
        id="join-code"
        class="mt-1 font-mono text-display font-semibold tracking-[0.25em] uppercase"
        aria-labelledby="lobby-code-label"
        aria-label={spelled_out(@code)}
      >
        {@code}
      </p>

      <div class="mt-5 flex flex-col items-center gap-2">
        <button
          type="button"
          id="copy-join-link"
          data-slot="button"
          phx-hook=".CopyLink"
          data-url={@join_url}
          class="inline-flex cursor-pointer items-center gap-2 rounded-control bg-base-200 px-4 py-2.5 text-label font-medium transition-colors hover:bg-base-300"
        >
          <.icon name="hero-link" class="size-4" />
          <span data-copy="idle">{gettext("Copy the link")}</span>
          <span data-copy="done" hidden>{gettext("Copied")}</span>
        </button>

        <%!--
          The link in full, and selectable. The clipboard is unavailable over
          plain HTTP on anything but localhost, which is exactly the setup a
          team self-hosting on their own network is most likely to have.
        --%>
        <p id="join-link" class="text-caption break-all text-base-content/60 select-all">
          {@join_url}
        </p>
      </div>

      <span id="copy-status" role="status" class="sr-only"></span>
    </div>

    <script :type={Phoenix.LiveView.ColocatedHook} name=".CopyLink">
      export default {
        mounted() {
          this.el.addEventListener("click", async () => {
            try {
              await navigator.clipboard.writeText(this.el.dataset.url)
              this.confirm()
            } catch {
              // No clipboard: select the link instead, so the next keystroke
              // is a copy rather than a dead end.
              const link = document.getElementById("join-link")
              if (!link) return
              const range = document.createRange()
              range.selectNodeContents(link)
              const selection = window.getSelection()
              selection.removeAllRanges()
              selection.addRange(range)
            }
          })
        },
        confirm() {
          const idle = this.el.querySelector('[data-copy="idle"]')
          const done = this.el.querySelector('[data-copy="done"]')
          const status = document.getElementById("copy-status")

          idle.hidden = true
          done.hidden = false
          if (status) status.textContent = done.textContent

          clearTimeout(this.timer)
          this.timer = setTimeout(() => {
            idle.hidden = false
            done.hidden = true
            if (status) status.textContent = ""
          }, 2000)
        },
        destroyed() { clearTimeout(this.timer) }
      }
    </script>
    """
  end

  # One person in the room is the person who opened it, so "everyone is ready"
  # is not a useful thing to say about them.
  defp room_ready?(%{present_count: total, ready_count: ready}) do
    total > 1 and ready == total
  end

  defp facilitator_cue(true, _present), do: gettext("Everyone is ready.")

  defp facilitator_cue(false, present) when present <= 1 do
    gettext("You can start whenever you like — people can join after it begins.")
  end

  defp facilitator_cue(false, _present), do: gettext("Still waiting on a few.")

  # A code read one character at a time. Screen readers pronounce a short
  # string of letters and digits as a word, and a word cannot be typed back.
  defp spelled_out(code) do
    code |> String.graphemes() |> Enum.join(" ")
  end
end
