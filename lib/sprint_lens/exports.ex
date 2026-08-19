defmodule SprintLens.Exports do
  @moduledoc """
  Taking a finished retrospective out of the app: markdown, CSV and JSON
  (FR-701, FR-702, FR-703).

  ## Pure by design

  Every function here takes the recap map `SprintLens.Insights.recap/2`
  already built and returns a string. Nothing reads the database and nothing
  checks a permission — the caller has already been through
  `Insights.fetch_closed_session/2`, which is where "closed, and yours to
  read" is decided. That keeps the formats testable as what they are: string
  transformations with fiddly edge cases.

  ## The CSV edge case that is a security question

  A spreadsheet treats a cell beginning with `=`, `+`, `-` or `@` as a
  formula, so a card reading `=HYPERLINK("http://evil","click")` becomes a
  live link when a colleague opens the export. Card text is written by people
  and is therefore attacker-controlled by definition, so those cells get a
  leading apostrophe — the standard mitigation, and the reason
  `escape_formula/1` exists.

  Line endings are CRLF because RFC 4180 says so and because Excel on Windows
  is the single most likely thing to open this file.
  """

  alias SprintLens.Actions.ActionItem
  alias SprintLens.Retro.Topic

  @type format :: :markdown | :csv | :json
  @type subject :: :cards | :actions

  @formats [:markdown, :csv, :json]
  @subjects [:cards, :actions]

  @doc """
  The formats a recap can be taken out in (§7.2).
  """
  @spec formats() :: [format()]
  def formats, do: @formats

  @doc """
  Reads a format name from a parameter, or `:error`.
  """
  @spec parse_format(String.t() | nil) :: {:ok, format()} | :error
  def parse_format(nil), do: {:ok, :markdown}
  def parse_format("md"), do: {:ok, :markdown}
  def parse_format(name), do: parse(name, @formats)

  @doc """
  Reads which CSV is wanted: the cards or the action items (FR-702).
  """
  @spec parse_subject(String.t() | nil) :: {:ok, subject()} | :error
  def parse_subject(nil), do: {:ok, :cards}
  def parse_subject(name), do: parse(name, @subjects)

  @doc """
  Renders a recap in one format, returning the body, its content type and the
  filename a browser should save it under.
  """
  @spec render(map(), format(), subject()) ::
          %{body: String.t(), content_type: String.t(), filename: String.t()}
  def render(recap, format, subject \\ :cards)

  def render(recap, :markdown, _subject) do
    %{
      body: markdown(recap),
      content_type: "text/markdown; charset=utf-8",
      filename: filename(recap, "md")
    }
  end

  def render(recap, :csv, subject) do
    %{
      body: csv(recap, subject),
      content_type: "text/csv; charset=utf-8",
      filename: filename(recap, "#{subject}.csv")
    }
  end

  def render(recap, :json, _subject) do
    %{
      body: json(recap),
      content_type: "application/json; charset=utf-8",
      filename: filename(recap, "json")
    }
  end

  @doc """
  The recap as a markdown document (FR-701).

  Written to be read: headings for the parts of the session, the board as
  lists under its column names, and the vote totals beside the topics they
  belong to.
  """
  @spec markdown(map()) :: String.t()
  def markdown(recap) do
    session = recap.session

    [
      "# #{session.title}",
      "",
      metadata_lines(recap),
      "",
      "## Board",
      "",
      Enum.map(recap.columns, &markdown_column(&1, recap)),
      "## Discussion",
      "",
      markdown_topics(recap),
      "## Actions",
      "",
      markdown_actions(recap)
    ]
    |> List.flatten()
    |> Enum.join("\n")
    |> String.trim_trailing()
    |> Kernel.<>("\n")
  end

  @doc """
  The cards or the action items as CSV (FR-702).
  """
  @spec csv(map(), subject()) :: String.t()
  def csv(recap, :cards) do
    rows =
      for column <- recap.columns,
          card <- Enum.filter(recap.cards, &(&1.column_id == column.id)) do
        [
          to_string(card.id),
          column.name,
          card.text,
          author_name(card, recap.session),
          timestamp(card.inserted_at)
        ]
      end

    encode([~w(id column text author created_at) | rows])
  end

  def csv(recap, :actions) do
    rows =
      for action <- recap.actions do
        [
          to_string(action.id),
          action.title,
          action.description || "",
          action.status,
          assignee_name(action),
          timestamp(action.due_date),
          timestamp(action.inserted_at)
        ]
      end

    encode([~w(id title description status assignee due_date created_at) | rows])
  end

  @doc """
  The whole session as JSON: everything in the recap plus its metadata
  (FR-703).
  """
  @spec json(map()) :: String.t()
  def json(recap) do
    session = recap.session

    Jason.encode!(
      %{
        exported_at: DateTime.utc_now(),
        session: %{
          id: session.id,
          title: session.title,
          team_id: session.team_id,
          closed_at: session.closed_at,
          is_anonymous: session.is_anonymous,
          is_blind: session.is_blind,
          vote_budget: session.vote_budget,
          multi_vote: session.multi_vote,
          participant_count: recap.participant_count
        },
        columns: Enum.map(recap.columns, &%{id: &1.id, name: &1.name, position: &1.position}),
        cards: Enum.map(recap.cards, &json_card(&1, session)),
        topics: Enum.map(recap.topics, &json_topic/1),
        notes: Enum.map(recap.notes, &json_note/1),
        actions: Enum.map(recap.actions, &json_action/1),
        mood: recap.mood,
        roti: recap.roti
      },
      pretty: true
    )
  end

  ## Markdown pieces

  defp metadata_lines(recap) do
    session = recap.session

    [
      "- Closed: #{timestamp(session.closed_at)}",
      "- Took part: #{recap.participant_count}",
      "- Mood: #{score(recap.mood)}",
      "- ROTI: #{score(recap.roti)}",
      if(session.is_anonymous, do: "- Anonymous: authorship was not recorded", else: nil)
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp markdown_column(column, recap) do
    cards = Enum.filter(recap.cards, &(&1.column_id == column.id))

    ["### #{column.name}", "" | markdown_cards(cards, recap.session)] ++ [""]
  end

  defp markdown_cards([], _session), do: ["_Nothing in this column._"]

  defp markdown_cards(cards, session) do
    Enum.map(cards, fn card ->
      case author_name(card, session) do
        "" -> "- #{one_line(card.text)}"
        name -> "- #{one_line(card.text)} — #{name}"
      end
    end)
  end

  defp markdown_topics(%{topics: []}), do: ["_Nothing was discussed._", ""]

  defp markdown_topics(recap) do
    Enum.flat_map(recap.topics, fn topic ->
      votes = "#{topic.votes || 0} vote(s)"

      [
        "### #{one_line(topic.title)} (#{votes})",
        "",
        topic.note && "> #{one_line(topic.note)}",
        topic.note && "",
        topic.kind == :group && Enum.map(topic.cards, &"- #{one_line(&1.text)}"),
        topic.kind == :group && "",
        ""
      ]
      |> List.flatten()
      |> Enum.reject(&(&1 in [nil, false]))
    end)
  end

  defp markdown_actions(%{actions: []}), do: ["_Nothing was agreed._", ""]

  defp markdown_actions(recap) do
    Enum.map(recap.actions, fn action ->
      parts =
        [
          one_line(action.title),
          "status: #{action.status}",
          assignee_name(action) != "" && "owner: #{assignee_name(action)}",
          action.due_date && "due: #{timestamp(action.due_date)}"
        ]
        |> Enum.reject(&(&1 in [nil, false]))

      "- " <> Enum.join(parts, " · ")
    end)
  end

  ## JSON pieces

  defp json_card(card, session) do
    base = %{
      id: card.id,
      column_id: card.column_id,
      card_group_id: card.card_group_id,
      text: card.text,
      position: card.position,
      created_at: card.inserted_at
    }

    if session.is_anonymous, do: base, else: Map.put(base, :author, author_name(card, session))
  end

  defp json_topic(%Topic{} = topic) do
    %{
      key: topic.key,
      kind: Atom.to_string(topic.kind),
      title: topic.title,
      votes: topic.votes,
      note: topic.note,
      card_ids: Enum.map(topic.cards, & &1.id)
    }
  end

  defp json_note(note) do
    {:ok, ref} = Topic.from_ids(note.card_id, note.card_group_id)

    %{id: note.id, topic: Topic.key(ref), body: note.body}
  end

  defp json_action(%ActionItem{} = action) do
    %{
      id: action.id,
      title: action.title,
      description: action.description,
      status: action.status,
      due_date: action.due_date,
      assignee: assignee_name(action),
      carried_from_id: action.carried_from_id,
      created_at: action.inserted_at
    }
  end

  ## CSV

  # RFC 4180: CRLF between records, quotes doubled inside a quoted field.
  defp encode(rows) do
    rows
    |> Enum.map_join("\r\n", fn row -> Enum.map_join(row, ",", &cell/1) end)
    |> Kernel.<>("\r\n")
  end

  defp cell(value) do
    escaped = value |> to_string() |> escape_formula()

    if String.contains?(escaped, [",", "\"", "\n", "\r"]) do
      ~s("#{String.replace(escaped, "\"", "\"\"")}")
    else
      escaped
    end
  end

  # A spreadsheet runs a cell that starts with one of these. Card text comes
  # from people, so it gets the standard leading apostrophe rather than the
  # benefit of the doubt.
  defp escape_formula(<<first::utf8, _rest::binary>> = value)
       when first in [?=, ?+, ?-, ?@, ?\t, ?\r] do
    "'" <> value
  end

  defp escape_formula(value), do: value

  ## Shared

  defp parse(name, allowed) do
    case Enum.find(allowed, &(Atom.to_string(&1) == name)) do
      nil -> :error
      found -> {:ok, found}
    end
  end

  defp filename(recap, extension) do
    # Marks (`\p{M}`) are kept as well as letters and numbers: Thai vowel
    # signs and tone marks are marks, not letters, and dropping them turns
    # "รีโทร" into "รโทร" — a filename nobody would recognise (FR-906).
    slug =
      recap.session.title
      |> String.downcase()
      |> String.replace(~r/[^\p{L}\p{N}\p{M}]+/u, "-")
      |> String.trim("-")

    "#{slug}-#{recap.session.id}.#{extension}"
  end

  # An anonymous session has no authorship to render: the references were
  # destroyed when it closed (section 6.4), so this is a fact about the data
  # rather than a filter that could be forgotten.
  defp author_name(card, session) do
    if session.is_anonymous or is_nil(card.author), do: "", else: card.author.display_name
  end

  defp assignee_name(%ActionItem{assignee: %{display_name: name}}), do: name
  defp assignee_name(_action), do: ""

  defp timestamp(nil), do: ""
  defp timestamp(%DateTime{} = at), do: DateTime.to_iso8601(at)

  defp score(%{count: 0}), do: "—"
  defp score(%{average: average}), do: to_string(average)

  # Newlines inside a card would break the list item they are rendered in.
  defp one_line(text), do: String.replace(text, ~r/\s*\n\s*/, " ")
end
