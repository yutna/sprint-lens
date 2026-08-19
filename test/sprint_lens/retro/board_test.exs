defmodule SprintLens.Retro.BoardTest do
  use SprintLens.DataCase

  alias SprintLens.Repo
  alias SprintLens.Retro
  alias SprintLens.Retro.Board
  alias SprintLens.Retro.Card
  alias SprintLens.Retro.Events
  alias SprintLens.Retro.MoodEntry
  alias SprintLens.Retro.Session
  alias SprintLens.Retro.Vote

  setup do
    facilitator = insert(:user)
    team = team_with_lead(facilitator)
    participant = insert(:user)
    join_team(participant, team)

    %{team: team, facilitator: facilitator, participant: participant}
  end

  defp board(ctx, attrs \\ %{}) do
    session = active_session(ctx.team, ctx.facilitator, attrs)
    {:ok, session} = Retro.set_phase(ctx.facilitator, session, :brainstorm)

    %{session: session, columns: session.columns}
  end

  defp first_column(session), do: hd(session.columns)

  # A board part-way through a retro: two cards merged into a cluster, one
  # loose card, one nobody voted for, and votes already cast by two people.
  defp voted_board(ctx) do
    board = board(ctx)
    column = hd(board.columns)

    clustered = [
      write(ctx.participant, board.session, column, "Slow builds"),
      write(ctx.participant, board.session, column, "Flaky CI")
    ]

    loose = write(ctx.participant, board.session, column, "Good pairing")
    quiet = write(ctx.participant, board.session, column, "Nobody cared")

    {:ok, grouping} = Retro.set_phase(ctx.facilitator, board.session, :group)

    {:ok, group} =
      Board.create_group(ctx.participant, grouping, "Tooling", Enum.map(clustered, & &1.id))

    {:ok, session} = Retro.set_phase(ctx.facilitator, grouping, :vote)
    session = %{session | multi_vote: true}

    # Two on the cluster itself, one on a card inside it, one on the loose
    # card — enough to tell a rollup from a plain count.
    {:ok, _} = Board.cast_vote(ctx.facilitator, session, {:group, group.id})
    {:ok, _} = Board.cast_vote(ctx.facilitator, session, {:group, group.id})
    {:ok, _} = Board.cast_vote(ctx.participant, session, {:card, hd(clustered).id})
    {:ok, _} = Board.cast_vote(ctx.participant, session, {:card, loose.id})

    %{
      session: session,
      columns: board.columns,
      clustered: clustered,
      group: group,
      loose: loose,
      quiet: quiet
    }
  end

  defp cast(ctx, count) do
    session = %{ctx.session | multi_vote: true}

    for _ <- 1..count do
      {:ok, vote} = Board.cast_vote(ctx.participant, session, {:card, ctx.card.id})
      vote
    end
  end

  defp reload_session(id), do: SprintLens.Repo.get!(Session, id)

  defp write(actor, session, column, text, attrs \\ %{}) do
    {:ok, card} =
      Board.create_card(
        actor,
        session,
        Map.merge(%{column_id: column.id, text: text}, attrs)
      )

    card
  end

  describe "create_card/3" do
    setup ctx, do: Map.merge(ctx, board(ctx))

    @tag req: ["FR-301"]
    test "a participant writes a card into a column", ctx do
      column = first_column(ctx.session)

      assert {:ok, card} =
               Board.create_card(ctx.participant, ctx.session, %{
                 column_id: column.id,
                 text: "we deploy too rarely"
               })

      assert card.text == "we deploy too rarely"
      assert card.column_id == column.id
      assert card.author_id == ctx.participant.id
    end

    @tag req: ["FR-301"]
    test "card text is limited to 500 characters", ctx do
      column = first_column(ctx.session)

      assert {:error, changeset} =
               Board.create_card(ctx.participant, ctx.session, %{
                 column_id: column.id,
                 text: String.duplicate("x", Card.max_text() + 1)
               })

      assert %{text: [message]} = errors_on(changeset)
      assert message =~ "500"
    end

    @tag req: ["FR-301"]
    test "an empty card is refused", ctx do
      column = first_column(ctx.session)

      assert {:error, changeset} =
               Board.create_card(ctx.participant, ctx.session, %{
                 column_id: column.id,
                 text: "   "
               })

      refute changeset.valid?
    end

    @tag req: ["FR-305"]
    test "cards are appended, so everyone sees the same order", ctx do
      column = first_column(ctx.session)

      first = write(ctx.participant, ctx.session, column, "first")
      second = write(ctx.facilitator, ctx.session, column, "second")

      assert first.position == 0
      assert second.position == 1
    end

    @tag req: ["FR-306"]
    test "everyone in the session is told", ctx do
      Events.subscribe(ctx.session.id)
      column = first_column(ctx.session)

      write(ctx.participant, ctx.session, column, "seen")

      assert_receive {:retro_event, "card.created", %{column_id: id}}
      assert id == column.id
    end

    @tag req: ["FR-206"]
    test "cards can only be written during brainstorm", ctx do
      column = first_column(ctx.session)
      {:ok, voting} = Retro.set_phase(ctx.facilitator, ctx.session, :vote)

      assert Board.create_card(ctx.participant, voting, %{column_id: column.id, text: "late"}) ==
               {:error, :wrong_phase}
    end

    @tag req: ["FR-205"]
    test "a closed session accepts nothing", ctx do
      column = first_column(ctx.session)
      {:ok, closed} = Retro.close_session(ctx.facilitator, ctx.session)

      assert Board.create_card(ctx.participant, closed, %{column_id: column.id, text: "late"}) ==
               {:error, :session_closed}
    end

    @tag req: ["NFR-201"]
    test "someone outside the team cannot write", ctx do
      column = first_column(ctx.session)

      assert Board.create_card(insert(:user), ctx.session, %{column_id: column.id, text: "no"}) ==
               {:error, :unauthorized}
    end

    @tag req: ["FR-103"]
    test "a column from another session is not found", ctx do
      other = active_session(ctx.team, ctx.facilitator)

      assert Board.create_card(ctx.participant, ctx.session, %{
               column_id: hd(other.columns).id,
               text: "elsewhere"
             }) == {:error, :not_found}
    end
  end

  describe "clearing a field that already had a value" do
    setup ctx, do: Map.merge(ctx, board(ctx))

    @tag req: ["FR-919"]
    test "a card edited to blank is reported, not a crash", ctx do
      card = write(ctx.participant, ctx.session, first_column(ctx.session), "original")

      assert {:error, changeset} =
               Board.update_card(ctx.participant, ctx.session, card, %{text: "   "})

      assert %{text: [_message]} = errors_on(changeset)
    end

    @tag req: ["FR-407"]
    test "a note edited to blank is reported too", ctx do
      card = write(ctx.participant, ctx.session, first_column(ctx.session), "original")
      {:ok, discussing} = Retro.set_phase(ctx.facilitator, ctx.session, :discuss)

      {:ok, _note} = Board.write_note(ctx.facilitator, discussing, {:card, card.id}, "something")

      assert {:error, changeset} =
               Board.write_note(ctx.facilitator, discussing, {:card, card.id}, "   ")

      assert %{body: [_message]} = errors_on(changeset)
    end

    @tag req: ["FR-304"]
    test "a cluster relabelled to blank is reported too", ctx do
      {:ok, grouping} = Retro.set_phase(ctx.facilitator, ctx.session, :group)
      {:ok, group} = Board.create_group(ctx.participant, grouping, "Tooling", [])

      assert {:error, changeset} = Board.update_group(ctx.participant, grouping, group, "  ")
      assert %{label: [_message]} = errors_on(changeset)
    end
  end

  describe "fetch_card/2" do
    setup ctx, do: Map.merge(ctx, board(ctx))

    @tag req: ["FR-301"]
    test "finds a card together with its session", ctx do
      card = write(ctx.participant, ctx.session, first_column(ctx.session), "found")

      assert {:ok, session, found} = Board.fetch_card(ctx.participant, card.id)
      assert session.id == ctx.session.id
      assert found.id == card.id
    end

    @tag req: ["FR-103"]
    test "refuses a card belonging to a team the caller is not in", ctx do
      card = write(ctx.participant, ctx.session, first_column(ctx.session), "private")

      assert Board.fetch_card(insert(:user), card.id) == {:error, :not_found}
      assert Board.fetch_card(nil, card.id) == {:error, :not_found}
    end

    @tag req: ["FR-919"]
    test "an id that is not a number is simply not found", ctx do
      assert Board.fetch_card(ctx.participant, "not-a-number") == {:error, :not_found}
      assert Board.fetch_card(ctx.participant, 0) == {:error, :not_found}
    end
  end

  describe "idempotency (§7.5)" do
    setup ctx, do: Map.merge(ctx, board(ctx))

    @tag req: ["FR-301"]
    test "a retried request produces one card, not two", ctx do
      column = first_column(ctx.session)
      attrs = %{column_id: column.id, text: "flaky network", client_request_id: "req-1"}

      assert {:ok, first} = Board.create_card(ctx.participant, ctx.session, attrs)
      assert {:ok, second} = Board.create_card(ctx.participant, ctx.session, attrs)

      assert first.id == second.id
      assert Board.count_cards(ctx.session) == 1
    end

    @tag req: ["FR-301"]
    test "two different requests both land", ctx do
      column = first_column(ctx.session)

      write(ctx.participant, ctx.session, column, "one", %{client_request_id: "a"})
      write(ctx.participant, ctx.session, column, "two", %{client_request_id: "b"})

      assert Board.count_cards(ctx.session) == 2
    end

    @tag req: ["FR-301"]
    test "cards with no request id are never treated as duplicates", ctx do
      column = first_column(ctx.session)

      write(ctx.participant, ctx.session, column, "same text")
      write(ctx.participant, ctx.session, column, "same text")

      assert Board.count_cards(ctx.session) == 2
    end

    @tag req: ["FR-301"]
    test "an empty request id is not a request id", ctx do
      column = first_column(ctx.session)

      write(ctx.participant, ctx.session, column, "one", %{client_request_id: ""})
      write(ctx.participant, ctx.session, column, "two", %{client_request_id: ""})

      assert Board.count_cards(ctx.session) == 2
    end
  end

  describe "update_card/4 and delete_card/3" do
    setup ctx do
      ctx = Map.merge(ctx, board(ctx))
      card = write(ctx.participant, ctx.session, first_column(ctx.session), "original")

      Map.put(ctx, :card, card)
    end

    @tag req: ["FR-301"]
    test "the author edits their own card", ctx do
      assert {:ok, updated} =
               Board.update_card(ctx.participant, ctx.session, ctx.card, %{text: "revised"})

      assert updated.text == "revised"
    end

    @tag req: ["FR-301"]
    test "someone else cannot edit it", ctx do
      other = insert(:user)
      join_team(other, ctx.team)

      assert Board.update_card(other, ctx.session, ctx.card, %{text: "hijacked"}) ==
               {:error, :unauthorized}
    end

    @tag req: ["FR-301", "FR-302"]
    test "not even the facilitator, who may delete it but not rewrite it", ctx do
      assert Board.update_card(ctx.facilitator, ctx.session, ctx.card, %{text: "reworded"}) ==
               {:error, :unauthorized}

      assert Board.delete_card(ctx.facilitator, ctx.session, ctx.card) == :ok
    end

    @tag req: ["FR-301"]
    test "the author deletes their own card", ctx do
      assert Board.delete_card(ctx.participant, ctx.session, ctx.card) == :ok
      assert Board.count_cards(ctx.session) == 0
    end

    @tag req: ["FR-302"]
    test "the facilitator deletes any card", ctx do
      assert Board.delete_card(ctx.facilitator, ctx.session, ctx.card) == :ok
    end

    @tag req: ["FR-301"]
    test "another participant cannot delete it", ctx do
      other = insert(:user)
      join_team(other, ctx.team)

      assert Board.delete_card(other, ctx.session, ctx.card) == {:error, :unauthorized}
    end

    @tag req: ["FR-306"]
    test "edits and deletions are announced", ctx do
      Events.subscribe(ctx.session.id)

      Board.update_card(ctx.participant, ctx.session, ctx.card, %{text: "revised"})
      assert_receive {:retro_event, "card.updated", %{card_id: _id}}

      Board.delete_card(ctx.participant, ctx.session, ctx.card)
      assert_receive {:retro_event, "card.deleted", %{card_id: _id}}
    end

    @tag req: ["FR-308"]
    test "concurrent edits resolve as last write wins", ctx do
      # Two people holding the same card, both editing. The spec chose last
      # write wins deliberately (section 11); this pins that choice.
      {:ok, _first} = Board.update_card(ctx.participant, ctx.session, ctx.card, %{text: "first"})
      {:ok, second} = Board.update_card(ctx.participant, ctx.session, ctx.card, %{text: "second"})

      assert second.text == "second"
      assert Repo.get(Card, ctx.card.id).text == "second"
    end

    @tag req: ["FR-205"]
    test "a closed session refuses deletion", ctx do
      {:ok, closed} = Retro.close_session(ctx.facilitator, ctx.session)

      assert Board.delete_card(ctx.participant, closed, ctx.card) == {:error, :session_closed}
    end
  end

  describe "move_card/5 (FR-303, FR-305)" do
    setup ctx do
      ctx = Map.merge(ctx, board(ctx))
      [first, second | _rest] = ctx.session.columns

      cards =
        Enum.map(["a", "b", "c"], fn text -> write(ctx.participant, ctx.session, first, text) end)

      Map.merge(ctx, %{from: first, to: second, cards: cards})
    end

    defp positions(column) do
      Repo.all(
        from c in Card,
          where: c.column_id == ^column.id,
          order_by: [asc: c.position],
          select: {c.text, c.position}
      )
    end

    @tag req: ["FR-303"]
    test "a card moves to another column", ctx do
      [card | _rest] = ctx.cards

      assert {:ok, moved} = Board.move_card(ctx.participant, ctx.session, card, ctx.to.id, 0)
      assert moved.column_id == ctx.to.id
      assert positions(ctx.to) == [{"a", 0}]
    end

    @tag req: ["FR-305"]
    test "the column it left is renumbered with no gaps", ctx do
      [card | _rest] = ctx.cards

      Board.move_card(ctx.participant, ctx.session, card, ctx.to.id, 0)

      assert positions(ctx.from) == [{"b", 0}, {"c", 1}]
    end

    @tag req: ["FR-305"]
    test "a card reorders within its own column", ctx do
      [_a, _b, c] = ctx.cards

      assert {:ok, _moved} = Board.move_card(ctx.participant, ctx.session, c, ctx.from.id, 0)
      assert positions(ctx.from) == [{"c", 0}, {"a", 1}, {"b", 2}]
    end

    @tag req: ["FR-305"]
    test "a position past the end lands at the end rather than failing", ctx do
      [a | _rest] = ctx.cards

      assert {:ok, _moved} = Board.move_card(ctx.participant, ctx.session, a, ctx.from.id, 99)
      assert positions(ctx.from) == [{"b", 0}, {"c", 1}, {"a", 2}]
    end

    @tag req: ["FR-306"]
    test "the move is announced", ctx do
      Events.subscribe(ctx.session.id)
      [card | _rest] = ctx.cards

      Board.move_card(ctx.participant, ctx.session, card, ctx.to.id, 0)

      assert_receive {:retro_event, "card.moved", %{card_id: _id}}
    end

    @tag req: ["FR-303"]
    test "a column from another session is refused", ctx do
      other = active_session(ctx.team, ctx.facilitator)
      [card | _rest] = ctx.cards

      assert Board.move_card(ctx.participant, ctx.session, card, hd(other.columns).id, 0) ==
               {:error, :not_found}
    end

    @tag req: ["FR-206"]
    test "moving is available in group as well as brainstorm", ctx do
      {:ok, grouping} = Retro.set_phase(ctx.facilitator, ctx.session, :group)
      [card | _rest] = ctx.cards

      assert {:ok, _moved} = Board.move_card(ctx.participant, grouping, card, ctx.to.id, 0)
    end

    @tag req: ["FR-206"]
    test "but not during vote", ctx do
      {:ok, voting} = Retro.set_phase(ctx.facilitator, ctx.session, :vote)
      [card | _rest] = ctx.cards

      assert Board.move_card(ctx.participant, voting, card, ctx.to.id, 0) ==
               {:error, :wrong_phase}
    end
  end

  describe "grouping (FR-304)" do
    setup ctx do
      ctx = Map.merge(ctx, board(ctx))
      column = first_column(ctx.session)

      cards =
        Enum.map(["deploys are slow", "deploys break"], fn text ->
          write(ctx.participant, ctx.session, column, text)
        end)

      {:ok, session} = Retro.set_phase(ctx.facilitator, ctx.session, :group)

      Map.merge(ctx, %{session: session, cards: cards, column: column})
    end

    @tag req: ["FR-304"]
    test "a participant merges related cards into a labelled group", ctx do
      ids = Enum.map(ctx.cards, & &1.id)

      assert {:ok, group} = Board.create_group(ctx.participant, ctx.session, "Deploys", ids)
      assert group.label == "Deploys"

      [loaded] = Board.list_groups(ctx.session)
      assert Enum.map(loaded.cards, & &1.id) |> Enum.sort() == Enum.sort(ids)
    end

    @tag req: ["FR-304"]
    test "a group can be relabelled", ctx do
      {:ok, group} = Board.create_group(ctx.participant, ctx.session, "Deploys", [])

      assert {:ok, renamed} = Board.update_group(ctx.participant, ctx.session, group, "Releases")
      assert renamed.label == "Releases"
    end

    @tag req: ["FR-304"]
    test "ungrouping leaves the cards on the board", ctx do
      ids = Enum.map(ctx.cards, & &1.id)
      {:ok, group} = Board.create_group(ctx.participant, ctx.session, "Deploys", ids)

      assert Board.delete_group(ctx.participant, ctx.session, group) == :ok
      assert Board.list_groups(ctx.session) == []
      assert Board.count_cards(ctx.session) == 2
    end

    @tag req: ["FR-304"]
    test "a single card can be added to a group and taken out again", ctx do
      [card | _rest] = ctx.cards
      {:ok, group} = Board.create_group(ctx.participant, ctx.session, "Deploys", [])

      assert {:ok, grouped} = Board.set_card_group(ctx.participant, ctx.session, card, group.id)
      assert grouped.card_group_id == group.id

      assert {:ok, loose} = Board.set_card_group(ctx.participant, ctx.session, grouped, nil)
      assert loose.card_group_id == nil
    end

    @tag req: ["FR-304"]
    test "a group from another session cannot be used", ctx do
      other = active_session(ctx.team, ctx.facilitator)
      {:ok, other} = Retro.set_phase(ctx.facilitator, other, :group)
      {:ok, theirs} = Board.create_group(ctx.facilitator, other, "Theirs", [])
      [card | _rest] = ctx.cards

      assert Board.set_card_group(ctx.participant, ctx.session, card, theirs.id) ==
               {:error, :not_found}
    end

    @tag req: ["FR-304"]
    test "a group needs a label", ctx do
      assert {:error, changeset} = Board.create_group(ctx.participant, ctx.session, "  ", [])
      refute changeset.valid?
    end

    @tag req: ["FR-306"]
    test "grouping is announced", ctx do
      Events.subscribe(ctx.session.id)

      {:ok, group} = Board.create_group(ctx.participant, ctx.session, "Deploys", [])
      assert_receive {:retro_event, "group.created", %{label: "Deploys"}}

      Board.update_group(ctx.participant, ctx.session, group, "Releases")
      assert_receive {:retro_event, "group.updated", %{label: "Releases"}}

      Board.delete_group(ctx.participant, ctx.session, group)
      assert_receive {:retro_event, "group.deleted", %{group_id: _id}}
    end

    @tag req: ["FR-206"]
    test "grouping only happens in the group phase", ctx do
      {:ok, brainstorming} = Retro.set_phase(ctx.facilitator, ctx.session, :brainstorm)

      assert Board.create_group(ctx.participant, brainstorming, "Too early", []) ==
               {:error, :wrong_phase}
    end
  end

  describe "blind mode (FR-209)" do
    setup ctx do
      ctx = Map.merge(ctx, board(ctx, %{is_blind: true}))
      column = first_column(ctx.session)

      mine = write(ctx.participant, ctx.session, column, "mine")
      theirs = write(ctx.facilitator, ctx.session, column, "theirs")

      Map.merge(ctx, %{mine: mine, theirs: theirs})
    end

    @tag req: ["FR-209"]
    test "each participant sees only their own cards before the reveal", ctx do
      visible = Board.visible_cards(ctx.session, ctx.participant)

      assert Enum.map(visible, & &1.id) == [ctx.mine.id]
    end

    @tag req: ["FR-209"]
    test "the facilitator is not exempt — they see only their own too", ctx do
      visible = Board.visible_cards(ctx.session, ctx.facilitator)

      assert Enum.map(visible, & &1.id) == [ctx.theirs.id]
    end

    @tag req: ["FR-209"]
    test "after the reveal everyone sees everything", ctx do
      assert {:ok, revealed} = Board.reveal_cards(ctx.facilitator, ctx.session)

      assert length(Board.visible_cards(revealed, ctx.participant)) == 2
      assert length(Board.visible_cards(revealed, ctx.facilitator)) == 2
    end

    @tag req: ["NFR-201"]
    test "a participant cannot reveal", ctx do
      assert Board.reveal_cards(ctx.participant, ctx.session) == {:error, :unauthorized}
    end

    @tag req: ["FR-209"]
    test "a session that is not blind hides nothing", ctx do
      %{session: open} = board(ctx)
      column = first_column(open)
      write(ctx.participant, open, column, "one")
      write(ctx.facilitator, open, column, "two")

      assert length(Board.visible_cards(open, ctx.participant)) == 2
    end

    @tag req: ["FR-209", "FR-210"]
    test "a card with no author is hidden while blind, from everyone", ctx do
      # The shape an anonymous session leaves behind. Nobody can claim it.
      Repo.update_all(from(c in Card, where: c.id == ^ctx.mine.id), set: [author_id: nil])
      {:ok, session} = Retro.fetch_session(ctx.participant, ctx.session.id)

      refute Enum.any?(Board.visible_cards(session, ctx.participant), &(&1.id == ctx.mine.id))
    end

    @tag req: ["FR-209"]
    test "a signed-out viewer sees nothing while blind", ctx do
      assert Board.visible_cards(ctx.session, nil) == []
    end
  end

  describe "anonymity when the session closes (FR-210, NFR-304)" do
    setup ctx do
      ctx = Map.merge(ctx, board(ctx, %{is_anonymous: true}))
      column = first_column(ctx.session)

      cards =
        Enum.map(["one", "two"], &write(ctx.participant, ctx.session, column, &1))

      Map.merge(ctx, %{cards: cards, column: column})
    end

    @tag req: ["FR-210"]
    test "authorship exists while the session runs, so people can edit their own", ctx do
      [card | _rest] = ctx.cards

      assert card.author_id == ctx.participant.id

      assert {:ok, _updated} =
               Board.update_card(ctx.participant, ctx.session, card, %{text: "edited"})
    end

    @tag req: ["FR-210", "NFR-304"]
    test "closing deletes the authorship, it does not hide it", ctx do
      {:ok, mood} = Board.record_mood(ctx.participant, checkin(ctx), :checkin_mood, 4)

      {:ok, _closed} = Retro.close_session(ctx.facilitator, ctx.session)

      # Read straight from the database: no query against application data can
      # say who wrote what, including for an Org Admin.
      for card <- ctx.cards do
        assert Repo.get(Card, card.id).author_id == nil
      end

      assert Repo.get(MoodEntry, mood.id).user_id == nil
    end

    @tag req: ["FR-210", "NFR-304"]
    test "closing deletes the voter references too", ctx do
      {:ok, voting} = Retro.set_phase(ctx.facilitator, ctx.session, :vote)
      {:ok, vote} = Board.cast_vote(ctx.participant, voting, {:card, hd(ctx.cards).id})

      {:ok, _closed} = Retro.close_session(ctx.facilitator, voting)

      # Section 6.4 names author *and* voter references. A vote still says who
      # was in the room and what they cared about.
      assert Repo.get(Vote, vote.id).voter_id == nil
      assert Repo.get(Vote, vote.id).card_id == hd(ctx.cards).id
    end

    @tag req: ["FR-215", "FR-602"]
    test "closing reveals the cards and the totals the recap has to show", ctx do
      blind = board(ctx, %{is_blind: true})

      refute blind.session.cards_revealed
      refute blind.session.votes_revealed

      assert {:ok, closed} = Retro.close_session(ctx.facilitator, blind.session)

      # FR-602 requires the recap to show the cards and the vote totals. A
      # session that ended before the facilitator revealed them would leave a
      # recap that withholds them for good.
      assert closed.cards_revealed
      assert closed.votes_revealed
    end

    @tag req: ["NFR-304"]
    test "the cards themselves survive — only the authorship goes", ctx do
      {:ok, _closed} = Retro.close_session(ctx.facilitator, ctx.session)

      assert Board.count_cards(ctx.session) == 2
      assert Enum.map(Board.list_cards(ctx.session), & &1.text) |> Enum.sort() == ["one", "two"]
    end

    @tag req: ["FR-210"]
    test "a session that was never anonymous keeps its authorship", ctx do
      %{session: open} = board(ctx)
      card = write(ctx.participant, open, first_column(open), "attributed")

      {:ok, _closed} = Retro.close_session(ctx.facilitator, open)

      assert Repo.get(Card, card.id).author_id == ctx.participant.id
    end
  end

  describe "mood and ROTI (FR-211, FR-214)" do
    setup ctx do
      session = active_session(ctx.team, ctx.facilitator)

      Map.put(ctx, :session, session)
    end

    @tag req: ["FR-211"]
    test "check-in collects a score from one to five with an optional word", ctx do
      assert {:ok, entry} =
               Board.record_mood(ctx.participant, ctx.session, :checkin_mood, 4, "hopeful")

      assert entry.score == 4
      assert entry.word == "hopeful"
    end

    @tag req: ["FR-211"]
    test "the note really is one word", ctx do
      {:ok, entry} =
        Board.record_mood(ctx.participant, ctx.session, :checkin_mood, 3, "  tired but ok  ")

      assert entry.word == "tired"
    end

    @tag req: ["FR-211"]
    test "a score outside one to five is refused", ctx do
      assert {:error, changeset} =
               Board.record_mood(ctx.participant, ctx.session, :checkin_mood, 6)

      assert %{score: [_message]} = errors_on(changeset)
    end

    @tag req: ["FR-211"]
    test "answering again replaces the answer rather than adding another", ctx do
      {:ok, _first} = Board.record_mood(ctx.participant, ctx.session, :checkin_mood, 2)
      {:ok, second} = Board.record_mood(ctx.participant, ctx.session, :checkin_mood, 5)

      assert second.score == 5
      assert Board.mood_summary(ctx.session, :checkin_mood).count == 1
    end

    @tag req: ["FR-211"]
    test "participants see aggregates, not each other's answers", ctx do
      Board.record_mood(ctx.participant, ctx.session, :checkin_mood, 2, "tired")
      Board.record_mood(ctx.facilitator, ctx.session, :checkin_mood, 4, "hopeful")

      summary = Board.mood_summary(ctx.session, :checkin_mood)

      assert summary.count == 2
      assert summary.average == 3.0
      assert summary.distribution == %{2 => 1, 4 => 1}
      assert Enum.sort(summary.words) == ["hopeful", "tired"]
      # Nothing in the summary says who felt what.
      refute Map.has_key?(summary, :entries)
    end

    @tag req: ["FR-211"]
    test "an empty summary is empty rather than an error", ctx do
      summary = Board.mood_summary(ctx.session, :checkin_mood)

      assert summary.count == 0
      assert summary.average == nil
    end

    @tag req: ["FR-214"]
    test "ROTI is collected at wrap-up", ctx do
      {:ok, wrapup} = Retro.set_phase(ctx.facilitator, ctx.session, :wrapup)

      assert {:ok, entry} = Board.record_mood(ctx.participant, wrapup, :roti, 5)
      assert entry.score == 5
      assert Board.mood_summary(wrapup, :roti).count == 1
    end

    @tag req: ["FR-206"]
    test "check-in mood is not collected in the middle of the board", ctx do
      {:ok, brainstorming} = Retro.set_phase(ctx.facilitator, ctx.session, :brainstorm)

      assert Board.record_mood(ctx.participant, brainstorming, :checkin_mood, 3) ==
               {:error, :wrong_phase}
    end

    @tag req: ["FR-211"]
    test "a person can read back their own answer", ctx do
      {:ok, _entry} = Board.record_mood(ctx.participant, ctx.session, :checkin_mood, 4)

      assert Board.my_mood(ctx.participant, ctx.session, :checkin_mood).score == 4
      assert Board.my_mood(ctx.facilitator, ctx.session, :checkin_mood) == nil
      assert Board.my_mood(nil, ctx.session, :checkin_mood) == nil
    end

    @tag req: ["FR-306"]
    test "the aggregate is broadcast, never the individual answer", ctx do
      Events.subscribe(ctx.session.id)

      Board.record_mood(ctx.participant, ctx.session, :checkin_mood, 4, "hopeful")

      assert_receive {:retro_event, "mood.updated", payload}
      assert payload.count == 1
      refute Map.has_key?(payload, :user_id)
    end

    @tag req: ["NFR-201"]
    test "someone outside the team cannot answer", ctx do
      assert Board.record_mood(insert(:user), ctx.session, :checkin_mood, 3) ==
               {:error, :unauthorized}
    end
  end

  describe "casting votes (FR-401, FR-402, FR-403)" do
    setup ctx do
      board = board(ctx)
      column = hd(board.columns)
      card = write(ctx.participant, board.session, column, "Slow builds")
      other = write(ctx.participant, board.session, column, "Flaky tests")
      {:ok, session} = Retro.set_phase(ctx.facilitator, board.session, :vote)

      Map.merge(ctx, %{session: session, columns: board.columns, card: card, other: other})
    end

    @tag req: ["FR-403"]
    test "a participant casts a vote on a card", ctx do
      assert {:ok, vote} = Board.cast_vote(ctx.participant, ctx.session, {:card, ctx.card.id})

      assert vote.card_id == ctx.card.id
      assert vote.card_group_id == nil
      assert vote.voter_id == ctx.participant.id
    end

    @tag req: ["FR-403"]
    test "a topic key names the same thing a tuple does", ctx do
      assert {:ok, vote} = Board.cast_vote(ctx.participant, ctx.session, "card:#{ctx.card.id}")

      assert vote.card_id == ctx.card.id
    end

    @tag req: ["FR-401"]
    test "the budget is spent down and reported to its owner", ctx do
      assert Board.vote_summary(ctx.session, ctx.participant) == %{
               budget: 5,
               used: 0,
               remaining: 5,
               revealed: false
             }

      cast(ctx, 2)

      assert %{used: 2, remaining: 3} = Board.vote_summary(ctx.session, ctx.participant)
    end

    @tag req: ["FR-401"]
    test "spending past the budget is refused, and says what the budget was", ctx do
      {:ok, session} = Retro.set_phase(ctx.facilitator, ctx.session, :vote)
      session = %{session | vote_budget: 2}

      cast(%{ctx | session: session}, 2)

      assert {:error, :vote_budget_exceeded, details} =
               Board.cast_vote(ctx.participant, session, {:card, ctx.card.id})

      assert details == %{budget: 2, used: 2}
    end

    @tag req: ["FR-403"]
    test "one person's spending is not another's", ctx do
      cast(ctx, 3)

      assert %{used: 3} = Board.vote_summary(ctx.session, ctx.participant)
      assert %{used: 0, remaining: 5} = Board.vote_summary(ctx.session, ctx.facilitator)
    end

    @tag req: ["FR-403"]
    test "a signed-out viewer has spent nothing", ctx do
      assert %{used: 0} = Board.vote_summary(ctx.session, nil)
    end

    @tag req: ["FR-402"]
    test "a second vote on the same topic is refused by default", ctx do
      {:ok, _vote} = Board.cast_vote(ctx.participant, ctx.session, {:card, ctx.card.id})

      assert Board.cast_vote(ctx.participant, ctx.session, {:card, ctx.card.id}) ==
               {:error, :already_voted}
    end

    @tag req: ["FR-402"]
    test "a session that allows it takes more than one", ctx do
      session = %{ctx.session | multi_vote: true}

      assert {:ok, _first} = Board.cast_vote(ctx.participant, session, {:card, ctx.card.id})
      assert {:ok, _second} = Board.cast_vote(ctx.participant, session, {:card, ctx.card.id})

      assert %{used: 2} = Board.vote_summary(session, ctx.participant)
    end

    @tag req: ["FR-402"]
    test "the one-vote rule is per topic, not per session", ctx do
      assert {:ok, _first} = Board.cast_vote(ctx.participant, ctx.session, {:card, ctx.card.id})
      assert {:ok, _second} = Board.cast_vote(ctx.participant, ctx.session, {:card, ctx.other.id})
    end

    @tag req: ["FR-403"]
    test "a topic in another session is not found", ctx do
      elsewhere = board(ctx)
      stray = write(ctx.participant, elsewhere.session, hd(elsewhere.columns), "elsewhere")

      assert Board.cast_vote(ctx.participant, ctx.session, {:card, stray.id}) ==
               {:error, :not_found}

      assert Board.cast_vote(ctx.participant, ctx.session, {:group, 0}) == {:error, :not_found}
      assert Board.cast_vote(ctx.participant, ctx.session, "nonsense") == {:error, :not_found}
    end

    @tag req: ["FR-403"]
    test "voting outside the vote phase is refused", ctx do
      {:ok, discussing} = Retro.set_phase(ctx.facilitator, ctx.session, :discuss)

      assert Board.cast_vote(ctx.participant, discussing, {:card, ctx.card.id}) ==
               {:error, :wrong_phase}
    end

    @tag req: ["FR-103"]
    test "someone outside the team cannot vote", ctx do
      assert Board.cast_vote(insert(:user), ctx.session, {:card, ctx.card.id}) ==
               {:error, :unauthorized}
    end

    @tag req: ["FR-301"]
    test "a repeated request id casts one vote, not two (§7.5)", ctx do
      opts = [client_request_id: "vote-1"]

      assert {:ok, first} =
               Board.cast_vote(ctx.participant, ctx.session, {:card, ctx.card.id}, opts)

      assert {:ok, again} =
               Board.cast_vote(ctx.participant, ctx.session, {:card, ctx.card.id}, opts)

      assert first.id == again.id
      assert %{used: 1} = Board.vote_summary(ctx.session, ctx.participant)
    end

    @tag req: ["FR-306"]
    test "casting is announced without saying who or how many", ctx do
      Events.subscribe(ctx.session.id)

      Board.cast_vote(ctx.participant, ctx.session, {:card, ctx.card.id})

      assert_receive {:retro_event, "vote.updated", payload}
      assert payload == %{topic: "card:#{ctx.card.id}"}
    end
  end

  describe "retracting votes (FR-403)" do
    setup ctx do
      board = board(ctx)
      column = hd(board.columns)
      card = write(ctx.participant, board.session, column, "Slow builds")
      {:ok, session} = Retro.set_phase(ctx.facilitator, board.session, :vote)

      Map.merge(ctx, %{session: session, columns: board.columns, card: card})
    end

    @tag req: ["FR-403"]
    test "a vote comes back to the budget it came from", ctx do
      {:ok, _vote} = Board.cast_vote(ctx.participant, ctx.session, {:card, ctx.card.id})
      assert %{used: 1} = Board.vote_summary(ctx.session, ctx.participant)

      assert Board.retract_vote(ctx.participant, ctx.session, {:card, ctx.card.id}) == :ok
      assert %{used: 0, remaining: 5} = Board.vote_summary(ctx.session, ctx.participant)
    end

    @tag req: ["FR-403"]
    test "retracting a vote never cast is not found", ctx do
      assert Board.retract_vote(ctx.participant, ctx.session, {:card, ctx.card.id}) ==
               {:error, :not_found}
    end

    @tag req: ["FR-403"]
    test "one retraction takes back one vote", ctx do
      session = %{ctx.session | multi_vote: true}
      Board.cast_vote(ctx.participant, session, {:card, ctx.card.id})
      Board.cast_vote(ctx.participant, session, {:card, ctx.card.id})

      assert Board.retract_vote(ctx.participant, session, {:card, ctx.card.id}) == :ok
      assert %{used: 1} = Board.vote_summary(session, ctx.participant)
    end

    @tag req: ["FR-403"]
    test "nobody retracts someone else's vote", ctx do
      {:ok, _vote} = Board.cast_vote(ctx.participant, ctx.session, {:card, ctx.card.id})

      assert Board.retract_vote(ctx.facilitator, ctx.session, {:card, ctx.card.id}) ==
               {:error, :not_found}

      assert %{used: 1} = Board.vote_summary(ctx.session, ctx.participant)
    end

    @tag req: ["FR-403"]
    test "a topic that is not in this session is not found", ctx do
      assert Board.retract_vote(ctx.participant, ctx.session, "card:0") == {:error, :not_found}
    end

    @tag req: ["FR-403"]
    test "retracting outside the vote phase is refused", ctx do
      {:ok, _vote} = Board.cast_vote(ctx.participant, ctx.session, {:card, ctx.card.id})
      {:ok, discussing} = Retro.set_phase(ctx.facilitator, ctx.session, :discuss)

      assert Board.retract_vote(ctx.participant, discussing, {:card, ctx.card.id}) ==
               {:error, :wrong_phase}
    end
  end

  describe "topics and their totals (FR-404, FR-405)" do
    setup ctx, do: Map.merge(ctx, voted_board(ctx))

    @tag req: ["FR-404"]
    test "totals are hidden from everyone until the facilitator reveals them", ctx do
      for actor <- [ctx.participant, ctx.facilitator] do
        assert ctx.session |> Board.topics(actor) |> Enum.map(& &1.votes) == [nil, nil, nil]
      end
    end

    @tag req: ["FR-403"]
    test "each person sees their own votes even while totals are hidden", ctx do
      mine = Map.new(Board.topics(ctx.session, ctx.participant), &{&1.key, &1.my_votes})

      assert mine["group:#{ctx.group.id}"] == 1
      assert mine["card:#{ctx.loose.id}"] == 1

      theirs = Map.new(Board.topics(ctx.session, ctx.facilitator), &{&1.key, &1.my_votes})

      assert theirs["group:#{ctx.group.id}"] == 2
      assert theirs["card:#{ctx.loose.id}"] == 0
    end

    @tag req: ["FR-404"]
    test "after the reveal everyone sees the same totals", ctx do
      {:ok, revealed} = Board.reveal_votes(ctx.facilitator, ctx.session)

      for actor <- [ctx.participant, ctx.facilitator] do
        totals = Map.new(Board.topics(revealed, actor), &{&1.key, &1.votes})

        assert totals["group:#{ctx.group.id}"] == 3
        assert totals["card:#{ctx.loose.id}"] == 1
        assert totals["card:#{ctx.quiet.id}"] == 0
      end
    end

    @tag req: ["FR-405"]
    test "a cluster's total counts the votes cast on its cards", ctx do
      # Voting follows grouping, but a facilitator can step back a phase and
      # the room can regroup — votes already on a card must not vanish.
      {:ok, revealed} = Board.reveal_votes(ctx.facilitator, ctx.session)

      topic = Enum.find(Board.topics(revealed, ctx.participant), &(&1.kind == :group))

      assert topic.votes == 3
    end

    @tag req: ["FR-405"]
    test "revealed topics are ordered by votes, highest first", ctx do
      {:ok, revealed} = Board.reveal_votes(ctx.facilitator, ctx.session)

      assert revealed |> Board.topics(ctx.participant) |> Enum.map(& &1.key) == [
               "group:#{ctx.group.id}",
               "card:#{ctx.loose.id}",
               "card:#{ctx.quiet.id}"
             ]
    end

    @tag req: ["FR-404"]
    test "an unrevealed board is not ordered by the totals it is hiding", ctx do
      top = "group:#{ctx.group.id}"
      keys = ctx.session |> Board.topics(ctx.participant) |> Enum.map(& &1.key)

      # The cluster has the most votes. If it led the list, the order would be
      # announcing the total the reveal is supposed to withhold.
      assert top in keys
      refute List.first(keys) == top

      {:ok, revealed} = Board.reveal_votes(ctx.facilitator, ctx.session)
      revealed_keys = revealed |> Board.topics(ctx.participant) |> Enum.map(& &1.key)

      assert List.first(revealed_keys) == top
    end

    @tag req: ["FR-405"]
    test "a card inside a cluster is not a topic of its own", ctx do
      keys = ctx.session |> Board.topics(ctx.participant) |> Enum.map(& &1.key)

      for card <- ctx.clustered, do: refute("card:#{card.id}" in keys)
    end

    @tag req: ["FR-209"]
    test "a card the caller cannot see yet is not a topic for them", ctx do
      blind = board(ctx, %{is_blind: true})
      column = hd(blind.columns)
      write(ctx.facilitator, blind.session, column, "theirs")
      mine = write(ctx.participant, blind.session, column, "mine")
      {:ok, session} = Retro.set_phase(ctx.facilitator, blind.session, :vote)

      assert session |> Board.topics(ctx.participant) |> Enum.map(& &1.key) == ["card:#{mine.id}"]
    end

    @tag req: ["FR-404"]
    test "only the facilitator reveals", ctx do
      assert Board.reveal_votes(ctx.participant, ctx.session) == {:error, :unauthorized}
    end

    @tag req: ["FR-306"]
    test "the reveal is announced", ctx do
      Events.subscribe(ctx.session.id)

      Board.reveal_votes(ctx.facilitator, ctx.session)

      assert_receive {:retro_event, "vote.revealed", %{votes_revealed: true}}
    end
  end

  describe "a cluster's vote set (FR-402, FR-403)" do
    setup ctx, do: Map.merge(ctx, voted_board(ctx))

    @tag req: ["FR-403"]
    test "retracting on a cluster takes back a vote cast on one of its cards", ctx do
      # The participant's only vote in this set was cast on a card, before it
      # was merged. If the total rolls the card up and retraction does not,
      # the screen offers a vote back that nothing can return.
      topic = fn ->
        Enum.find(Board.topics(ctx.session, ctx.participant), &(&1.kind == :group))
      end

      assert topic.().my_votes == 1

      assert Board.retract_vote(ctx.participant, ctx.session, {:group, ctx.group.id}) == :ok
      assert topic.().my_votes == 0
    end

    @tag req: ["FR-402"]
    test "one vote per cluster means the cards inside it too", ctx do
      single = %{ctx.session | multi_vote: false}

      # Already voted on a card in this cluster.
      assert Board.cast_vote(ctx.participant, single, {:group, ctx.group.id}) ==
               {:error, :already_voted}

      # ...and someone who has not may still vote on it.
      other = insert(:user)
      join_team(other, ctx.team)

      assert {:ok, _vote} = Board.cast_vote(other, single, {:group, ctx.group.id})
    end
  end

  describe "the focused topic (FR-406, FR-408)" do
    setup ctx, do: Map.merge(ctx, voted_board(ctx))

    @tag req: ["FR-406"]
    test "the facilitator points every screen at one topic", ctx do
      assert {:ok, focused} =
               Board.set_focus(ctx.facilitator, ctx.session, {:group, ctx.group.id})

      assert Session.focus(focused) == {:group, ctx.group.id}
      assert Enum.find(Board.topics(focused, ctx.participant), & &1.focused?).kind == :group
    end

    @tag req: ["FR-406"]
    test "the spotlight can be emptied again", ctx do
      {:ok, focused} = Board.set_focus(ctx.facilitator, ctx.session, {:group, ctx.group.id})

      assert {:ok, cleared} = Board.set_focus(ctx.facilitator, focused, nil)
      assert Session.focus(cleared) == nil
      assert Enum.all?(Board.topics(cleared, ctx.participant), &(not &1.focused?))
    end

    @tag req: ["FR-406"]
    test "a participant does not decide what the room looks at", ctx do
      assert Board.set_focus(ctx.participant, ctx.session, {:group, ctx.group.id}) ==
               {:error, :unauthorized}

      assert Board.set_focus(ctx.participant, ctx.session, nil) == {:error, :unauthorized}
    end

    @tag req: ["FR-406"]
    test "a topic from somewhere else cannot be focused", ctx do
      assert Board.set_focus(ctx.facilitator, ctx.session, "card:0") == {:error, :not_found}
    end

    @tag req: ["FR-306"]
    test "the focus change is announced by topic key", ctx do
      Events.subscribe(ctx.session.id)

      Board.set_focus(ctx.facilitator, ctx.session, {:card, ctx.loose.id})
      assert_receive {:retro_event, "focus.changed", %{topic: topic}}
      assert topic == "card:#{ctx.loose.id}"

      Board.set_focus(ctx.facilitator, ctx.session, nil)
      assert_receive {:retro_event, "focus.changed", %{topic: nil}}
    end

    @tag req: ["FR-408"]
    test "focusing can timebox the discussion in the same breath", ctx do
      assert {:ok, focused} =
               Board.set_focus(ctx.facilitator, ctx.session, {:card, ctx.loose.id}, 300)

      assert Session.timer_running?(focused)
      assert Session.timer_remaining(focused) in 299..300
    end

    @tag req: ["FR-406"]
    test "deleting the focused card says the spotlight is empty", ctx do
      {:ok, session} = Retro.set_phase(ctx.facilitator, ctx.session, :brainstorm)
      {:ok, focused} = Board.set_focus(ctx.facilitator, session, {:card, ctx.loose.id})
      Events.subscribe(focused.id)

      :ok = Board.delete_card(ctx.facilitator, focused, ctx.loose)

      assert_receive {:retro_event, "focus.changed", %{topic: nil}}
      assert focused.id |> reload_session() |> Session.focus() == nil
    end

    @tag req: ["FR-406"]
    test "deleting an unfocused card leaves the spotlight alone", ctx do
      {:ok, session} = Retro.set_phase(ctx.facilitator, ctx.session, :brainstorm)
      {:ok, focused} = Board.set_focus(ctx.facilitator, session, {:card, ctx.loose.id})
      Events.subscribe(focused.id)

      :ok = Board.delete_card(ctx.facilitator, focused, ctx.quiet)

      assert_receive {:retro_event, "card.deleted", _payload}
      refute_receive {:retro_event, "focus.changed", _payload}
    end

    @tag req: ["FR-406"]
    test "ungrouping the focused cluster says the spotlight is empty", ctx do
      {:ok, session} = Retro.set_phase(ctx.facilitator, ctx.session, :group)
      {:ok, focused} = Board.set_focus(ctx.facilitator, session, {:group, ctx.group.id})
      Events.subscribe(focused.id)

      :ok = Board.delete_group(ctx.facilitator, focused, ctx.group)

      assert_receive {:retro_event, "focus.changed", %{topic: nil}}
    end
  end

  describe "discussion notes (FR-407)" do
    setup ctx, do: Map.merge(ctx, voted_board(ctx))

    @tag req: ["FR-407"]
    test "the facilitator records what the room decided", ctx do
      assert {:ok, note} =
               Board.write_note(
                 ctx.facilitator,
                 ctx.session,
                 {:group, ctx.group.id},
                 "Ship weekly"
               )

      assert note.body == "Ship weekly"
      assert note.card_group_id == ctx.group.id

      topic = Enum.find(Board.topics(ctx.session, ctx.participant), &(&1.kind == :group))
      assert topic.note == "Ship weekly"
    end

    @tag req: ["FR-407"]
    test "writing again edits the note rather than adding a second", ctx do
      {:ok, first} =
        Board.write_note(ctx.facilitator, ctx.session, {:card, ctx.loose.id}, "draft")

      {:ok, again} =
        Board.write_note(ctx.facilitator, ctx.session, {:card, ctx.loose.id}, "final")

      assert first.id == again.id
      assert again.body == "final"
      assert length(Board.list_notes(ctx.session)) == 1
    end

    @tag req: ["FR-407"]
    test "an empty note is refused", ctx do
      assert {:error, changeset} =
               Board.write_note(ctx.facilitator, ctx.session, {:card, ctx.loose.id}, "   ")

      assert %{body: [_message]} = errors_on(changeset)
    end

    @tag req: ["FR-407"]
    test "a participant does not write the record", ctx do
      assert Board.write_note(ctx.participant, ctx.session, {:card, ctx.loose.id}, "mine") ==
               {:error, :unauthorized}
    end

    @tag req: ["FR-407"]
    test "a topic from another session has no note here", ctx do
      assert Board.write_note(ctx.facilitator, ctx.session, "group:0", "stray") ==
               {:error, :not_found}
    end

    @tag req: ["FR-306"]
    test "the note is announced by topic, never by its words", ctx do
      Events.subscribe(ctx.session.id)

      Board.write_note(ctx.facilitator, ctx.session, {:card, ctx.loose.id}, "sensitive")

      assert_receive {:retro_event, "note.updated", payload}
      assert payload == %{topic: "card:#{ctx.loose.id}"}
      refute inspect(payload) =~ "sensitive"
    end

    @tag req: ["FR-407"]
    test "notes on a closed session are refused", ctx do
      {:ok, closed} = Retro.close_session(ctx.facilitator, ctx.session)

      assert Board.write_note(ctx.facilitator, closed, {:card, ctx.loose.id}, "late") ==
               {:error, :session_closed}
    end
  end

  describe "accepting a scope rather than a user" do
    setup ctx, do: Map.merge(ctx, board(ctx))

    @tag req: ["NFR-201"]
    test "the web layer's scope works everywhere a user does", ctx do
      scope = SprintLens.Accounts.Scope.for_user(ctx.participant)
      column = first_column(ctx.session)

      assert {:ok, card} =
               Board.create_card(scope, ctx.session, %{column_id: column.id, text: "scoped"})

      assert card.author_id == ctx.participant.id
      assert Board.visible_cards(ctx.session, scope) != []
    end
  end

  describe "authorize/3 and phases_for/1" do
    setup ctx, do: Map.merge(ctx, board(ctx))

    @tag req: ["FR-206"]
    test "reports the phases each action belongs to", ctx do
      assert Board.phases_for(:write_card) == [:brainstorm]
      assert Board.phases_for(:group_cards) == [:group]
      assert Board.phases_for(:checkin_mood) == [:checkin]
      assert Board.phases_for(:roti) == [:wrapup]
      assert Board.phases_for(:nonsense) == []
      assert ctx.session
    end

    @tag req: ["NFR-201"]
    test "an unknown action is never available", ctx do
      assert Board.authorize(ctx.participant, ctx.session, :nonsense) == {:error, :wrong_phase}
    end

    @tag req: ["FR-205"]
    test "a session that has not started yet accepts nothing", ctx do
      created = insert(:session, team: ctx.team, facilitator: ctx.facilitator, state: "created")

      assert Board.authorize_open(ctx.participant, created) == {:error, :session_closed}
    end
  end

  defp checkin(ctx) do
    {:ok, session} = Retro.set_phase(ctx.facilitator, ctx.session, :checkin)
    session
  end
end
