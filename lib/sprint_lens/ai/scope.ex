defmodule SprintLens.AI.Scope do
  @moduledoc """
  What each kind of AI job is allowed to be told (AI-015, AI-016).

  ## Authorship is never sent, for any session

  AI-016 says authorship "MUST never be sent for anonymous sessions, and
  SHOULD be omitted for all AI jobs". Taking the SHOULD deletes a branch: if
  the builder never carries a name, there is no anonymous case to get wrong,
  no flag to check, and no way for a future feature to reintroduce one by
  forgetting. A model that is summarising a retrospective does not need to
  know who said what.

  ## Nothing is assembled anywhere else

  Every job's input comes from `build/2` and nothing else calls the adapter
  directly, so AI-015's "only the content needed for the task" is one
  function to read rather than six call sites to audit. The test for it reads
  the *encoded* scope back looking for every name in the session.
  """

  import Ecto.Query, warn: false

  alias SprintLens.Admin
  alias SprintLens.AI.Suggestion
  alias SprintLens.Insights
  alias SprintLens.Retro.Board
  alias SprintLens.Retro.Session
  alias SprintLens.Teams.Team

  @typedoc """
  The `input_scope` of §5.2's envelope: what kinds of thing were sent.
  """
  @type scope :: [String.t()]

  @doc """
  Assembles a job's input, and says what went into it.

  `opts` carries whatever a particular feature needs beyond the session —
  the focused topic for an action draft, the text for a translation.
  """
  @spec build(Suggestion.type(), map()) :: {:ok, map(), scope()} | {:error, :not_found}
  def build(type, context)

  def build(:session_summary, %{session: %Session{} = session}) do
    {:ok,
     %{
       title: session.title,
       language: language(session),
       cards: cards(session),
       groups: groups(session),
       votes: votes(session),
       notes: notes(session)
     }, ~w(cards groups votes notes)}
  end

  def build(:clustering, %{session: %Session{} = session}) do
    {:ok, %{title: session.title, cards: cards(session)}, ~w(cards)}
  end

  def build(:action_draft, %{session: %Session{} = session} = context) do
    {:ok,
     %{
       topic: context[:topic] || "",
       note: context[:note] || "",
       cards: cards(session)
     }, ~w(cards notes)}
  end

  def build(:recurring_themes, %{team: %Team{} = team}) do
    sessions =
      for entry <- Insights.archive(team) do
        %{
          session_id: entry.session.id,
          title: entry.session.title,
          closed_at: entry.closed_at,
          cards: cards(entry.session)
        }
      end

    {:ok, %{team: team.name, sessions: sessions}, ~w(recaps)}
  end

  # Nothing about the team goes with this one, not even its name: an
  # icebreaker is a generic question in a language, and sending less is
  # always the stronger answer to AI-015.
  def build(:icebreakers, %{} = context) do
    {:ok, %{language: context[:language] || "th"}, ~w()}
  end

  def build(:translation, %{text: text} = context) when is_binary(text) and text != "" do
    {:ok, %{text: text, to: context[:language] || "en"}, ~w(text)}
  end

  def build(_type, _context), do: {:error, :not_found}

  @doc """
  How big the input is, for the operations log (AI-017).

  Measured rather than stored: the size is a fact about the request that is
  useful when something is slow, and it is the only thing about the content
  that gets recorded anywhere.
  """
  @spec size(map()) :: non_neg_integer()
  def size(input), do: input |> Jason.encode!() |> byte_size()

  ## Content, without anybody's name

  defp cards(%Session{} = session) do
    # Deliberately built by hand rather than by serialising the struct: a
    # `Map.take` would start carrying `author_id` the day somebody adds it to
    # the list, and this way there is nothing to add it to (AI-016).
    for card <- Board.list_cards(session) do
      %{id: card.id, column_id: card.column_id, text: card.text, group_id: card.card_group_id}
    end
  end

  defp groups(%Session{} = session) do
    for group <- Board.list_groups(session) do
      %{id: group.id, label: group.label, card_ids: Enum.map(group.cards, & &1.id)}
    end
  end

  defp votes(%Session{} = session) do
    for topic <- Board.topics(session, nil) do
      %{topic: topic.key, title: topic.title, votes: topic.votes || 0}
    end
  end

  defp notes(%Session{} = session) do
    for note <- Board.list_notes(session) do
      %{id: note.id, body: note.body}
    end
  end

  # AI-009 asks for the summary "in the session's language". A session has no
  # language of its own; the organisation's default is the closest thing, and
  # it is what every other default in the app comes from (FR-802).
  defp language(%Session{}), do: Admin.settings().default_language
end
