defmodule SprintLens.Retro.Events do
  @moduledoc """
  The realtime contract for a live session (spec section 7.3).

  Every event name the spec lists is declared here, and broadcasting goes
  through `broadcast/3` rather than `Phoenix.PubSub` directly. That gives one
  place to be sure of three things:

    * the event names match the spec exactly, checked by a test against the
      list below;
    * order is preserved per session, which `Phoenix.PubSub` gives us because
      all events for a session go through one topic;
    * every broadcast is measured, so NFR-102's two-second budget at the 95th
      percentile is something we can see rather than assume (NFR-503).

  Payload filtering does *not* happen here. A broadcast fans out to every
  subscriber, so anything that must differ per viewer — blind mode (FR-209),
  authorship in an anonymous session (FR-210), vote totals before the reveal
  (FR-404) — is applied at the rendering edge, where the viewer is known.
  """

  alias Phoenix.PubSub

  @pubsub SprintLens.PubSub

  # Section 7.3, verbatim.
  @events ~w(
    phase.changed
    timer.updated
    card.created
    card.updated
    card.deleted
    card.moved
    group.created
    group.updated
    group.deleted
    vote.updated
    vote.revealed
    focus.changed
    note.updated
    presence.updated
    mood.updated
    action.created
    action.updated
    session.closed
  )

  @typedoc "One of the event names in section 7.3."
  @type event :: String.t()

  @doc """
  Every event name section 7.3 defines.
  """
  @spec events() :: [event()]
  def events, do: @events

  @doc """
  The broadcast topic for a session. One topic per session keeps ordering
  per session, which is all section 7.3 requires.
  """
  @spec topic(term()) :: String.t()
  def topic(session_id), do: "session:#{session_id}"

  @doc """
  Subscribes the calling process to a session's events.
  """
  @spec subscribe(term()) :: :ok | {:error, term()}
  def subscribe(session_id), do: PubSub.subscribe(@pubsub, topic(session_id))

  @doc """
  Unsubscribes the calling process.
  """
  @spec unsubscribe(term()) :: :ok
  def unsubscribe(session_id), do: PubSub.unsubscribe(@pubsub, topic(session_id))

  @doc """
  Broadcasts one of the section 7.3 events to everyone in a session.

  Raises on an event name that is not in the spec: a typo in an event name is
  otherwise a message nobody receives and nobody notices.
  """
  @spec broadcast(term(), event(), map()) :: :ok
  def broadcast(session_id, event, payload \\ %{}) when is_map(payload) do
    unless event in @events do
      raise ArgumentError,
            "#{inspect(event)} is not an event in section 7.3. Known events: #{Enum.join(@events, ", ")}"
    end

    :telemetry.span([:sprint_lens, :realtime, :broadcast], %{event: event}, fn ->
      result = PubSub.broadcast(@pubsub, topic(session_id), {:retro_event, event, payload})

      {result, %{event: event}}
    end)

    :ok
  end
end
