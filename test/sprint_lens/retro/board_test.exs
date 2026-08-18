defmodule SprintLens.Retro.BoardTest do
  use SprintLens.DataCase

  alias SprintLens.Repo
  alias SprintLens.Retro
  alias SprintLens.Retro.Board
  alias SprintLens.Retro.Card
  alias SprintLens.Retro.Events
  alias SprintLens.Retro.MoodEntry

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
