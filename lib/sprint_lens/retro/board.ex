defmodule SprintLens.Retro.Board do
  @moduledoc """
  The single write path for everything that happens on a board: cards,
  clusters and mood entries.

  Every mutation goes through `authorize/3` and then broadcasts its section
  7.3 event. Nothing else in the app writes a card, and nothing else
  broadcasts a card event — so the LiveView, the REST API and any future
  realtime intent all pass the same gate, and NFR-201 has one place to be
  right rather than three.

  ## What a mutation is checked against

  In this order, because each answer makes the next question meaningful:

    1. **Access** — is this person in the session's team at all (FR-103)?
    2. **State** — is the session still open (FR-205)?
    3. **Phase** — is this action available now (FR-206)? Writing cards
       belongs to brainstorm, clustering to group, and so on.
    4. **Ownership** — may this person touch *this* card (FR-301, FR-302)?

  ## Idempotency

  Creating a card accepts the client's own request id and treats a repeat as
  the original (§7.5). A flaky mobile network retrying a POST must not leave
  two identical cards on the board; the database's unique index is what makes
  that true under concurrency, rather than a check-then-write that can race.
  """

  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias SprintLens.Accounts.Scope
  alias SprintLens.Accounts.User
  alias SprintLens.Policy
  alias SprintLens.Repo
  alias SprintLens.Retro
  alias SprintLens.Retro.Card
  alias SprintLens.Retro.CardGroup
  alias SprintLens.Retro.Column
  alias SprintLens.Retro.Events
  alias SprintLens.Retro.MoodEntry
  alias SprintLens.Retro.Session
  alias SprintLens.Teams

  # Which phases each action belongs to (section 4.3). Writing during vote
  # would let someone add a card nobody has had a chance to read.
  @phases_for %{
    write_card: [:brainstorm],
    move_card: [:brainstorm, :group],
    group_cards: [:group],
    checkin_mood: [:checkin],
    roti: [:wrapup]
  }

  ## Reading

  @doc """
  Every card in a session, in board order.
  """
  @spec list_cards(Session.t()) :: [Card.t()]
  def list_cards(%Session{} = session) do
    Repo.all(
      from c in Card,
        join: col in Column,
        on: col.id == c.column_id,
        where: col.session_id == ^session.id,
        order_by: [asc: col.position, asc: c.position],
        preload: [:author]
    )
  end

  @doc """
  A card and the session it belongs to, for a caller allowed to be there.

  Reached through the session rather than by card id alone: the membership
  check that guards every other path would otherwise be skipped, and a card id
  is a much easier thing to guess than a board (FR-103).
  """
  @spec fetch_card(User.t() | Scope.t() | nil, term()) ::
          {:ok, Session.t(), Card.t()} | {:error, :not_found}
  def fetch_card(actor, card_id) do
    with %Card{} = card <- Repo.fetch(Card, card_id),
         %Column{} = column <- Repo.fetch(Column, card.column_id),
         {:ok, session} <- Retro.fetch_session(actor, column.session_id) do
      {:ok, session, card}
    else
      _no_access -> {:error, :not_found}
    end
  end

  @doc """
  The cards a given viewer may see right now (FR-209).

  Filtering happens here rather than at the broadcast, because a broadcast
  reaches everyone and only the rendering edge knows who is looking.
  """
  @spec visible_cards(Session.t(), User.t() | Scope.t() | nil) :: [Card.t()]
  def visible_cards(%Session{} = session, actor) do
    user = user(actor)

    session
    |> list_cards()
    |> Enum.filter(&Card.visible_to?(&1, user, session))
  end

  @doc """
  A session's clusters, with their cards (FR-304).
  """
  @spec list_groups(Session.t()) :: [CardGroup.t()]
  def list_groups(%Session{} = session) do
    Repo.all(
      from g in CardGroup,
        where: g.session_id == ^session.id,
        order_by: [asc: g.position],
        preload: [cards: ^from(c in Card, order_by: [asc: c.position])]
    )
  end

  @doc """
  How many cards a session holds, which the insights dashboard needs
  (FR-604).
  """
  @spec count_cards(Session.t()) :: non_neg_integer()
  def count_cards(%Session{} = session) do
    Repo.aggregate(
      from(c in Card,
        join: col in Column,
        on: col.id == c.column_id,
        where: col.session_id == ^session.id
      ),
      :count
    )
  end

  ## Cards

  @doc """
  Writes a card into a column (FR-301).

  The author is recorded even in an anonymous session: people have to be able
  to edit their own cards while it runs, and the reference is stripped when it
  closes (section 6.4, NFR-304).
  """
  @spec create_card(User.t() | Scope.t(), Session.t(), map()) ::
          {:ok, Card.t()}
          | {:error, Ecto.Changeset.t()}
          | {:error, :unauthorized | :wrong_phase | :session_closed | :not_found}
  def create_card(actor, %Session{} = session, attrs) do
    attrs = stringify(attrs)

    with :ok <- authorize(actor, session, :write_card),
         {:ok, column} <- fetch_column(session, attrs["column_id"]) do
      case existing_by_request_id(column, attrs["client_request_id"]) do
        %Card{} = card -> {:ok, preload_card(card)}
        nil -> insert_card(actor, session, column, attrs)
      end
    end
  end

  defp insert_card(actor, session, column, attrs) do
    attrs =
      Map.merge(attrs, %{
        "column_id" => column.id,
        "author_id" => user(actor).id,
        "position" => next_position(column)
      })

    %Card{}
    |> Card.create_changeset(attrs)
    |> Repo.insert()
    |> broadcast(session, "card.created", &card_payload/1)
  end

  @doc """
  Edits a card's text (FR-301).

  Concurrent edits resolve as last write wins (FR-308): the board is a
  conversation, and two people editing the same card at the same moment is
  rare enough that presence cues are a better answer than locking.
  """
  @spec update_card(User.t() | Scope.t(), Session.t(), Card.t(), map()) ::
          {:ok, Card.t()} | {:error, Ecto.Changeset.t()} | {:error, :unauthorized | :wrong_phase}
  def update_card(actor, %Session{} = session, %Card{} = card, attrs) do
    with :ok <- authorize(actor, session, :write_card),
         :ok <- may_edit(actor, card) do
      card
      |> Card.update_changeset(stringify(attrs))
      |> Repo.update()
      |> broadcast(session, "card.updated", &card_payload/1)
    end
  end

  @doc """
  Deletes a card. The author may delete their own; the facilitator may delete
  any (FR-301, FR-302).
  """
  @spec delete_card(User.t() | Scope.t(), Session.t(), Card.t()) ::
          :ok | {:error, :unauthorized | :session_closed}
  def delete_card(actor, %Session{} = session, %Card{} = card) do
    with :ok <- authorize_open(actor, session),
         :ok <- may_delete(actor, session, card) do
      Repo.delete!(card)
      Events.broadcast(session.id, "card.deleted", %{card_id: card.id, column_id: card.column_id})

      :ok
    end
  end

  @doc """
  Moves a card to a column and a position (FR-303, FR-305).

  Positions are renumbered inside one transaction so every participant ends up
  with the same order — "card order within a column MUST be shared" is a
  statement about all clients agreeing, not about one client's view.
  """
  @spec move_card(User.t() | Scope.t(), Session.t(), Card.t(), term(), non_neg_integer()) ::
          {:ok, Card.t()} | {:error, Ecto.Changeset.t()} | {:error, atom()}
  def move_card(actor, %Session{} = session, %Card{} = card, column_id, position) do
    with :ok <- authorize(actor, session, :move_card),
         {:ok, column} <- fetch_column(session, column_id) do
      source_id = card.column_id

      Multi.new()
      |> Multi.update(
        :card,
        Card.move_changeset(card, %{column_id: column.id, position: next_position(column)})
      )
      |> Multi.run(:renumber, fn _repo, %{card: moved} ->
        # Both columns: the one the card arrived in needs it inserted at the
        # requested index, and the one it left needs its gap closed. Skipped
        # when they are the same column, which the first pass already handled.
        moved = renumber(column.id, moved, position)
        if source_id != column.id, do: renumber(source_id, nil, nil)

        {:ok, moved}
      end)
      |> Repo.transaction()
      # Matched rather than cased: the column was just fetched from this
      # session and the position comes from a count, so the changeset cannot
      # be invalid. A failure means an invariant broke.
      |> then(fn {:ok, %{renumber: moved}} ->
        broadcast({:ok, moved}, session, "card.moved", &card_payload/1)
      end)
    end
  end

  ## Groups (FR-304)

  @doc """
  Merges cards into a labelled cluster (FR-304).
  """
  @spec create_group(User.t() | Scope.t(), Session.t(), String.t(), [term()]) ::
          {:ok, CardGroup.t()} | {:error, Ecto.Changeset.t()} | {:error, atom()}
  def create_group(actor, %Session{} = session, label, card_ids) do
    with :ok <- authorize(actor, session, :group_cards) do
      attrs = %{session_id: session.id, label: label, position: next_group_position(session)}

      Multi.new()
      |> Multi.insert(:group, CardGroup.changeset(%CardGroup{}, attrs))
      |> Multi.run(:cards, fn _repo, %{group: group} ->
        {count, _} =
          Repo.update_all(
            from(c in cards_in_session(session), where: c.id in ^List.wrap(card_ids)),
            set: [card_group_id: group.id]
          )

        {:ok, count}
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{group: group}} ->
          broadcast({:ok, group}, session, "group.created", &group_payload/1)

        {:error, _step, changeset, _changes} ->
          {:error, changeset}
      end
    end
  end

  @doc """
  Relabels a cluster (FR-304).
  """
  @spec update_group(User.t() | Scope.t(), Session.t(), CardGroup.t(), String.t()) ::
          {:ok, CardGroup.t()} | {:error, Ecto.Changeset.t()} | {:error, atom()}
  def update_group(actor, %Session{} = session, %CardGroup{} = group, label) do
    with :ok <- authorize(actor, session, :group_cards) do
      group
      |> CardGroup.changeset(%{label: label})
      |> Repo.update()
      |> broadcast(session, "group.updated", &group_payload/1)
    end
  end

  @doc """
  Ungroups a cluster (FR-304).

  The cards stay on the board and simply lose their cluster: merging is a way
  of reading the board, not a way of destroying what people wrote.
  """
  @spec delete_group(User.t() | Scope.t(), Session.t(), CardGroup.t()) ::
          :ok | {:error, atom()}
  def delete_group(actor, %Session{} = session, %CardGroup{} = group) do
    with :ok <- authorize(actor, session, :group_cards) do
      Repo.delete!(group)
      Events.broadcast(session.id, "group.deleted", %{group_id: group.id})

      :ok
    end
  end

  @doc """
  Puts a card into a cluster, or takes it out when `group_id` is `nil`
  (FR-304).
  """
  @spec set_card_group(User.t() | Scope.t(), Session.t(), Card.t(), term() | nil) ::
          {:ok, Card.t()} | {:error, atom()}
  def set_card_group(actor, %Session{} = session, %Card{} = card, group_id) do
    with :ok <- authorize(actor, session, :group_cards),
         {:ok, group_id} <- resolve_group(session, group_id) do
      card
      |> Card.group_changeset(group_id)
      |> Repo.update()
      |> broadcast(session, "card.updated", &card_payload/1)
    end
  end

  ## Reveal (FR-209)

  @doc """
  Reveals every card written in blind mode (FR-209).
  """
  @spec reveal_cards(User.t() | Scope.t(), Session.t()) ::
          {:ok, Session.t()} | {:error, :unauthorized}
  def reveal_cards(actor, %Session{} = session) do
    with :ok <- authorize_control(actor, session, :reveal) do
      # A bare flag with nothing to validate; a failure would be an invariant
      # breaking rather than something a caller can correct.
      {:ok, updated} =
        session
        |> Session.reveal_changeset(%{cards_revealed: true})
        |> Repo.update()

      Events.broadcast(session.id, "card.updated", %{revealed: true})

      {:ok, Retro.preload(updated)}
    end
  end

  ## Mood and ROTI (FR-211, FR-214)

  @doc """
  Records a check-in mood or a ROTI score (FR-211, FR-214).

  Answering again replaces the previous answer rather than adding a second
  one — a person changing their mind should not skew the aggregate.
  """
  @spec record_mood(
          User.t() | Scope.t(),
          Session.t(),
          MoodEntry.kind(),
          integer(),
          String.t() | nil
        ) ::
          {:ok, MoodEntry.t()} | {:error, Ecto.Changeset.t()} | {:error, atom()}
  def record_mood(actor, %Session{} = session, kind, score, word \\ nil) do
    with :ok <- authorize(actor, session, kind_action(kind)) do
      user = user(actor)

      attrs = %{
        session_id: session.id,
        user_id: user.id,
        kind: Atom.to_string(kind),
        score: score,
        word: word
      }

      existing = Repo.get_by(MoodEntry, session_id: session.id, user_id: user.id, kind: "#{kind}")

      (existing || %MoodEntry{})
      |> MoodEntry.changeset(attrs)
      |> Repo.insert_or_update()
      |> case do
        {:ok, entry} ->
          Events.broadcast(session.id, "mood.updated", mood_summary(session, kind))
          {:ok, entry}

        error ->
          error
      end
    end
  end

  @doc """
  The aggregate for one kind of answer — which is all participants ever see
  (FR-211).
  """
  @spec mood_summary(Session.t(), MoodEntry.kind()) :: map()
  def mood_summary(%Session{} = session, kind) do
    entries =
      Repo.all(
        from m in MoodEntry,
          where: m.session_id == ^session.id and m.kind == ^Atom.to_string(kind),
          select: {m.score, m.word}
      )

    scores = Enum.map(entries, &elem(&1, 0))

    %{
      kind: kind,
      count: length(scores),
      average: average(scores),
      distribution: Enum.frequencies(scores),
      words: entries |> Enum.map(&elem(&1, 1)) |> Enum.reject(&is_nil/1)
    }
  end

  @doc """
  A person's own answer, so a form can show what they said.
  """
  @spec my_mood(User.t() | Scope.t() | nil, Session.t(), MoodEntry.kind()) :: MoodEntry.t() | nil
  def my_mood(actor, %Session{} = session, kind) do
    case user(actor) do
      nil ->
        nil

      %User{id: id} ->
        Repo.get_by(MoodEntry, session_id: session.id, user_id: id, kind: Atom.to_string(kind))
    end
  end

  ## Anonymity (FR-210, NFR-304)

  @doc """
  Strips authorship from an anonymous session's content, irreversibly.

  Called when the session closes. Section 6.4 and NFR-304 are explicit that
  the references are *deleted*, not hidden: after this, no query against
  application data can say who wrote what, including for an Org Admin.

  A no-op for a session that was never anonymous.
  """
  @spec strip_authorship(Session.t()) :: :ok
  def strip_authorship(%Session{is_anonymous: false}), do: :ok

  def strip_authorship(%Session{} = session) do
    Repo.update_all(from(c in cards_in_session(session)), set: [author_id: nil])

    Repo.update_all(
      from(m in MoodEntry, where: m.session_id == ^session.id),
      set: [user_id: nil]
    )

    :ok
  end

  ## Authorisation

  @doc """
  Whether `actor` may take `action` in this session right now.

  Public so the web layer can decide what to render without duplicating the
  rule — but the rule is enforced here regardless of what was rendered.
  """
  @spec authorize(User.t() | Scope.t() | nil, Session.t(), atom()) ::
          :ok | {:error, :unauthorized | :session_closed | :wrong_phase}
  def authorize(actor, %Session{} = session, action) do
    with :ok <- authorize_open(actor, session) do
      if Session.phase(session) in Map.get(@phases_for, action, []) do
        :ok
      else
        {:error, :wrong_phase}
      end
    end
  end

  @doc """
  Whether `actor` may act on this session at all: a member, and the session
  still open.
  """
  @spec authorize_open(User.t() | Scope.t() | nil, Session.t()) ::
          :ok | {:error, :unauthorized | :session_closed}
  def authorize_open(actor, %Session{} = session) do
    cond do
      not Policy.see_team?(actor, Teams.role(actor, session.team_id)) -> {:error, :unauthorized}
      Session.state(session) != :active -> {:error, :session_closed}
      true -> :ok
    end
  end

  @doc """
  The phases in which `action` is available (section 4.3).
  """
  @spec phases_for(atom()) :: [Session.phase()]
  def phases_for(action), do: Map.get(@phases_for, action, [])

  defp authorize_control(actor, session, control) do
    with :ok <- authorize_open(actor, session) do
      if Policy.session_can?(Retro.session_role(actor, session), control) do
        :ok
      else
        {:error, :unauthorized}
      end
    end
  end

  # Editing is the author's alone (FR-301). The facilitator's power in FR-302
  # is to remove a card, not to rewrite it.
  defp may_edit(actor, card) do
    if Policy.edit_card?(user(actor), card.author_id), do: :ok, else: {:error, :unauthorized}
  end

  # Deleting is the author's or the facilitator's (FR-301, FR-302).
  defp may_delete(actor, session, card) do
    role = Retro.session_role(actor, session)

    if Policy.delete_card?(role, user(actor), card.author_id) do
      :ok
    else
      {:error, :unauthorized}
    end
  end

  ## Internals

  defp fetch_column(session, column_id) do
    case Repo.get_by(Column, id: column_id, session_id: session.id) do
      nil -> {:error, :not_found}
      column -> {:ok, column}
    end
  end

  defp existing_by_request_id(_column, nil), do: nil
  defp existing_by_request_id(_column, ""), do: nil

  defp existing_by_request_id(column, request_id) do
    Repo.get_by(Card, column_id: column.id, client_request_id: request_id)
  end

  defp next_position(column) do
    Repo.aggregate(from(c in Card, where: c.column_id == ^column.id), :count)
  end

  defp next_group_position(session) do
    Repo.aggregate(from(g in CardGroup, where: g.session_id == ^session.id), :count)
  end

  # Rewrites every position in a column so all clients see one order (FR-305).
  # With a `moved` card it is placed at `position`; without one the column is
  # simply closed up.
  defp renumber(column_id, moved, position) do
    ordered =
      from(c in Card, where: c.column_id == ^column_id, order_by: [asc: c.position, asc: c.id])
      |> Repo.all()
      |> Enum.reject(&(moved && &1.id == moved.id))

    ordered =
      if moved do
        {before, rest} = Enum.split(ordered, position)
        before ++ [moved] ++ rest
      else
        ordered
      end

    ordered
    |> Enum.with_index()
    |> Enum.each(fn {card, index} ->
      Repo.update_all(from(c in Card, where: c.id == ^card.id), set: [position: index])
    end)

    moved && Repo.get(Card, moved.id)
  end

  defp resolve_group(_session, nil), do: {:ok, nil}

  defp resolve_group(session, group_id) do
    case Repo.get_by(CardGroup, id: group_id, session_id: session.id) do
      nil -> {:error, :not_found}
      group -> {:ok, group.id}
    end
  end

  defp cards_in_session(session) do
    from c in Card,
      join: col in Column,
      on: col.id == c.column_id,
      where: col.session_id == ^session.id
  end

  defp kind_action(:checkin_mood), do: :checkin_mood
  defp kind_action(:roti), do: :roti

  defp average([]), do: nil
  defp average(scores), do: Float.round(Enum.sum(scores) / length(scores), 2)

  defp broadcast({:ok, record}, session, event, payload_fun) do
    record = preload_record(record)
    Events.broadcast(session.id, event, payload_fun.(record))

    {:ok, record}
  end

  defp broadcast(error, _session, _event, _payload_fun), do: error

  defp preload_record(%Card{} = card), do: preload_card(card)
  defp preload_record(%CardGroup{} = group), do: Repo.preload(group, :cards)

  defp preload_card(%Card{} = card), do: Repo.preload(card, :author)

  defp card_payload(%Card{} = card) do
    %{
      card_id: card.id,
      column_id: card.column_id,
      position: card.position,
      card_group_id: card.card_group_id
    }
  end

  defp group_payload(%CardGroup{} = group) do
    %{group_id: group.id, label: group.label, position: group.position}
  end

  defp stringify(attrs), do: Map.new(attrs, fn {key, value} -> {to_string(key), value} end)

  defp user(%Scope{user: user}), do: user
  defp user(%User{} = user), do: user
  defp user(_other), do: nil
end
