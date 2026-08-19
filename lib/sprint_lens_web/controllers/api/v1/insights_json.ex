defmodule SprintLensWeb.Api.V1.InsightsJSON do
  @moduledoc """
  Serialises the archive, the recap, search results and the dashboard (§7.2).

  A recap of an anonymous session has no authorship to serialise: the
  references were destroyed when it closed, so the omission here is a
  consequence of the data rather than a filter that could be forgotten
  (FR-210, NFR-304).
  """

  alias SprintLens.Retro.Card
  alias SprintLens.Retro.DiscussionNote
  alias SprintLens.Retro.Topic
  alias SprintLensWeb.Api.V1.ActionJSON
  alias SprintLensWeb.Api.V1.CardJSON

  @doc """
  One row of the archive (FR-601).
  """
  @spec archive_entry(map()) :: map()
  def archive_entry(entry) do
    %{
      session_id: entry.session.id,
      title: entry.session.title,
      closed_at: entry.closed_at,
      template: entry.template,
      is_anonymous: entry.session.is_anonymous,
      participant_count: entry.participant_count,
      card_count: entry.card_count,
      mood_average: entry.mood,
      roti_average: entry.roti
    }
  end

  @doc """
  A closed session's recap (FR-602).
  """
  @spec recap(map()) :: map()
  def recap(recap) do
    %{
      session_id: recap.session.id,
      title: recap.session.title,
      closed_at: recap.session.closed_at,
      is_anonymous: recap.session.is_anonymous,
      participant_count: recap.participant_count,
      columns: Enum.map(recap.columns, &%{id: &1.id, name: &1.name, position: &1.position}),
      cards: Enum.map(recap.cards, &CardJSON.card(&1, recap.session)),
      topics: Enum.map(recap.topics, &topic/1),
      notes: Enum.map(recap.notes, &note/1),
      actions: Enum.map(recap.actions, &ActionJSON.action/1),
      mood: recap.mood,
      roti: recap.roti
    }
  end

  @doc """
  What a search found (FR-603).
  """
  @spec results(map()) :: map()
  def results(results) do
    %{
      query: results.query,
      cards: Enum.map(results.cards, &found_card/1),
      notes: Enum.map(results.notes, &note/1),
      actions: Enum.map(results.actions, &ActionJSON.action/1)
    }
  end

  @doc """
  A team's dashboard numbers (FR-604).
  """
  @spec metrics(map()) :: map()
  def metrics(metrics), do: metrics

  defp topic(%Topic{} = topic) do
    %{
      key: topic.key,
      title: topic.title,
      votes: topic.votes,
      note: topic.note,
      card_ids: Enum.map(topic.cards, & &1.id)
    }
  end

  defp note(%DiscussionNote{} = note) do
    %{
      id: note.id,
      session_id: note.session_id,
      topic: note.card_id |> Topic.from_ids(note.card_group_id) |> key(),
      body: note.body
    }
  end

  defp found_card(%Card{} = card) do
    %{
      id: card.id,
      text: card.text,
      session_id: card.column.session_id,
      session_title: card.column.session.title,
      column_name: card.column.name
    }
  end

  defp key({:ok, ref}), do: Topic.key(ref)
end
