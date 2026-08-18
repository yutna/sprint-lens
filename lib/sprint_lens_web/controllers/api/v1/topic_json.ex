defmodule SprintLensWeb.Api.V1.TopicJSON do
  @moduledoc """
  Serialises topics, the focused one, and discussion notes (§7.2).

  `votes` is `null` — present but empty — until the facilitator reveals
  (FR-404). Omitting the key would say "this session has no totals"; `null`
  says "not yet", which is what a client needs to render the difference.
  """

  alias SprintLens.Retro.DiscussionNote
  alias SprintLens.Retro.Session
  alias SprintLens.Retro.Topic

  @doc """
  One topic, as the caller is allowed to see it.
  """
  @spec topic(Topic.t()) :: map()
  def topic(%Topic{} = topic) do
    %{
      key: topic.key,
      kind: Atom.to_string(topic.kind),
      id: topic.id,
      title: topic.title,
      card_ids: Enum.map(topic.cards, & &1.id),
      votes: topic.votes,
      my_votes: topic.my_votes,
      note: topic.note,
      focused: topic.focused?,
      created_at: topic.created_at
    }
  end

  @doc """
  The session's focused topic, or `null` when the spotlight is empty
  (FR-406).
  """
  @spec focus(Session.t()) :: map()
  def focus(%Session{} = session) do
    %{topic: session |> Session.focus() |> key(), timer_s: session.timer_duration_s}
  end

  @doc """
  A discussion note and the topic it belongs to (FR-407).
  """
  @spec note(DiscussionNote.t(), Topic.ref() | String.t()) :: map()
  def note(%DiscussionNote{} = note, topic) do
    {:ok, ref} = Topic.parse(topic)

    %{topic: Topic.key(ref), body: note.body, updated_at: note.updated_at}
  end

  defp key(nil), do: nil
  defp key(ref), do: Topic.key(ref)
end
