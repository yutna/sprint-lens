defmodule SprintLensWeb.BoardLiveTest do
  @moduledoc """
  The board through the LiveView (SCR-07, FR-301 to FR-309).

  Blind mode and anonymity are tested with two clients, because both are
  claims about what one person can see of another's work — a single-client
  test cannot tell "hidden from everyone" apart from "not rendered yet".
  """

  use SprintLensWeb.ConnCase

  import Phoenix.LiveViewTest

  @moduletag locale: "en"

  alias SprintLens.Retro
  alias SprintLens.Retro.Board
  alias SprintLens.Retro.SessionServer

  setup :register_and_log_in_user

  setup %{user: user} do
    team = team_with_lead(user)
    participant = insert(:user, language: "en", display_name: "Ploy")
    join_team(participant, team)

    %{
      team: team,
      facilitator: user,
      participant: participant,
      participant_conn: log_in_user(build_conn(), participant)
    }
  end

  defp brainstorming(ctx, attrs \\ %{}) do
    session = active_session(ctx.team, ctx.facilitator, attrs)
    {:ok, session} = Retro.set_phase(ctx.facilitator, session, :brainstorm)
    on_exit(fn -> SessionServer.stop(session.id) end)

    session
  end

  defp write(lv, column, text) do
    lv
    |> form("#card-form-#{column.id}", card: %{column_id: column.id, text: text})
    |> render_submit()
  end

  describe "writing cards (FR-301)" do
    setup ctx, do: Map.put(ctx, :session, brainstorming(ctx))

    @tag req: ["FR-301"]
    test "a participant writes a card and everyone sees it", ctx do
      column = hd(ctx.session.columns)
      {:ok, facilitator_lv, _html} = live(ctx.conn, ~p"/sessions/#{ctx.session}")
      {:ok, participant_lv, _html} = live(ctx.participant_conn, ~p"/sessions/#{ctx.session}")

      write(participant_lv, column, "we deploy too rarely")

      assert render(facilitator_lv) =~ "we deploy too rarely"
    end

    @tag req: ["FR-301"]
    test "the writing box carries the character limit and a counter", ctx do
      column = hd(ctx.session.columns)
      {:ok, lv, _html} = live(ctx.conn, ~p"/sessions/#{ctx.session}")

      html = lv |> element("#card-form-#{column.id}") |> render()

      assert html =~ ~s(maxlength="500")
      assert has_element?(lv, "#card-counter-#{column.id}")
    end

    @tag req: ["FR-919"]
    test "an over-long card is reported rather than saved", ctx do
      column = hd(ctx.session.columns)
      {:ok, lv, _html} = live(ctx.conn, ~p"/sessions/#{ctx.session}")

      assert write(lv, column, String.duplicate("x", 501)) =~ "500"
      assert Board.count_cards(ctx.session) == 0
    end

    @tag req: ["FR-917"]
    test "an empty column says so", ctx do
      column = hd(ctx.session.columns)
      {:ok, lv, _html} = live(ctx.conn, ~p"/sessions/#{ctx.session}")

      assert has_element?(lv, "#column-empty-#{column.id}")
    end

    @tag req: ["FR-206"]
    test "the writing box is not offered outside brainstorm", ctx do
      {:ok, voting} = Retro.set_phase(ctx.facilitator, ctx.session, :vote)
      column = hd(voting.columns)

      {:ok, lv, _html} = live(ctx.conn, ~p"/sessions/#{voting}")

      refute has_element?(lv, "#card-form-#{column.id}")
    end

    @tag req: ["NFR-201"]
    test "a forged write outside brainstorm is refused", ctx do
      {:ok, voting} = Retro.set_phase(ctx.facilitator, ctx.session, :vote)
      column = hd(voting.columns)

      {:ok, lv, _html} = live(ctx.conn, ~p"/sessions/#{voting}")

      assert render_submit(lv, "create_card", %{
               "card" => %{"column_id" => column.id, "text" => "sneaky"}
             }) =~ "not available in this phase"

      assert Board.count_cards(voting) == 0
    end
  end

  describe "editing and deleting (FR-301, FR-302)" do
    setup ctx do
      session = brainstorming(ctx)
      column = hd(session.columns)

      {:ok, card} =
        Board.create_card(ctx.participant, session, %{column_id: column.id, text: "original"})

      Map.merge(ctx, %{session: session, column: column, card: card})
    end

    @tag req: ["FR-301"]
    test "the author edits their own card", ctx do
      {:ok, lv, _html} = live(ctx.participant_conn, ~p"/sessions/#{ctx.session}")

      lv |> element("#edit-card-button-#{ctx.card.id}") |> render_click()

      html =
        lv
        |> form("#edit-card-#{ctx.card.id}", card: %{id: ctx.card.id, text: "revised"})
        |> render_submit()

      assert html =~ "revised"
      refute html =~ "original"
    end

    @tag req: ["FR-301"]
    test "editing can be cancelled", ctx do
      {:ok, lv, _html} = live(ctx.participant_conn, ~p"/sessions/#{ctx.session}")

      lv |> element("#edit-card-button-#{ctx.card.id}") |> render_click()
      assert has_element?(lv, "#edit-card-#{ctx.card.id}")

      lv |> element("#cancel-edit-#{ctx.card.id}") |> render_click()
      refute has_element?(lv, "#edit-card-#{ctx.card.id}")
    end

    @tag req: ["FR-301"]
    test "someone else is offered no edit control", ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/sessions/#{ctx.session}")

      refute has_element?(lv, "#edit-card-button-#{ctx.card.id}")
    end

    @tag req: ["NFR-201"]
    test "and a forged edit is refused", ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/sessions/#{ctx.session}")

      assert render_submit(lv, "update_card", %{
               "card" => %{"id" => to_string(ctx.card.id), "text" => "hijacked"}
             }) =~ "do not have permission"
    end

    @tag req: ["FR-302"]
    test "the facilitator may delete any card", ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/sessions/#{ctx.session}")

      lv |> element("#delete-card-#{ctx.card.id}") |> render_click()

      assert Board.count_cards(ctx.session) == 0
    end

    @tag req: ["FR-301"]
    test "a third participant may not", ctx do
      other = insert(:user, language: "en")
      join_team(other, ctx.team)

      {:ok, lv, _html} = live(log_in_user(build_conn(), other), ~p"/sessions/#{ctx.session}")

      refute has_element?(lv, "#delete-card-#{ctx.card.id}")

      assert render_click(lv, "delete_card", %{"id" => to_string(ctx.card.id)}) =~
               "do not have permission"
    end

    @tag req: ["FR-205"]
    test "a card cannot be deleted once the session is closed", ctx do
      {:ok, lv, _html} = live(ctx.participant_conn, ~p"/sessions/#{ctx.session}")
      {:ok, _closed} = Retro.close_session(ctx.facilitator, ctx.session)

      # The open board is still on screen; the server refuses anyway.
      assert render_click(lv, "delete_card", %{"id" => to_string(ctx.card.id)}) =~
               "session is closed"
    end

    @tag req: ["NFR-201"]
    test "an event naming a card that is not on this board is refused", ctx do
      other = brainstorming(ctx)

      {:ok, theirs} =
        Board.create_card(ctx.facilitator, other, %{column_id: hd(other.columns).id, text: "x"})

      {:ok, lv, _html} = live(ctx.participant_conn, ~p"/sessions/#{ctx.session}")

      assert render_click(lv, "delete_card", %{"id" => to_string(theirs.id)}) =~
               "does not exist"

      assert Board.count_cards(other) == 1
    end

    @tag req: ["FR-306"]
    test "a deletion reaches the other client", ctx do
      {:ok, facilitator_lv, _html} = live(ctx.conn, ~p"/sessions/#{ctx.session}")
      {:ok, participant_lv, _html} = live(ctx.participant_conn, ~p"/sessions/#{ctx.session}")

      assert render(participant_lv) =~ "original"

      facilitator_lv |> element("#delete-card-#{ctx.card.id}") |> render_click()

      refute render(participant_lv) =~ "original"
    end
  end

  describe "moving cards without dragging (FR-903, FR-914)" do
    setup ctx do
      session = brainstorming(ctx)
      [from, to | _rest] = session.columns

      {:ok, card} =
        Board.create_card(ctx.participant, session, %{column_id: from.id, text: "movable"})

      Map.merge(ctx, %{session: session, from: from, to: to, card: card})
    end

    @tag req: ["FR-903", "FR-914"]
    test "every other column is offered as a real button", ctx do
      {:ok, lv, _html} = live(ctx.participant_conn, ~p"/sessions/#{ctx.session}")

      # One button per destination, and none pointing at the column it is in.
      assert has_element?(lv, "#move-card-#{ctx.card.id}-to-#{ctx.to.id}")
      refute has_element?(lv, "#move-card-#{ctx.card.id}-to-#{ctx.from.id}")
    end

    @tag req: ["FR-303"]
    test "tapping one moves the card", ctx do
      {:ok, lv, _html} = live(ctx.participant_conn, ~p"/sessions/#{ctx.session}")

      lv |> element("#move-card-#{ctx.card.id}-to-#{ctx.to.id}") |> render_click()

      assert [moved] = Board.list_cards(ctx.session)
      assert moved.column_id == ctx.to.id
    end

    @tag req: ["FR-306"]
    test "the move reaches the other client", ctx do
      {:ok, facilitator_lv, _html} = live(ctx.conn, ~p"/sessions/#{ctx.session}")
      {:ok, participant_lv, _html} = live(ctx.participant_conn, ~p"/sessions/#{ctx.session}")

      participant_lv |> element("#move-card-#{ctx.card.id}-to-#{ctx.to.id}") |> render_click()

      assert facilitator_lv
             |> element("#column-#{ctx.to.id}")
             |> render() =~ "movable"
    end

    @tag req: ["NFR-201"]
    test "a forged move to another session's column is refused", ctx do
      other = active_session(ctx.team, ctx.facilitator)
      {:ok, lv, _html} = live(ctx.participant_conn, ~p"/sessions/#{ctx.session}")

      render_click(lv, "move_card", %{
        "id" => to_string(ctx.card.id),
        "column-id" => to_string(hd(other.columns).id)
      })

      assert hd(Board.list_cards(ctx.session)).column_id == ctx.from.id
    end
  end

  describe "one column at a time on a narrow screen (FR-902)" do
    setup ctx, do: Map.put(ctx, :session, brainstorming(ctx))

    @tag req: ["FR-902"]
    test "tabs name every column and mark which is active", ctx do
      [first, second | _rest] = ctx.session.columns
      {:ok, lv, _html} = live(ctx.conn, ~p"/sessions/#{ctx.session}")

      assert lv |> element("#tab-#{first.id}") |> render() =~ ~s(aria-selected="true")
      assert lv |> element("#tab-#{second.id}") |> render() =~ ~s(aria-selected="false")
    end

    @tag req: ["FR-902"]
    test "choosing a tab changes which column is shown", ctx do
      [_first, second | _rest] = ctx.session.columns
      {:ok, lv, _html} = live(ctx.conn, ~p"/sessions/#{ctx.session}")

      lv |> element("#tab-#{second.id}") |> render_click()

      assert lv |> element("#tab-#{second.id}") |> render() =~ ~s(aria-selected="true")
    end

    @tag req: ["FR-902"]
    test "moving a card follows it to its new column", ctx do
      [from, to | _rest] = ctx.session.columns

      {:ok, card} =
        Board.create_card(ctx.facilitator, ctx.session, %{column_id: from.id, text: "x"})

      {:ok, lv, _html} = live(ctx.conn, ~p"/sessions/#{ctx.session}")
      lv |> element("#move-card-#{card.id}-to-#{to.id}") |> render_click()

      assert lv |> element("#tab-#{to.id}") |> render() =~ ~s(aria-selected="true")
    end
  end

  describe "blind mode with two people watching (FR-209)" do
    setup ctx do
      session = brainstorming(ctx, %{is_blind: true})

      Map.merge(ctx, %{session: session, column: hd(session.columns)})
    end

    @tag req: ["FR-209"]
    test "each person sees only their own card until the reveal", ctx do
      {:ok, facilitator_lv, _html} = live(ctx.conn, ~p"/sessions/#{ctx.session}")
      {:ok, participant_lv, _html} = live(ctx.participant_conn, ~p"/sessions/#{ctx.session}")

      write(facilitator_lv, ctx.column, "mine alone")
      write(participant_lv, ctx.column, "theirs alone")

      assert render(facilitator_lv) =~ "mine alone"
      refute render(facilitator_lv) =~ "theirs alone"

      assert render(participant_lv) =~ "theirs alone"
      refute render(participant_lv) =~ "mine alone"
    end

    @tag req: ["FR-209"]
    test "the reveal shows everyone everything", ctx do
      {:ok, facilitator_lv, _html} = live(ctx.conn, ~p"/sessions/#{ctx.session}")
      {:ok, participant_lv, _html} = live(ctx.participant_conn, ~p"/sessions/#{ctx.session}")

      write(facilitator_lv, ctx.column, "mine alone")
      write(participant_lv, ctx.column, "theirs alone")

      facilitator_lv |> element("#reveal-cards") |> render_click()

      assert render(participant_lv) =~ "mine alone"
      assert render(participant_lv) =~ "theirs alone"
    end

    @tag req: ["FR-209"]
    test "only the facilitator is offered the reveal", ctx do
      {:ok, lv, _html} = live(ctx.participant_conn, ~p"/sessions/#{ctx.session}")

      refute has_element?(lv, "#reveal-cards")
      assert has_element?(lv, "#blind-notice")

      assert render_click(lv, "reveal_cards", %{}) =~ "do not have permission"
    end

    @tag req: ["FR-209"]
    test "a board that is not blind says nothing about hiding", ctx do
      open = brainstorming(ctx)
      {:ok, lv, _html} = live(ctx.conn, ~p"/sessions/#{open}")

      refute has_element?(lv, "#blind-notice")
    end
  end

  describe "anonymity on screen (FR-210)" do
    setup ctx do
      session = brainstorming(ctx, %{is_anonymous: true})
      column = hd(session.columns)

      {:ok, _card} =
        Board.create_card(ctx.participant, session, %{column_id: column.id, text: "unsigned"})

      Map.merge(ctx, %{session: session, column: column})
    end

    @tag req: ["FR-210"]
    test "no name is shown, not even to the facilitator", ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/sessions/#{ctx.session}")

      html = render(lv)
      assert html =~ "unsigned"
      refute html =~ ctx.participant.display_name
    end

    @tag req: ["FR-210", "FR-605"]
    test "an Org Admin on the board is told no more than anyone else", ctx do
      # Scenario 10.2 names the Org Admin specifically. They can only reach a
      # board they belong to (FR-605), so the case that matters is an admin
      # who *is* a member: the extra role must buy them nothing here.
      admin = insert(:org_admin, language: "en")
      join_team(admin, ctx.team)

      {:ok, lv, _html} = live(log_in_user(build_conn(), admin), ~p"/sessions/#{ctx.session}")

      html = render(lv)
      assert html =~ "unsigned"
      refute html =~ ctx.participant.display_name
    end

    @tag req: ["FR-210"]
    test "an attributed session does show who wrote what", ctx do
      open = brainstorming(ctx)
      column = hd(open.columns)

      {:ok, _card} =
        Board.create_card(ctx.participant, open, %{column_id: column.id, text: "signed"})

      {:ok, lv, _html} = live(ctx.conn, ~p"/sessions/#{open}")

      assert render(lv) =~ ctx.participant.display_name
    end
  end

  describe "grouping (FR-304)" do
    setup ctx do
      session = brainstorming(ctx)
      column = hd(session.columns)

      for text <- ["deploys are slow", "deploys break"] do
        {:ok, _card} =
          Board.create_card(ctx.participant, session, %{column_id: column.id, text: text})
      end

      {:ok, session} = Retro.set_phase(ctx.facilitator, session, :group)

      Map.merge(ctx, %{session: session, column: column})
    end

    @tag req: ["FR-304"]
    test "the cards chosen are the cards merged", ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/sessions/#{ctx.session}")
      [first, second] = Board.list_cards(ctx.session)

      lv |> element("#select-card-#{first.id}") |> render_click()
      lv |> element("#select-card-#{second.id}") |> render_click()

      html = lv |> form("#group_form", group: %{label: "Deploys"}) |> render_submit()

      assert html =~ "Deploys"
      assert [group] = Board.list_groups(ctx.session)
      assert length(group.cards) == 2
    end

    @tag req: ["FR-304"]
    test "only the chosen cards are merged", ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/sessions/#{ctx.session}")
      [first, _second] = Board.list_cards(ctx.session)

      lv |> element("#select-card-#{first.id}") |> render_click()
      lv |> form("#group_form", group: %{label: "Deploys"}) |> render_submit()

      assert [group] = Board.list_groups(ctx.session)
      assert Enum.map(group.cards, & &1.id) == [first.id]
    end

    @tag req: ["FR-304"]
    test "a card can be unchosen before merging", ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/sessions/#{ctx.session}")
      [first, second] = Board.list_cards(ctx.session)

      lv |> element("#select-card-#{first.id}") |> render_click()
      lv |> element("#select-card-#{second.id}") |> render_click()
      lv |> element("#select-card-#{first.id}") |> render_click()

      lv |> form("#group_form", group: %{label: "Deploys"}) |> render_submit()

      assert [group] = Board.list_groups(ctx.session)
      assert Enum.map(group.cards, & &1.id) == [second.id]
    end

    @tag req: ["FR-304"]
    test "an unnamed cluster is reported and the choice is kept", ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/sessions/#{ctx.session}")
      [first, _second] = Board.list_cards(ctx.session)

      lv |> element("#select-card-#{first.id}") |> render_click()

      assert lv |> form("#group_form", group: %{label: "  "}) |> render_submit() =~ "label"
      assert Board.list_groups(ctx.session) == []

      # The selection survives the failure, so nobody has to tick the boxes
      # again to fix a typo.
      assert has_element?(lv, "#select-card-#{first.id}[checked]")
    end

    @tag req: ["FR-304"]
    test "merging nothing says so rather than making an empty cluster", ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/sessions/#{ctx.session}")

      html = lv |> form("#group_form", group: %{label: "Deploys"}) |> render_submit()

      assert html =~ "Choose the cards"
      assert Board.list_groups(ctx.session) == []
    end

    @tag req: ["FR-304"]
    test "a group can be undone, leaving the cards", ctx do
      {:ok, group} = Board.create_group(ctx.facilitator, ctx.session, "Deploys", [])
      {:ok, lv, _html} = live(ctx.conn, ~p"/sessions/#{ctx.session}")

      lv |> element("#ungroup-#{group.id}") |> render_click()

      assert Board.list_groups(ctx.session) == []
      assert Board.count_cards(ctx.session) == 2
    end

    @tag req: ["FR-206"]
    test "the grouping form only appears in the group phase", ctx do
      {:ok, brainstorm} = Retro.set_phase(ctx.facilitator, ctx.session, :brainstorm)
      {:ok, lv, _html} = live(ctx.conn, ~p"/sessions/#{brainstorm}")

      refute has_element?(lv, "#group_form")
    end

    @tag req: ["FR-919"]
    test "a group needs a label", ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/sessions/#{ctx.session}")

      assert lv |> form("#group_form", group: %{label: "  "}) |> render_submit() =~ "label"
    end

    @tag req: ["NFR-201"]
    test "ungrouping another session's group is refused", ctx do
      other = active_session(ctx.team, ctx.facilitator)
      {:ok, other} = Retro.set_phase(ctx.facilitator, other, :group)
      {:ok, theirs} = Board.create_group(ctx.facilitator, other, "Theirs", [])

      {:ok, lv, _html} = live(ctx.conn, ~p"/sessions/#{ctx.session}")

      render_click(lv, "delete_group", %{"id" => to_string(theirs.id)})

      assert length(Board.list_groups(other)) == 1
    end
  end

  describe "the check-in (FR-211, FR-212)" do
    setup ctx do
      session = active_session(ctx.team, ctx.facilitator)
      on_exit(fn -> SessionServer.stop(session.id) end)

      Map.put(ctx, :session, session)
    end

    @tag req: ["FR-212"]
    test "an icebreaker prompt is shown, with no AI involved", ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/sessions/#{ctx.session}")

      assert has_element?(lv, "#icebreaker")
    end

    @tag req: ["FR-211"]
    test "a mood is recorded and the aggregate updates for everyone", ctx do
      {:ok, facilitator_lv, _html} = live(ctx.conn, ~p"/sessions/#{ctx.session}")
      {:ok, participant_lv, _html} = live(ctx.participant_conn, ~p"/sessions/#{ctx.session}")

      assert facilitator_lv |> element("#mood-summary-checkin_mood") |> render() =~ "No answers"

      participant_lv |> element("#checkin_mood-score-4") |> render_click()

      assert facilitator_lv |> element("#mood-summary-checkin_mood") |> render() =~ "4"
    end

    @tag req: ["FR-211"]
    test "participants see the aggregate, never who said what", ctx do
      {:ok, participant_lv, _html} = live(ctx.participant_conn, ~p"/sessions/#{ctx.session}")
      participant_lv |> element("#checkin_mood-score-2") |> render_click()

      {:ok, facilitator_lv, _html} = live(ctx.conn, ~p"/sessions/#{ctx.session}")

      summary = facilitator_lv |> element("#mood-summary-checkin_mood") |> render()
      assert summary =~ "2"
      refute summary =~ ctx.participant.display_name
    end

    @tag req: ["FR-211"]
    test "the one-word notes people left are shown alongside the aggregate", ctx do
      {:ok, _entry} = Board.record_mood(ctx.participant, ctx.session, :checkin_mood, 4, "hopeful")

      {:ok, lv, _html} = live(ctx.conn, ~p"/sessions/#{ctx.session}")

      assert render(lv) =~ "hopeful"
    end

    @tag req: ["FR-211"]
    test "answering again replaces the answer", ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/sessions/#{ctx.session}")

      lv |> element("#checkin_mood-score-2") |> render_click()
      lv |> element("#checkin_mood-score-5") |> render_click()

      assert Board.mood_summary(ctx.session, :checkin_mood).count == 1
      assert Board.mood_summary(ctx.session, :checkin_mood).average == 5.0
    end

    @tag req: ["FR-214"]
    test "wrap-up asks the ROTI question instead", ctx do
      {:ok, wrapup} = Retro.set_phase(ctx.facilitator, ctx.session, :wrapup)
      {:ok, lv, _html} = live(ctx.conn, ~p"/sessions/#{wrapup}")

      refute has_element?(lv, "#mood-checkin_mood")
      lv |> element("#roti-score-5") |> render_click()

      assert Board.mood_summary(wrapup, :roti).count == 1
    end

    @tag req: ["NFR-201"]
    test "a forged mood outside its phase is refused", ctx do
      {:ok, brainstorm} = Retro.set_phase(ctx.facilitator, ctx.session, :brainstorm)
      {:ok, lv, _html} = live(ctx.conn, ~p"/sessions/#{brainstorm}")

      assert render_click(lv, "record_mood", %{"kind" => "checkin_mood", "score" => "3"}) =~
               "not available in this phase"
    end
  end
end
