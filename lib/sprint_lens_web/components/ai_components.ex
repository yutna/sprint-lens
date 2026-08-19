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
    <section id={@id} class="rounded-box border border-base-300 p-3">
      <div class="flex flex-wrap items-center gap-2">
        <h3 class="grow font-semibold">{@title}</h3>

        <span :if={@status in [:queued, :running]} id={"#{@id}-working"} class="badge badge-sm">
          {gettext("Thinking...")}
        </span>

        <.button
          :if={is_nil(@suggestion) or @status in [:accepted, :rejected]}
          id={"#{@id}-request"}
          phx-click="request_suggestion"
          phx-value-type={@type}
          class="btn btn-ghost btn-xs"
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
          class="btn btn-ghost btn-xs"
        >
          {gettext("Try again")}
        </.button>
      </div>

      <p :if={@hint} class="text-sm opacity-70">{@hint}</p>

      <p :if={@status == :failed} id={"#{@id}-failed"} class="mt-2 text-sm opacity-70">
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
          class="whitespace-pre-wrap break-words rounded-box bg-base-200 p-2 text-sm"
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
            class="w-full textarea"
            aria-label={gettext("Edit the suggestion before accepting it")}
          >{@suggestion.output}</textarea>

          <div class="mt-1 flex flex-wrap gap-1">
            <.button id={"#{@id}-save"} variant="primary" class="btn btn-primary btn-xs">
              {gettext("Accept edited")}
            </.button>
            <.button
              id={"#{@id}-cancel"}
              phx-click="cancel_edit_suggestion"
              class="btn btn-ghost btn-xs"
            >
              {gettext("Cancel")}
            </.button>
          </div>
        </.form>

        <div :if={not @editing} class="flex flex-wrap gap-1">
          <.button
            id={"#{@id}-accept"}
            variant="primary"
            phx-click="accept_suggestion"
            phx-value-id={@suggestion.id}
            class="btn btn-primary btn-xs"
          >
            {gettext("Accept")}
          </.button>
          <.button
            id={"#{@id}-edit"}
            phx-click="edit_suggestion"
            phx-value-id={@suggestion.id}
            class="btn btn-ghost btn-xs"
          >
            {gettext("Edit first")}
          </.button>
          <.button
            id={"#{@id}-reject"}
            phx-click="reject_suggestion"
            phx-value-id={@suggestion.id}
            class="btn btn-ghost btn-xs"
          >
            {gettext("Reject")}
          </.button>
        </div>
      </div>

      <p :if={@status == :accepted} id={"#{@id}-accepted"} class="mt-2 text-sm opacity-70">
        {gettext("Accepted.")}
      </p>

      <p :if={@status == :rejected} id={"#{@id}-rejected"} class="mt-2 text-sm opacity-70">
        {gettext("Rejected.")}
      </p>
    </section>
    """
  end
end
