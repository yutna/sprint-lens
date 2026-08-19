defmodule SprintLensWeb.ActionLiveTest do
  @moduledoc """
  Action items on screen: on the board, at check-in, on Home and in the team's
  own list (FR-501 to FR-506, SCR-02, SCR-10).

  Scenario 10.5 is a claim about two sessions rather than two people — what
  last week's retro left open has to show up at the start of this week's — so
  the check-in tests always have a closed session behind them.
  """

  use SprintLensWeb.ConnCase

  import Phoenix.LiveViewTest

  @moduletag locale: "en"

  alias SprintLens.Actions
  alias SprintLens.Actions.ActionItem
  alias SprintLens.Retro
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

  defp discussing(ctx) do
    session = active_session(ctx.team, ctx.facilitator)
    on_exit(fn -> SessionServer.stop(session.id) end)
    {:ok, session} = Retro.set_phase(ctx.facilitator, session, :discuss)

    session
  end

  defp checking_in(ctx) do
    session = active_session(ctx.team, ctx.facilitator)
    on_exit(fn -> SessionServer.stop(session.id) end)

    session
  end

  # Last week's retro, closed, with one thing still outstanding.
  defp with_open_item(ctx) do
    last = discussing(ctx)
    {:ok, item} = Actions.create_action(ctx.participant, last, %{title: "Write the runbook"})
    {:ok, _closed} = Retro.close_session(ctx.facilitator, last)

    %{last: last, item: item, next: checking_in(ctx)}
  end

  describe "writing an action during the discussion (FR-501, FR-502)" do
    setup ctx, do: Map.put(ctx, :session, discussing(ctx))

    @tag req: ["FR-501"]
    test "a participant writes one and everyone sees it", ctx do
      {:ok, facilitator_lv, _html} = live(ctx.conn, ~p"/sessions/#{ctx.session}")
      {:ok, participant_lv, _html} = live(ctx.participant_conn, ~p"/sessions/#{ctx.session}")

      participant_lv
      |> form("#action-form", action: %{title: "Fix the deploy script"})
      |> render_submit()

      assert render(facilitator_lv) =~ "Fix the deploy script"
      assert [item] = Actions.list_session_actions(ctx.session)
      assert ActionItem.status(item) == :open
    end

    @tag req: ["FR-502"]
    test "with an owner from the team and a due date", ctx do
      {:ok, lv, _html} = live(ctx.participant_conn, ~p"/sessions/#{ctx.session}")

      lv
      |> form("#action-form",
        action: %{
          title: "Fix the deploy script",
          assignee_id: ctx.facilitator.id,
          due_date: "2026-09-30"
        }
      )
      |> render_submit()

      assert [item] = Actions.list_session_actions(ctx.session)
      assert item.assignee_id == ctx.facilitator.id
      assert item.due_date
    end

    @tag req: ["FR-501"]
    test "an action written while a topic is focused keeps the link", ctx do
      {:ok, brainstorming} = Retro.set_phase(ctx.facilitator, ctx.session, :brainstorm)

      {:ok, card} =
        SprintLens.Retro.Board.create_card(ctx.participant, brainstorming, %{
          column_id: hd(ctx.session.columns).id,
          text: "Deploys are slow"
        })

      {:ok, discussing} = Retro.set_phase(ctx.facilitator, brainstorming, :discuss)

      {:ok, _focused} =
        SprintLens.Retro.Board.set_focus(ctx.facilitator, discussing, {:card, card.id})

      {:ok, lv, _html} = live(ctx.participant_conn, ~p"/sessions/#{ctx.session}")

      assert has_element?(lv, "#action-topic", "Deploys are slow")

      lv |> form("#action-form", action: %{title: "Cache the layers"}) |> render_submit()

      assert [item] = Actions.list_session_actions(ctx.session)
      assert item.card_id == card.id
    end

    @tag req: ["FR-502"]
    test "an untitled action is reported rather than saved", ctx do
      {:ok, lv, _html} = live(ctx.participant_conn, ~p"/sessions/#{ctx.session}")

      assert lv |> form("#action-form", action: %{title: "  "}) |> render_submit() =~ "title"
      assert Actions.list_session_actions(ctx.session) == []
    end

    @tag req: ["FR-501"]
    test "there is nothing to write with before the discussion", ctx do
      {:ok, voting} = Retro.set_phase(ctx.facilitator, ctx.session, :vote)
      {:ok, lv, _html} = live(ctx.participant_conn, ~p"/sessions/#{voting}")

      refute has_element?(lv, "#actions-panel")
    end

    @tag req: ["NFR-201"]
    test "and a forged one is refused", ctx do
      {:ok, voting} = Retro.set_phase(ctx.facilitator, ctx.session, :vote)
      {:ok, lv, _html} = live(ctx.participant_conn, ~p"/sessions/#{voting}")

      assert render_submit(lv, "create_action", %{"action" => %{"title" => "sneaky"}}) =~
               "not available in this phase"

      assert Actions.list_session_actions(ctx.session) == []
    end

    @tag req: ["FR-917"]
    test "a session with nothing agreed says so", ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/sessions/#{ctx.session}")

      assert has_element?(lv, "#actions-empty")
    end

    @tag req: ["FR-503"]
    test "status can be moved along from the board", ctx do
      {:ok, item} = Actions.create_action(ctx.participant, ctx.session, %{title: "Fix it"})
      {:ok, lv, _html} = live(ctx.participant_conn, ~p"/sessions/#{ctx.session}")

      lv
      |> form("#action-status-form-#{item.id}", %{})
      |> render_change(%{"action_id" => item.id, "status" => "done"})

      assert {:ok, updated} = Actions.fetch_action(ctx.participant, item.id)
      assert ActionItem.status(updated) == :done
    end
  end

  describe "the carry-over review at check-in (FR-505)" do
    setup ctx, do: Map.merge(ctx, with_open_item(ctx))

    @tag req: ["FR-505"]
    test "check-in opens with what is still outstanding", ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/sessions/#{ctx.next}")

      assert has_element?(lv, "#carry-over-review")
      assert has_element?(lv, "#action-#{ctx.item.id}", "Write the runbook")
    end

    @tag req: ["FR-505"]
    test "an item marked done leaves the list, for everyone watching", ctx do
      {:ok, facilitator_lv, _html} = live(ctx.conn, ~p"/sessions/#{ctx.next}")
      {:ok, participant_lv, _html} = live(ctx.participant_conn, ~p"/sessions/#{ctx.next}")

      participant_lv
      |> form("#action-status-form-#{ctx.item.id}", %{})
      |> render_change(%{"action_id" => ctx.item.id, "status" => "done"})

      # The item under review belongs to a session that has already closed
      # while everyone is watching the new one — so the announcement has to
      # reach the session they are actually in.
      refute has_element?(facilitator_lv, "#action-#{ctx.item.id}")
      assert has_element?(facilitator_lv, "#carry-over-empty")
    end

    @tag req: ["FR-505"]
    test "a carried item keeps the link and replaces the original", ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/sessions/#{ctx.next}")

      lv |> element("#carry-over-#{ctx.item.id}") |> render_click()

      assert [carried] = Actions.list_open_actions(ctx.team)
      assert carried.carried_from_id == ctx.item.id
      assert has_element?(lv, "#action-carried-#{carried.id}")
      refute has_element?(lv, "#action-#{ctx.item.id}")
    end

    @tag req: ["FR-505"]
    test "a team with nothing outstanding is told so", ctx do
      {:ok, _done} = Actions.update_action(ctx.facilitator, ctx.item, %{status: "done"})

      {:ok, lv, _html} = live(ctx.conn, ~p"/sessions/#{ctx.next}")

      assert has_element?(lv, "#carry-over-empty")
    end

    @tag req: ["FR-505"]
    test "the review is not open outside check-in", ctx do
      {:ok, brainstorming} = Retro.set_phase(ctx.facilitator, ctx.next, :brainstorm)
      {:ok, lv, _html} = live(ctx.conn, ~p"/sessions/#{brainstorming}")

      refute has_element?(lv, "#carry-over-review")
    end

    @tag req: ["NFR-201"]
    test "and a forged carry-over outside check-in is refused", ctx do
      {:ok, brainstorming} = Retro.set_phase(ctx.facilitator, ctx.next, :brainstorm)
      {:ok, lv, _html} = live(ctx.conn, ~p"/sessions/#{brainstorming}")

      assert render_click(lv, "carry_over", %{"id" => to_string(ctx.item.id)}) =~
               "not available in this phase"
    end

    @tag req: ["NFR-201"]
    test "an item from another team cannot be carried in", ctx do
      elsewhere = team_with_lead(insert(:user))
      theirs = active_session(elsewhere, insert(:user))
      on_exit(fn -> SessionServer.stop(theirs.id) end)

      {:ok, lv, _html} = live(ctx.conn, ~p"/sessions/#{ctx.next}")

      assert render_click(lv, "carry_over", %{"id" => "0"}) =~ "does not exist"

      assert render_click(lv, "update_action_status", %{"action_id" => "0", "status" => "done"}) =~
               "does not exist"
    end
  end

  describe "SCR-10 the team action list (FR-504)" do
    setup ctx do
      session = discussing(ctx)

      {:ok, mine} =
        Actions.create_action(ctx.participant, session, %{
          title: "Mine",
          assignee_id: ctx.participant.id
        })

      {:ok, theirs} =
        Actions.create_action(ctx.participant, session, %{
          title: "Theirs",
          assignee_id: ctx.facilitator.id
        })

      {:ok, done} = Actions.update_action(ctx.participant, theirs, %{status: "done"})

      Map.merge(ctx, %{session: session, mine: mine, done: done})
    end

    @tag req: ["FR-504"]
    test "lists everything the team has decided", ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}/actions")

      assert has_element?(lv, "#action-#{ctx.mine.id}", "Mine")
      assert has_element?(lv, "#action-#{ctx.done.id}", "Theirs")
    end

    @tag req: ["FR-504"]
    test "filtered by status", ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}/actions")

      lv |> form("#action-filters") |> render_change(%{"status" => "done"})

      assert has_element?(lv, "#action-#{ctx.done.id}")
      refute has_element?(lv, "#action-#{ctx.mine.id}")
    end

    @tag req: ["FR-504"]
    test "filtered by owner", ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}/actions")

      lv |> form("#action-filters") |> render_change(%{"assignee_id" => ctx.participant.id})

      assert has_element?(lv, "#action-#{ctx.mine.id}")
      refute has_element?(lv, "#action-#{ctx.done.id}")
    end

    @tag req: ["FR-504"]
    test "filtered by the session it came from", ctx do
      other = discussing(ctx)
      {:ok, elsewhere} = Actions.create_action(ctx.participant, other, %{title: "Elsewhere"})

      {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}/actions")

      lv |> form("#action-filters") |> render_change(%{"session_id" => other.id})

      assert has_element?(lv, "#action-#{elsewhere.id}")
      refute has_element?(lv, "#action-#{ctx.mine.id}")
    end

    @tag req: ["FR-506"]
    test "and reports how the team is doing", ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}/actions")

      assert has_element?(lv, "#stat-open", "1")
      assert has_element?(lv, "#stat-completion", "50")
      assert has_element?(lv, "#stat-overdue", "0")
      assert has_element?(lv, "#stat-age")
    end

    @tag req: ["FR-503"]
    test "an item's status can be changed from here", ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}/actions")

      lv
      |> form("#action-status-form-#{ctx.mine.id}", %{})
      |> render_change(%{"action_id" => ctx.mine.id, "status" => "in_progress"})

      assert {:ok, updated} = Actions.fetch_action(ctx.facilitator, ctx.mine.id)
      assert ActionItem.status(updated) == :in_progress
    end

    @tag req: ["FR-502"]
    test "a forged status is reported rather than saved", ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}/actions")

      assert render_change(lv, "update_action_status", %{
               "action_id" => to_string(ctx.mine.id),
               "status" => "maybe"
             }) =~ "need attention"
    end

    @tag req: ["NFR-201"]
    test "an item from somewhere else is not editable from here", ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}/actions")

      assert render_change(lv, "update_action_status", %{"action_id" => "0", "status" => "done"}) =~
               "does not exist"
    end

    @tag req: ["FR-504"]
    test "a superseded item stays in the history", ctx do
      next = checking_in(ctx)
      {:ok, carried} = Actions.carry_over(ctx.facilitator, next, ctx.mine)

      {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}/actions")

      assert has_element?(lv, "#action-#{ctx.mine.id}")
      assert has_element?(lv, "#action-#{carried.id}")
    end

    @tag req: ["FR-917"]
    test "a team with no actions says so", ctx do
      empty = team_with_lead(ctx.facilitator)

      {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{empty}/actions")

      assert has_element?(lv, "#actions-empty")
    end

    @tag req: ["FR-103"]
    test "a team you are not in has no action list to read", ctx do
      theirs = team_with_lead(insert(:user))

      assert {:error, {:live_redirect, %{to: "/teams"}}} =
               live(ctx.conn, ~p"/teams/#{theirs}/actions")
    end
  end

  describe "SCR-02 Home" do
    @tag req: ["FR-504"]
    test "shows what is assigned to me and still open", ctx do
      session = discussing(ctx)

      {:ok, mine} =
        Actions.create_action(ctx.participant, session, %{
          title: "Mine to do",
          assignee_id: ctx.participant.id
        })

      {:ok, _theirs} =
        Actions.create_action(ctx.participant, session, %{
          title: "Not mine",
          assignee_id: ctx.facilitator.id
        })

      {:ok, lv, _html} = live(ctx.participant_conn, ~p"/home")

      assert has_element?(lv, "#action-#{mine.id}", "Mine to do")
      refute render(lv) =~ "Not mine"
    end

    @tag req: ["FR-506"]
    test "an item past its due date is called overdue", ctx do
      session = discussing(ctx)
      past = DateTime.add(DateTime.utc_now(:second), -2, :day)

      {:ok, late} =
        Actions.create_action(ctx.participant, session, %{
          title: "Late",
          assignee_id: ctx.participant.id,
          due_date: past
        })

      {:ok, lv, _html} = live(ctx.participant_conn, ~p"/home")

      assert has_element?(lv, "#action-overdue-#{late.id}")
      assert has_element?(lv, "#action-due-#{late.id}")
    end

    @tag req: ["FR-502"]
    test "and one in progress says which state it is in", ctx do
      session = discussing(ctx)

      {:ok, item} =
        Actions.create_action(ctx.participant, session, %{
          title: "Under way",
          assignee_id: ctx.participant.id
        })

      {:ok, _moving} = Actions.update_action(ctx.participant, item, %{status: "in_progress"})

      {:ok, lv, _html} = live(ctx.participant_conn, ~p"/home")

      assert has_element?(lv, "#action-status-badge-#{item.id}", "In progress")
    end

    @tag req: ["FR-203"]
    test "a scheduled session shows when it is", ctx do
      {:ok, session} =
        Retro.create_session(ctx.facilitator, ctx.team, %{
          title: "Next sprint",
          scheduled_at: DateTime.add(DateTime.utc_now(:second), 3, :day)
        })

      {:ok, lv, _html} = live(ctx.conn, ~p"/home")

      assert has_element?(lv, "#home-session-#{session.id}", "Next sprint")
    end

    @tag req: ["FR-917"]
    test "and says so when there is nothing", ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/home")

      assert has_element?(lv, "#home-actions-empty")
    end

    @tag req: ["FR-203"]
    test "lists the sessions that are still open", ctx do
      session = discussing(ctx)

      {:ok, lv, _html} = live(ctx.conn, ~p"/home")

      assert has_element?(lv, "#home-session-#{session.id}", session.title)
    end

    @tag req: ["FR-917"]
    test "and says so when there are none", ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/home")

      assert has_element?(lv, "#home-upcoming-empty")
    end
  end
end
