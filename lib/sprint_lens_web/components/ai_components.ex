defmodule SprintLensWeb.AIComponents do
  @moduledoc """
  The suggestion slot (AI-002, AI-005, AI-006).

  ## One slot, every feature

  A suggestion looks the same wherever it appears: a button while there is
  nothing, a spinner while a job runs, the draft with accept and reject once
  it is ready, and a retry when it failed. Rendering that four ways would
  guarantee that one of them forgets the accept step AI-002 requires, so it
  is one component and the feature only chooses the labels.

  ## Nothing renders when AI is off

  AI-001 says every feature outside section 5 works fully with AI disabled,
  and the visible half of that is this: with the switch off or the team
  opted out, the slot is not on the page at all. Not disabled, not greyed
  out — absent, so nobody wonders what they are missing.
  """

  use SprintLensWeb, :html

  alias SprintLens.AI.Suggestion

  @doc """
  A suggestion slot for one feature.

  `suggestion` is the most recent one of this type, or `nil` when nobody has
  asked yet.
  """
  attr :id, :string, required: true
  attr :type, :atom, required: true
  attr :title, :string, required: true
  attr :hint, :string, default: nil
  attr :suggestion, :any, default: nil
  attr :editing, :boolean, default: false

  def suggestion_slot(assigns) do
    assigns =
      assign(assigns, :status, assigns.suggestion && Suggestion.status(assigns.suggestion))

    ~H"""
    <section id={@id} class="space-y-2 rounded-panel border border-base-200 bg-base-100 p-4">
      <div class="flex flex-wrap items-center gap-2">
        <h3 class="grow font-semibold">{@title}</h3>

        <span
          :if={@status in [:queued, :running]}
          id={"#{@id}-working"}
          data-slot="badge"
          class="rounded-control border border-base-300 bg-base-200 px-2 py-0.5 text-caption"
        >
          {gettext("Thinking...")}
        </span>

        <.button
          :if={is_nil(@suggestion) or @status in [:accepted, :rejected]}
          id={"#{@id}-request"}
          phx-click="request_suggestion"
          phx-value-type={@type}
          variant="ghost"
          size="sm"
        >
          {gettext("Ask AI")}
        </.button>

        <%!--
          AI-006: "the suggestion slot shows a retry option". A person's
          choice, not the queue's — a job that retried itself while somebody
          waited would be indistinguishable from one that had hung.
        --%>
        <.button
          :if={@status == :failed}
          id={"#{@id}-retry"}
          phx-click="retry_suggestion"
          phx-value-id={@suggestion.id}
          variant="ghost"
          size="sm"
        >
          {gettext("Try again")}
        </.button>
      </div>

      <p :if={@hint} class="text-label text-base-content/70">{@hint}</p>

      <p :if={@status == :failed} id={"#{@id}-failed"} class="text-label text-base-content/70">
        {gettext("The assistant did not answer. Everything else still works.")}
      </p>

      <div :if={@status == :ready} class="mt-2 space-y-2">
        <%!--
          The draft, and nothing has happened to it yet. AI-002: a human
          reviews and accepts, edits or rejects; nothing is applied
          automatically.
        --%>
        <pre
          :if={not @editing}
          id={"#{@id}-draft"}
          class="rounded-card bg-base-200 p-3 text-label break-words whitespace-pre-wrap"
        >{@suggestion.output}</pre>

        <.form
          :if={@editing}
          for={to_form(%{}, as: :suggestion)}
          id={"#{@id}-form"}
          phx-submit="accept_suggestion"
        >
          <input type="hidden" name="suggestion[id]" value={@suggestion.id} />
          <textarea
            id={"#{@id}-editor"}
            name="suggestion[output]"
            rows="8"
            class="w-full rounded-control border border-base-300 bg-base-100 px-3 py-2 text-body transition-colors placeholder:text-base-content/40 hover:border-base-content/30"
            aria-label={gettext("Edit the suggestion before accepting it")}
          >{@suggestion.output}</textarea>

          <div class="mt-1 flex flex-wrap gap-1">
            <.button id={"#{@id}-save"} variant="primary" size="sm">
              {gettext("Accept edited")}
            </.button>
            <.button id={"#{@id}-cancel"} phx-click="cancel_edit_suggestion" variant="ghost" size="sm">
              {gettext("Cancel")}
            </.button>
          </div>
        </.form>

        <div :if={not @editing} class="flex flex-wrap gap-1">
          <.button
            id={"#{@id}-accept"}
            phx-click="accept_suggestion"
            phx-value-id={@suggestion.id}
            variant="primary"
            size="sm"
          >
            {gettext("Accept")}
          </.button>
          <.button
            id={"#{@id}-edit"}
            phx-click="edit_suggestion"
            phx-value-id={@suggestion.id}
            variant="ghost"
            size="sm"
          >
            {gettext("Edit first")}
          </.button>
          <.button
            id={"#{@id}-reject"}
            phx-click="reject_suggestion"
            phx-value-id={@suggestion.id}
            variant="ghost"
            size="sm"
          >
            {gettext("Reject")}
          </.button>
        </div>
      </div>

      <p :if={@status == :accepted} id={"#{@id}-accepted"} class="text-label text-base-content/70">
        {gettext("Accepted.")}
      </p>

      <p :if={@status == :rejected} id={"#{@id}-rejected"} class="text-label text-base-content/70">
        {gettext("Rejected.")}
      </p>
    </section>
    """
  end
end
