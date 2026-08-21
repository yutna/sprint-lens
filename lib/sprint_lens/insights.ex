defmodule SprintLens.Insights do
  @moduledoc """
  Looking back: the archive, the recap, search, and the numbers a team can
  draw a line through (FR-601 to FR-606).

  ## Everything here reads; nothing here writes

  A retrospective's history is made by the sessions themselves. This context
  only assembles what already happened, which is why it takes no idempotency
  keys, broadcasts no events, and has no `Ecto.Multi` anywhere in it.

  ## Why search is `LIKE` and not FTS5

  SQLite's FTS5 would be the obvious choice, and it is the wrong one here.
  Its tokenizers — `unicode61`, `porter`, `ascii` — all split words on
  whitespace and punctuation. Thai is written without spaces between words,
  and Thai is this app's default language (FR-906), so an FTS5 index would
  store a whole Thai sentence as a single token and searching for a word
  inside it would find nothing. A substring match is worse at ranking English
  and is the only one of the two that works at all in Thai.

  What that costs is a full scan per search, which for a team's own history —
  a few sessions a month — is not a cost anybody will notice.

  ## What an Org Admin may see (FR-605)

  Org-wide numbers are aggregates over teams: how many sessions, how the
  moods averaged, how many actions got finished. No card text and no person
  ever appears, which is why `org_metrics/1` builds its own result rather than
  mapping over `team_metrics/1` and hoping nothing personal came along.
  """

  import Ecto.Query, warn: false

  alias SprintLens.Accounts.Scope
  alias SprintLens.Accounts.User
  alias SprintLens.Actions
  alias SprintLens.Actions.ActionItem
  alias SprintLens.Policy
  alias SprintLens.Repo
  alias SprintLens.Retro
  alias SprintLens.Retro.Board
  alias SprintLens.Retro.Card
  alias SprintLens.Retro.Column
  alias SprintLens.Retro.DiscussionNote
  alias SprintLens.Retro.MoodEntry
  alias SprintLens.Retro.Session
  alias SprintLens.Teams
  alias SprintLens.Teams.Team

  @doc """
  The team's closed sessions, most recent first, with what the archive shows
  about each: when it happened, which template it used, how many people took
  part, and how the room felt (FR-601).

  The mood summaries come from one grouped query rather than one per row: an
  archive is the page most likely to have a long list on it.
  """
  @spec archive(Team.t()) :: [map()]
  def archive(%Team{} = team) do
    sessions =
      Repo.all(
        from s in Session,
          where: s.team_id == ^team.id and s.state == "closed",
          order_by: [desc: s.closed_at, desc: s.id],
          preload: [:template]
      )

    moods = mood_averages(Enum.map(sessions, & &1.id))
    cards = card_counts(Enum.map(sessions, & &1.id))

    Enum.map(sessions, fn session ->
      %{
        session: session,
        closed_at: session.closed_at,
        template: session.template && session.template.name,
        # Beside the name rather than instead of it: `template` is also a
        # field of the archive's JSON representation, and an external caller
        # should keep getting the stored value. The flag is what lets the
        # interface translate the product's own wording without touching a
        # team's (FR-906, FR-909).
        template_builtin?: !!(session.template && session.template.is_builtin),
        participant_count: session.participant_count || 0,
        card_count: Map.get(cards, session.id, 0),
        mood: Map.get(moods, {session.id, :checkin_mood}),
        roti: Map.get(moods, {session.id, :roti})
      }
    end)
  end

  @doc """
  Everything a closed session's recap page shows (FR-602, FR-215).

  Assembled from the same functions the live board uses, so the recap cannot
  drift from what people saw at the time. Vote totals are visible because
  closing reveals them (see `SprintLens.Retro.close_session/2`), and
  authorship is absent for an anonymous session because it no longer exists in
  the database at all.
  """
  @spec recap(Session.t(), User.t() | Scope.t() | nil) :: map()
  def recap(%Session{} = session, actor \\ nil) do
    %{
      session: session,
      columns: session.columns,
      cards: Board.list_cards(session),
      topics: Board.topics(session, actor),
      notes: Board.list_notes(session),
      actions: Actions.list_session_actions(session),
      mood: Board.mood_summary(session, :checkin_mood),
      roti: Board.mood_summary(session, :roti),
      participant_count: session.participant_count || 0
    }
  end

  @doc """
  Searches a team's past cards, discussion notes and action items (FR-603).

  Only closed sessions are searched. "Past" is the word FR-603 uses, and it
  keeps the promises the live board makes: a card hidden by blind mode
  (FR-209) must not be findable through a search box while the session is
  still running.
  """
  @spec search(User.t() | Scope.t() | nil, Team.t(), String.t() | nil) ::
          {:ok, map()} | {:error, :unauthorized | :empty_query}
  def search(actor, %Team{} = team, query) do
    with :ok <- authorize_member(actor, team),
         {:ok, pattern} <- pattern(query) do
      {:ok,
       %{
         query: String.trim(query),
         cards: search_cards(team, pattern),
         notes: search_notes(team, pattern),
         actions: search_actions(team, pattern)
       }}
    end
  end

  @doc """
  The numbers behind a team's dashboard (FR-604, FR-506).

  Trends are per-session series rather than single numbers: "mood trend across
  sessions" is a line, and a line needs its points. The action figures come
  from `SprintLens.Actions.stats/2` rather than being recomputed, so the
  dashboard and the action list can never disagree.
  """
  @spec team_metrics(User.t() | Scope.t() | nil, Team.t()) ::
          {:ok, map()} | {:error, :unauthorized}
  def team_metrics(actor, %Team{} = team) do
    with :ok <- authorize_member(actor, team) do
      sessions = closed_sessions(team)
      ids = Enum.map(sessions, & &1.id)
      moods = mood_averages(ids)
      cards = card_counts(ids)
      members = length(Teams.list_members(team))

      {:ok,
       %{
         session_count: length(sessions),
         member_count: members,
         mood_trend: trend(sessions, &Map.get(moods, {&1.id, :checkin_mood})),
         roti_trend: trend(sessions, &Map.get(moods, {&1.id, :roti})),
         cards_per_session: trend(sessions, &Map.get(cards, &1.id, 0)),
         participation: trend(sessions, &participation_rate(&1, members)),
         actions: Actions.stats(team)
       }}
    end
  end

  @doc """
  The org-wide view (FR-605).

  Aggregates over teams and nothing else: no card text, no note, no name, no
  per-person anything. An Org Admin gets to know whether retrospectives are
  working across the organisation, not what was said in them.
  """
  @spec org_metrics(User.t() | Scope.t() | nil) :: {:ok, map()} | {:error, :unauthorized}
  def org_metrics(actor) do
    if Policy.can?(actor, :view_org_insights) do
      teams = Repo.all(from t in Team, order_by: [asc: t.name])

      {:ok,
       %{
         team_count: length(teams),
         teams: Enum.map(teams, &team_totals/1),
         totals: org_totals(teams)
       }}
    else
      {:error, :unauthorized}
    end
  end

  ## Internals

  defp closed_sessions(%Team{} = team) do
    Repo.all(
      from s in Session,
        where: s.team_id == ^team.id and s.state == "closed",
        order_by: [asc: s.closed_at, asc: s.id]
    )
  end

  # `nil` where there is no answer rather than zero: a session nobody rated is
  # a gap in the line, not a session everybody hated.
  defp trend(sessions, value_fun) do
    Enum.map(sessions, fn session ->
      %{
        session_id: session.id,
        title: session.title,
        closed_at: session.closed_at,
        value: value_fun.(session)
      }
    end)
  end

  # `members` is at least one: reaching this function means the caller is a
  # member of the team, so there is no zero to divide by.
  defp participation_rate(%Session{participant_count: count}, members) do
    Float.round((count || 0) / members * 100, 1)
  end

  defp mood_averages([]), do: %{}

  defp mood_averages(session_ids) do
    Repo.all(
      from m in MoodEntry,
        where: m.session_id in ^session_ids,
        group_by: [m.session_id, m.kind],
        select: {m.session_id, m.kind, avg(m.score)}
    )
    |> Map.new(fn {session_id, kind, average} ->
      {{session_id, String.to_existing_atom(kind)}, round_average(average)}
    end)
  end

  defp card_counts([]), do: %{}

  defp card_counts(session_ids) do
    Repo.all(
      from c in Card,
        join: col in Column,
        on: col.id == c.column_id,
        where: col.session_id in ^session_ids,
        group_by: col.session_id,
        select: {col.session_id, count(c.id)}
    )
    |> Map.new()
  end

  # SQLite's `avg()` comes back as a float, and never as nil: a group only
  # exists because it has rows in it. A session nobody answered has no row
  # here at all, which is what leaves the gap in the trend.
  defp round_average(average), do: Float.round(average, 2)

  # `%` and `_` are wildcards to SQL, so a search for a literal one has to say
  # so — otherwise typing `%` matches everything the team ever wrote.
  defp pattern(query) do
    trimmed = String.trim(query || "")

    if trimmed == "" do
      {:error, :empty_query}
    else
      escaped =
        trimmed
        |> String.replace("\\", "\\\\")
        |> String.replace("%", "\\%")
        |> String.replace("_", "\\_")

      {:ok, "%#{escaped}%"}
    end
  end

  defp search_cards(team, pattern) do
    Repo.all(
      from c in Card,
        join: col in Column,
        on: col.id == c.column_id,
        join: s in Session,
        on: s.id == col.session_id,
        where: s.team_id == ^team.id and s.state == "closed",
        where: fragment("? LIKE ? ESCAPE '\\'", c.text, ^pattern),
        order_by: [desc: s.closed_at, asc: c.id],
        preload: [column: {col, session: s}]
    )
  end

  defp search_notes(team, pattern) do
    Repo.all(
      from n in DiscussionNote,
        join: s in Session,
        on: s.id == n.session_id,
        where: s.team_id == ^team.id and s.state == "closed",
        where: fragment("? LIKE ? ESCAPE '\\'", n.body, ^pattern),
        order_by: [desc: s.closed_at, asc: n.id],
        preload: [session: s]
    )
  end

  # Action items are searched whatever their session's state, and whether or
  # not they have one at all: FR-503 makes them outlive the retrospective, so
  # "past actions" means every action, not only the ones behind a closed door.
  defp search_actions(team, pattern) do
    Repo.all(
      from a in ActionItem,
        where: a.team_id == ^team.id,
        where:
          fragment("? LIKE ? ESCAPE '\\'", a.title, ^pattern) or
            fragment("? LIKE ? ESCAPE '\\'", a.description, ^pattern),
        order_by: [desc: a.inserted_at, asc: a.id],
        preload: [:assignee, :session]
    )
  end

  defp team_totals(%Team{} = team) do
    sessions = closed_sessions(team)
    ids = Enum.map(sessions, & &1.id)
    moods = mood_averages(ids)
    stats = Actions.stats(team)

    %{
      team_id: team.id,
      team_name: team.name,
      session_count: length(sessions),
      participant_average: average(Enum.map(sessions, &(&1.participant_count || 0))),
      mood_average: average(for id <- ids, value = moods[{id, :checkin_mood}], do: value),
      roti_average: average(for id <- ids, value = moods[{id, :roti}], do: value),
      action_completion_rate: stats.completion_rate,
      open_actions: stats.open_count
    }
  end

  defp org_totals(teams) do
    rows = Enum.map(teams, &team_totals/1)

    %{
      session_count: Enum.sum(Enum.map(rows, & &1.session_count)),
      open_actions: Enum.sum(Enum.map(rows, & &1.open_actions)),
      mood_average: average(Enum.reject(Enum.map(rows, & &1.mood_average), &is_nil/1)),
      action_completion_rate: average(Enum.map(rows, & &1.action_completion_rate))
    }
  end

  defp average([]), do: nil
  defp average(values), do: Float.round(Enum.sum(values) / length(values), 2)

  defp authorize_member(actor, %Team{} = team) do
    if Policy.see_team?(actor, Teams.role(actor, team.id)) do
      :ok
    else
      {:error, :unauthorized}
    end
  end

  @doc """
  A closed session the caller may read the recap of (FR-602).
  """
  @spec fetch_closed_session(User.t() | Scope.t() | nil, term()) ::
          {:ok, Session.t()} | {:error, :not_found}
  def fetch_closed_session(actor, id) do
    with {:ok, session} <- Retro.fetch_session(actor, id),
         :closed <- Session.state(session) do
      {:ok, session}
    else
      _not_closed -> {:error, :not_found}
    end
  end
end
