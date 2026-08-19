defmodule SprintLens.ActionsTest do
  @moduledoc """
  Action items (FR-501 to FR-506).

  The tests that matter most here are about what "open" means. Carrying an
  item forward must not make the team look like it owes twice as much, and it
  must not make the completion rate FR-506 feeds look worse every sprint
  nothing gets finished.
  """

  use SprintLens.DataCase

  alias SprintLens.Actions
  alias SprintLens.Actions.ActionItem
  alias SprintLens.Repo
  alias SprintLens.Retro
  alias SprintLens.Retro.Board
  alias SprintLens.Retro.Events

  setup do
    facilitator = insert(:user)
    team = team_with_lead(facilitator)
    participant = insert(:user)
    join_team(participant, team)

    %{team: team, facilitator: facilitator, participant: participant}
  end

  defp discussing(ctx, attrs \\ %{}) do
    session = active_session(ctx.team, ctx.facilitator, attrs)
    {:ok, session} = Retro.set_phase(ctx.facilitator, session, :discuss)

    session
  end

  defp checking_in(ctx) do
    active_session(ctx.team, ctx.facilitator)
  end

  defp write_action(ctx, session, attrs \\ %{}) do
    {:ok, item} =
      Actions.create_action(ctx.participant, session, Map.merge(%{title: "Fix the build"}, attrs))

    item
  end

  describe "create_action/3 (FR-501, FR-502)" do
    @tag req: ["FR-501"]
    test "a participant writes down what the team agreed", ctx do
      session = discussing(ctx)

      assert {:ok, item} =
               Actions.create_action(ctx.participant, session, %{title: "Fix the build"})

      assert item.title == "Fix the build"
      assert item.team_id == ctx.team.id
      assert item.session_id == session.id
      assert ActionItem.status(item) == :open
    end

    @tag req: ["FR-502"]
    test "a title is required and a status is always there", ctx do
      session = discussing(ctx)

      assert {:error, changeset} = Actions.create_action(ctx.participant, session, %{title: "  "})
      assert %{title: [_message]} = errors_on(changeset)
    end

    @tag req: ["FR-502"]
    test "an assignee, a due date and a description are optional extras", ctx do
      session = discussing(ctx)
      due = DateTime.add(DateTime.utc_now(:second), 7, :day)

      item =
        write_action(ctx, session, %{
          assignee_id: ctx.facilitator.id,
          due_date: due,
          description: "Ask the platform team"
        })

      assert item.assignee_id == ctx.facilitator.id
      assert item.description == "Ask the platform team"
      assert DateTime.compare(item.due_date, due) == :eq
    end

    @tag req: ["FR-502"]
    test "the assignee has to be in the team", ctx do
      session = discussing(ctx)
      stranger = insert(:user)

      assert Actions.create_action(ctx.participant, session, %{
               title: "Fix the build",
               assignee_id: stranger.id
             }) == {:error, :not_found}
    end

    @tag req: ["FR-502"]
    test "an unknown status is refused", ctx do
      session = discussing(ctx)

      assert {:error, changeset} =
               Actions.create_action(ctx.participant, session, %{title: "x", status: "maybe"})

      assert %{status: [_message]} = errors_on(changeset)
    end

    @tag req: ["FR-501"]
    test "an action can be linked to the topic that prompted it", ctx do
      session = discussing(ctx)
      {:ok, brainstorming} = Retro.set_phase(ctx.facilitator, session, :brainstorm)

      {:ok, card} =
        Board.create_card(ctx.participant, brainstorming, %{
          column_id: hd(session.columns).id,
          text: "Builds are slow"
        })

      item = write_action(ctx, session, %{card_id: card.id})

      assert item.card_id == card.id
    end

    @tag req: ["FR-501"]
    test "a topic from another board is not a link", ctx do
      session = discussing(ctx)
      other = active_session(ctx.team, ctx.facilitator)
      {:ok, other} = Retro.set_phase(ctx.facilitator, other, :brainstorm)

      {:ok, stray} =
        Board.create_card(ctx.participant, other, %{
          column_id: hd(other.columns).id,
          text: "elsewhere"
        })

      assert Actions.create_action(ctx.participant, session, %{
               title: "x",
               card_id: stray.id
             }) == {:error, :not_found}

      assert Actions.create_action(ctx.participant, session, %{title: "x", card_group_id: 0}) ==
               {:error, :not_found}
    end

    @tag req: ["FR-501"]
    test "an action can be linked to a cluster", ctx do
      session = discussing(ctx)
      {:ok, grouping} = Retro.set_phase(ctx.facilitator, session, :group)
      {:ok, group} = Board.create_group(ctx.participant, grouping, "Tooling", [])

      item = write_action(ctx, session, %{card_group_id: group.id})

      assert item.card_group_id == group.id
    end

    @tag req: ["FR-501"]
    test "an action links to at most one topic", ctx do
      session = discussing(ctx)
      {:ok, grouping} = Retro.set_phase(ctx.facilitator, session, :group)
      {:ok, group} = Board.create_group(ctx.participant, grouping, "Tooling", [])
      {:ok, brainstorming} = Retro.set_phase(ctx.facilitator, session, :brainstorm)

      {:ok, card} =
        Board.create_card(ctx.participant, brainstorming, %{
          column_id: hd(session.columns).id,
          text: "Builds are slow"
        })

      assert {:error, :not_found} =
               Actions.create_action(ctx.participant, session, %{
                 title: "x",
                 card_id: card.id,
                 card_group_id: group.id
               })
    end

    @tag req: ["FR-501"]
    test "actions belong to the end of the retro, not the middle of it", ctx do
      session = active_session(ctx.team, ctx.facilitator)

      for phase <- [:checkin, :brainstorm, :group, :vote] do
        {:ok, wrong} = Retro.set_phase(ctx.facilitator, session, phase)

        assert Actions.create_action(ctx.participant, wrong, %{title: "early"}) ==
                 {:error, :wrong_phase}
      end

      for phase <- [:discuss, :wrapup] do
        {:ok, right} = Retro.set_phase(ctx.facilitator, session, phase)
        assert {:ok, _item} = Actions.create_action(ctx.participant, right, %{title: "in time"})
      end
    end

    @tag req: ["FR-205"]
    test "a closed session produces nothing new", ctx do
      session = discussing(ctx)
      {:ok, closed} = Retro.close_session(ctx.facilitator, session)

      assert Actions.create_action(ctx.participant, closed, %{title: "late"}) ==
               {:error, :session_closed}
    end

    @tag req: ["FR-103"]
    test "someone outside the team writes nothing", ctx do
      session = discussing(ctx)

      assert Actions.create_action(insert(:user), session, %{title: "no"}) ==
               {:error, :unauthorized}
    end

    @tag req: ["FR-501"]
    test "a repeated request id creates one item, not two (§7.5)", ctx do
      session = discussing(ctx)
      attrs = %{title: "Fix the build", client_request_id: "a-1"}

      {:ok, first} = Actions.create_action(ctx.participant, session, attrs)
      {:ok, again} = Actions.create_action(ctx.participant, session, attrs)

      assert first.id == again.id
      assert length(Actions.list_actions(ctx.team)) == 1
    end

    @tag req: ["FR-306"]
    test "everyone in the session is told, without the wording", ctx do
      session = discussing(ctx)
      Events.subscribe(session.id)

      item = write_action(ctx, session, %{title: "Something private-ish"})

      assert_receive {:retro_event, "action.created", payload}
      assert payload == %{action_id: item.id, status: "open"}
    end
  end

  describe "update_action/3 (FR-503)" do
    setup ctx do
      session = discussing(ctx)

      Map.merge(ctx, %{session: session, item: write_action(ctx, session)})
    end

    @tag req: ["FR-503"]
    test "a member moves an item along", ctx do
      assert {:ok, updated} =
               Actions.update_action(ctx.facilitator, ctx.item, %{status: "in_progress"})

      assert ActionItem.status(updated) == :in_progress
    end

    @tag req: ["FR-503"]
    test "and can still do it after the session has closed", ctx do
      {:ok, _closed} = Retro.close_session(ctx.facilitator, ctx.session)

      assert {:ok, updated} = Actions.update_action(ctx.participant, ctx.item, %{status: "done"})
      assert ActionItem.status(updated) == :done
    end

    @tag req: ["FR-502"]
    test "the owner and the due date can change", ctx do
      due = DateTime.add(DateTime.utc_now(:second), 3, :day)

      assert {:ok, updated} =
               Actions.update_action(ctx.participant, ctx.item, %{
                 assignee_id: ctx.facilitator.id,
                 due_date: due
               })

      assert updated.assignee_id == ctx.facilitator.id
      assert updated.assignee.id == ctx.facilitator.id
    end

    @tag req: ["FR-502"]
    test "but not to somebody outside the team", ctx do
      assert Actions.update_action(ctx.participant, ctx.item, %{assignee_id: insert(:user).id}) ==
               {:error, :not_found}
    end

    @tag req: ["FR-503"]
    test "which team it came from is history, not a field", ctx do
      other = team_with_lead(ctx.participant)

      {:ok, updated} = Actions.update_action(ctx.participant, ctx.item, %{team_id: other.id})

      assert updated.team_id == ctx.team.id
    end

    @tag req: ["FR-103"]
    test "someone outside the team changes nothing", ctx do
      assert Actions.update_action(insert(:user), ctx.item, %{status: "done"}) ==
               {:error, :unauthorized}
    end

    @tag req: ["FR-502"]
    test "an empty title is refused", ctx do
      assert {:error, changeset} = Actions.update_action(ctx.participant, ctx.item, %{title: " "})
      assert %{title: [_message]} = errors_on(changeset)
    end

    @tag req: ["FR-306"]
    test "the change is announced", ctx do
      Events.subscribe(ctx.session.id)

      Actions.update_action(ctx.participant, ctx.item, %{status: "done"})

      assert_receive {:retro_event, "action.updated", %{status: "done"}}
    end
  end

  describe "carrying items over (FR-505)" do
    setup ctx do
      last = discussing(ctx)
      item = write_action(ctx, last, %{title: "Write the runbook"})
      {:ok, _closed} = Retro.close_session(ctx.facilitator, last)

      Map.merge(ctx, %{last: last, item: item, next: checking_in(ctx)})
    end

    @tag req: ["FR-505"]
    test "check-in offers the items still open", ctx do
      assert ctx.team |> Actions.list_open_actions() |> Enum.map(& &1.id) == [ctx.item.id]
    end

    @tag req: ["FR-505"]
    test "carrying makes a new item that links to the one it came from", ctx do
      assert {:ok, carried} = Actions.carry_over(ctx.facilitator, ctx.next, ctx.item)

      assert carried.id != ctx.item.id
      assert carried.carried_from_id == ctx.item.id
      assert carried.title == ctx.item.title
      assert carried.session_id == ctx.next.id
      assert ActionItem.status(carried) == :open
    end

    @tag req: ["FR-505"]
    test "the original is left as it was, not rewritten", ctx do
      {:ok, _carried} = Actions.carry_over(ctx.facilitator, ctx.next, ctx.item)

      # Neither done nor dropped: it was superseded, and saying otherwise
      # would lie to the completion rate (FR-506).
      assert Repo.get(ActionItem, ctx.item.id) |> ActionItem.status() == :open
    end

    @tag req: ["FR-505"]
    test "and the team is not shown the same commitment twice", ctx do
      {:ok, carried} = Actions.carry_over(ctx.facilitator, ctx.next, ctx.item)

      assert ctx.team |> Actions.list_open_actions() |> Enum.map(& &1.id) == [carried.id]
    end

    @tag req: ["FR-504"]
    test "though the history still shows both", ctx do
      {:ok, carried} = Actions.carry_over(ctx.facilitator, ctx.next, ctx.item)

      ids = ctx.team |> Actions.list_actions() |> Enum.map(& &1.id)

      assert Enum.sort(ids) == Enum.sort([ctx.item.id, carried.id])
    end

    @tag req: ["FR-505"]
    test "an item marked done leaves the open list", ctx do
      {:ok, _done} = Actions.update_action(ctx.facilitator, ctx.item, %{status: "done"})

      assert Actions.list_open_actions(ctx.team) == []
    end

    @tag req: ["FR-505"]
    test "a finished item is not carried anywhere", ctx do
      {:ok, done} = Actions.update_action(ctx.facilitator, ctx.item, %{status: "done"})

      assert Actions.carry_over(ctx.facilitator, ctx.next, done) == {:error, :wrong_state}
    end

    @tag req: ["FR-505"]
    test "an item is carried once; a chain continues through the copy", ctx do
      {:ok, carried} = Actions.carry_over(ctx.facilitator, ctx.next, ctx.item)

      assert {:error, changeset} = Actions.carry_over(ctx.facilitator, ctx.next, ctx.item)
      assert %{carried_from_id: [_message]} = errors_on(changeset)

      third = checking_in(ctx)
      assert {:ok, again} = Actions.carry_over(ctx.facilitator, third, carried)
      assert again.carried_from_id == carried.id
    end

    @tag req: ["FR-505"]
    test "carrying belongs to check-in", ctx do
      {:ok, brainstorming} = Retro.set_phase(ctx.facilitator, ctx.next, :brainstorm)

      assert Actions.carry_over(ctx.facilitator, brainstorming, ctx.item) ==
               {:error, :wrong_phase}
    end

    @tag req: ["FR-103"]
    test "an item from another team is not carried into this one", ctx do
      elsewhere = team_with_lead(ctx.facilitator)
      theirs = active_session(elsewhere, ctx.facilitator)
      {:ok, theirs} = Retro.set_phase(ctx.facilitator, theirs, :discuss)
      {:ok, stray} = Actions.create_action(ctx.facilitator, theirs, %{title: "theirs"})

      assert Actions.carry_over(ctx.facilitator, ctx.next, stray) == {:error, :not_found}
    end

    @tag req: ["FR-505"]
    test "someone outside the team carries nothing", ctx do
      assert Actions.carry_over(insert(:user), ctx.next, ctx.item) == {:error, :unauthorized}
    end
  end

  describe "the team's list and its filters (FR-504)" do
    setup ctx do
      session = discussing(ctx)
      other = discussing(ctx)

      mine = write_action(ctx, session, %{title: "Mine", assignee_id: ctx.participant.id})
      theirs = write_action(ctx, session, %{title: "Theirs", assignee_id: ctx.facilitator.id})
      elsewhere = write_action(ctx, other, %{title: "Elsewhere"})
      {:ok, done} = Actions.update_action(ctx.participant, theirs, %{status: "done"})

      Map.merge(ctx, %{
        session: session,
        other: other,
        mine: mine,
        done: done,
        elsewhere: elsewhere
      })
    end

    @tag req: ["FR-504"]
    test "everything the team owns, newest first", ctx do
      assert length(Actions.list_actions(ctx.team)) == 3
    end

    @tag req: ["FR-504"]
    test "filtered by status", ctx do
      assert ctx.team |> Actions.list_actions(status: :done) |> Enum.map(& &1.id) == [ctx.done.id]
    end

    @tag req: ["FR-504"]
    test "filtered by assignee", ctx do
      assert ctx.team
             |> Actions.list_actions(assignee_id: ctx.participant.id)
             |> Enum.map(& &1.id) ==
               [ctx.mine.id]
    end

    @tag req: ["FR-504"]
    test "filtered by the session it came from", ctx do
      ids = ctx.team |> Actions.list_actions(session_id: ctx.other.id) |> Enum.map(& &1.id)

      assert ids == [ctx.elsewhere.id]
    end

    @tag req: ["FR-504"]
    test "filters combine, and blank ones are not filters", ctx do
      ids =
        ctx.team
        |> Actions.list_actions(status: "open", assignee_id: nil, session_id: "", nonsense: 1)
        |> Enum.map(& &1.id)

      assert Enum.sort(ids) == Enum.sort([ctx.mine.id, ctx.elsewhere.id])
    end

    @tag req: ["FR-504"]
    test "another team's list is its own", ctx do
      elsewhere = team_with_lead(insert(:user))

      assert Actions.list_actions(elsewhere) == []
    end

    @tag req: ["FR-602"]
    test "one session's items are its own too", ctx do
      assert ctx.other |> Actions.list_session_actions() |> Enum.map(& &1.id) == [
               ctx.elsewhere.id
             ]
    end
  end

  describe "what is waiting for one person (SCR-02)" do
    setup ctx do
      session = discussing(ctx)

      Map.merge(ctx, %{session: session})
    end

    @tag req: ["FR-504"]
    test "only what is assigned to them, and only what is still open", ctx do
      mine = write_action(ctx, ctx.session, %{title: "Mine", assignee_id: ctx.participant.id})
      write_action(ctx, ctx.session, %{title: "Theirs", assignee_id: ctx.facilitator.id})
      write_action(ctx, ctx.session, %{title: "Nobody's"})

      finished =
        write_action(ctx, ctx.session, %{title: "Finished", assignee_id: ctx.participant.id})

      {:ok, _done} = Actions.update_action(ctx.participant, finished, %{status: "done"})

      assert ctx.participant |> Actions.list_my_actions() |> Enum.map(& &1.id) == [mine.id]
    end

    @tag req: ["FR-504"]
    test "across every team they are in", ctx do
      elsewhere = team_with_lead(ctx.participant)
      theirs = active_session(elsewhere, ctx.participant)
      {:ok, theirs} = Retro.set_phase(ctx.participant, theirs, :discuss)

      {:ok, second} =
        Actions.create_action(ctx.participant, theirs, %{
          title: "Other team",
          assignee_id: ctx.participant.id
        })

      first =
        write_action(ctx, ctx.session, %{title: "This team", assignee_id: ctx.participant.id})

      ids = ctx.participant |> Actions.list_my_actions() |> Enum.map(& &1.id)

      assert Enum.sort(ids) == Enum.sort([first.id, second.id])
    end

    @tag req: ["FR-504"]
    test "and nobody signed out has any", ctx do
      write_action(ctx, ctx.session, %{title: "Mine", assignee_id: ctx.participant.id})

      assert Actions.list_my_actions(nil) == []
    end
  end

  describe "reading one item" do
    setup ctx do
      session = discussing(ctx)

      Map.merge(ctx, %{session: session, item: write_action(ctx, session)})
    end

    @tag req: ["FR-503"]
    test "a member finds it", ctx do
      assert {:ok, found} = Actions.fetch_action(ctx.facilitator, ctx.item.id)
      assert found.id == ctx.item.id
    end

    @tag req: ["FR-103"]
    test "nobody else does", ctx do
      assert Actions.fetch_action(insert(:user), ctx.item.id) == {:error, :not_found}
      assert Actions.fetch_action(nil, ctx.item.id) == {:error, :not_found}
    end

    @tag req: ["FR-919"]
    test "and an id that is not a number is simply not found", ctx do
      assert Actions.fetch_action(ctx.facilitator, "nope") == {:error, :not_found}
      assert Actions.fetch_action(ctx.facilitator, 0) == {:error, :not_found}
    end

    @tag req: ["FR-503"]
    test "a changeset is available for the form", ctx do
      assert %Ecto.Changeset{} = Actions.change_action()
      assert %Ecto.Changeset{} = Actions.change_action(ctx.item, %{title: "new"})
    end
  end

  describe "completion and ageing (FR-506)" do
    setup ctx do
      session = discussing(ctx)

      Map.merge(ctx, %{session: session})
    end

    @tag req: ["FR-506"]
    test "a team with nothing has nothing to report", ctx do
      stats = Actions.stats(ctx.team)

      assert stats.total == 0
      assert stats.completion_rate == 0.0
      assert stats.average_age_days == 0.0
      assert stats.oldest_open_days == 0
    end

    @tag req: ["FR-506"]
    test "completion is what got finished out of what was decided", ctx do
      for _ <- 1..3, do: write_action(ctx, ctx.session)
      [one, two, _three] = Actions.list_actions(ctx.team)

      {:ok, _} = Actions.update_action(ctx.participant, one, %{status: "done"})
      {:ok, _} = Actions.update_action(ctx.participant, two, %{status: "dropped"})

      stats = Actions.stats(ctx.team)

      # Dropped counts as settled but not as completed: the team decided not
      # to do it, which is neither a success nor an outstanding debt.
      assert stats.by_status == %{open: 1, in_progress: 0, done: 1, dropped: 1}
      assert stats.completion_rate == 33.3
      assert stats.open_count == 1
    end

    @tag req: ["FR-506"]
    test "ageing measures what the team is still carrying", ctx do
      old = write_action(ctx, ctx.session, %{title: "Old"})
      write_action(ctx, ctx.session, %{title: "New"})

      backdate(old, 10)
      now = DateTime.utc_now()

      stats = Actions.stats(ctx.team, now)

      assert stats.oldest_open_days == 10
      assert stats.average_age_days == 5.0
    end

    @tag req: ["FR-506"]
    test "a finished item's age is not the team's problem", ctx do
      old = write_action(ctx, ctx.session, %{title: "Old"})
      backdate(old, 30)
      {:ok, _done} = Actions.update_action(ctx.participant, old, %{status: "done"})

      write_action(ctx, ctx.session, %{title: "New"})

      assert Actions.stats(ctx.team).oldest_open_days == 0
    end

    @tag req: ["FR-506"]
    test "an item past its due date is overdue until it is settled", ctx do
      past = DateTime.add(DateTime.utc_now(:second), -1, :day)
      late = write_action(ctx, ctx.session, %{title: "Late", due_date: past})
      write_action(ctx, ctx.session, %{title: "No date"})

      assert Actions.overdue?(late)
      assert Actions.stats(ctx.team).overdue_count == 1

      {:ok, done} = Actions.update_action(ctx.participant, late, %{status: "done"})

      refute Actions.overdue?(done)
      assert Actions.stats(ctx.team).overdue_count == 0
    end

    @tag req: ["FR-506"]
    test "an item with no due date is never late", ctx do
      item = write_action(ctx, ctx.session)

      refute Actions.overdue?(item)
    end

    @tag req: ["FR-506"]
    test "age is counted in whole days from when it was written", ctx do
      item = write_action(ctx, ctx.session)

      assert Actions.age_in_days(item) == 0
      assert Actions.age_in_days(item, DateTime.add(DateTime.utc_now(), 3, :day)) == 3

      # A clock that went backwards is not negative age.
      assert Actions.age_in_days(item, DateTime.add(DateTime.utc_now(), -3, :day)) == 0
    end
  end

  defp backdate(item, days) do
    at = DateTime.add(DateTime.utc_now(:second), -days, :day)

    Repo.update_all(
      from(a in ActionItem, where: a.id == ^item.id),
      set: [inserted_at: at]
    )
  end
end
