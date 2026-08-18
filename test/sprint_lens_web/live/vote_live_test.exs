defmodule SprintLensWeb.VoteLiveTest do
  @moduledoc """
  The vote and discuss phases on screen (SCR-07, FR-401 to FR-408).

  Two clients throughout, because every claim here is about what one person
  sees of another's: a budget that is only yours (FR-403), totals nobody sees
  until the facilitator says so (FR-404), and a spotlight everyone follows
  (FR-406).
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

  # A board with two cards merged into a cluster and one loose card, sitting in
  # the vote phase — the state scenario 10.3 starts from.
  defp voting(ctx, attrs \\ %{}) do
    session = active_session(ctx.team, ctx.facilitator, attrs)
    on_exit(fn -> SessionServer.stop(session.id) end)

    {:ok, session} = Retro.set_phase(ctx.facilitator, session, :brainstorm)
    column = hd(session.columns)

    cards =
      for text <- ["Slow builds", "Flaky CI", "Good pairing"] do
        {:ok, card} =
          Board.create_card(ctx.participant, session, %{column_id: column.id, text: text})

        card
      end

    {:ok, grouping} = Retro.set_phase(ctx.facilitator, session, :group)

    {:ok, group} =
      Board.create_group(
        ctx.participant,
        grouping,
        "Tooling",
        cards |> Enum.take(2) |> Enum.map(& &1.id)
      )

    {:ok, session} = Retro.set_phase(ctx.facilitator, grouping, :vote)

    %{session: session, group: group, loose: List.last(cards)}
  end

  defp discussing(ctx) do
    state = voting(ctx)
    {:ok, session} = Retro.set_phase(ctx.facilitator, state.session, :discuss)

    %{state | session: session}
  end

  defp open_two(ctx, session) do
    {:ok, facilitator_lv, _html} = live(ctx.conn, ~p"/sessions/#{session}")
    {:ok, participant_lv, _html} = live(ctx.participant_conn, ~p"/sessions/#{session}")

    {facilitator_lv, participant_lv}
  end

  describe "spending a budget (FR-401, FR-403)" do
    setup ctx, do: Map.merge(ctx, voting(ctx))

    @tag req: ["FR-403"]
    test "a participant votes and watches their own budget fall", ctx do
      {:ok, lv, _html} = live(ctx.participant_conn, ~p"/sessions/#{ctx.session}")

      assert render(lv) =~ "5 of 5 votes left"

      lv |> element("#vote-up-group-#{ctx.group.id}") |> render_click()

      assert render(lv) =~ "4 of 5 votes left"
      assert has_element?(lv, "#topic-mine-group-#{ctx.group.id}")
    end

    @tag req: ["FR-403"]
    test "one person's spending does not show on another's screen", ctx do
      {facilitator_lv, participant_lv} = open_two(ctx, ctx.session)

      participant_lv |> element("#vote-up-group-#{ctx.group.id}") |> render_click()

      assert render(facilitator_lv) =~ "5 of 5 votes left"
      refute has_element?(facilitator_lv, "#topic-mine-group-#{ctx.group.id}")
    end

    @tag req: ["FR-403"]
    test "a vote can be taken back", ctx do
      {:ok, lv, _html} = live(ctx.participant_conn, ~p"/sessions/#{ctx.session}")

      lv |> element("#vote-up-card-#{ctx.loose.id}") |> render_click()
      assert has_element?(lv, "#vote-down-card-#{ctx.loose.id}")

      lv |> element("#vote-down-card-#{ctx.loose.id}") |> render_click()

      assert render(lv) =~ "5 of 5 votes left"
      refute has_element?(lv, "#vote-down-card-#{ctx.loose.id}")
    end

    @tag req: ["FR-402"]
    test "voting twice on one topic is refused, and says so", ctx do
      {:ok, lv, _html} = live(ctx.participant_conn, ~p"/sessions/#{ctx.session}")

      lv |> element("#vote-up-card-#{ctx.loose.id}") |> render_click()

      assert lv |> element("#vote-up-card-#{ctx.loose.id}") |> render_click() =~
               "already voted"
    end

    @tag req: ["FR-401"]
    test "spending the last vote says what the budget was", ctx do
      %{session: session, loose: loose} = voting(ctx, %{vote_budget: 1, multi_vote: true})
      {:ok, lv, _html} = live(ctx.participant_conn, ~p"/sessions/#{session}")

      lv |> element("#vote-up-card-#{loose.id}") |> render_click()

      assert lv |> element("#vote-up-card-#{loose.id}") |> render_click() =~
               "all 1 of your votes"
    end

    @tag req: ["FR-403"]
    test "there is nothing to vote with outside the vote phase", ctx do
      {:ok, brainstorming} = Retro.set_phase(ctx.facilitator, ctx.session, :brainstorm)
      {:ok, lv, _html} = live(ctx.participant_conn, ~p"/sessions/#{brainstorming}")

      refute has_element?(lv, "#topics-panel")
      refute has_element?(lv, "#vote-remaining")
    end
  end

  describe "hidden totals (FR-404)" do
    setup ctx, do: Map.merge(ctx, voting(ctx))

    @tag req: ["FR-404"]
    test "nobody sees a total before the reveal, the facilitator included", ctx do
      {facilitator_lv, participant_lv} = open_two(ctx, ctx.session)

      participant_lv |> element("#vote-up-group-#{ctx.group.id}") |> render_click()

      for lv <- [facilitator_lv, participant_lv] do
        assert has_element?(lv, "#votes-hidden")
        refute has_element?(lv, "#topic-total-group-#{ctx.group.id}")
      end
    end

    @tag req: ["FR-404"]
    test "the reveal reaches the other screen without it asking", ctx do
      {facilitator_lv, participant_lv} = open_two(ctx, ctx.session)

      participant_lv |> element("#vote-up-group-#{ctx.group.id}") |> render_click()
      facilitator_lv |> element("#reveal-votes") |> render_click()

      for lv <- [facilitator_lv, participant_lv] do
        assert has_element?(lv, "#topic-total-group-#{ctx.group.id}", "1 vote")
        refute has_element?(lv, "#votes-hidden")
      end
    end

    @tag req: ["FR-404"]
    test "a participant has no reveal button", ctx do
      {:ok, lv, _html} = live(ctx.participant_conn, ~p"/sessions/#{ctx.session}")

      refute has_element?(lv, "#reveal-votes")
    end
  end

  describe "the focused topic (FR-406)" do
    setup ctx, do: Map.merge(ctx, discussing(ctx))

    @tag req: ["FR-406"]
    test "every screen follows the facilitator's focus", ctx do
      {facilitator_lv, participant_lv} = open_two(ctx, ctx.session)

      refute has_element?(participant_lv, "#topic-group-#{ctx.group.id}[aria-current=true]")

      facilitator_lv |> element("#focus-group-#{ctx.group.id}") |> render_click()

      assert has_element?(participant_lv, "#topic-group-#{ctx.group.id}[aria-current=true]")
      assert has_element?(facilitator_lv, "#topic-group-#{ctx.group.id}[aria-current=true]")
    end

    @tag req: ["FR-406"]
    test "the spotlight can be emptied and that reaches everyone too", ctx do
      {facilitator_lv, participant_lv} = open_two(ctx, ctx.session)

      facilitator_lv |> element("#focus-group-#{ctx.group.id}") |> render_click()
      facilitator_lv |> element("#clear-focus") |> render_click()

      refute has_element?(participant_lv, "#topic-group-#{ctx.group.id}[aria-current=true]")
    end

    @tag req: ["FR-406"]
    test "a participant has no focus control", ctx do
      {:ok, lv, _html} = live(ctx.participant_conn, ~p"/sessions/#{ctx.session}")

      refute has_element?(lv, "#focus-group-#{ctx.group.id}")
      refute has_element?(lv, "#clear-focus")
    end
  end

  describe "controls that were never rendered (NFR-201)" do
    setup ctx, do: Map.merge(ctx, discussing(ctx))

    @tag req: ["NFR-201"]
    test "a participant pushing the reveal event is still refused", ctx do
      {:ok, lv, _html} = live(ctx.participant_conn, ~p"/sessions/#{ctx.session}")

      # The button is not on their screen, but a hand-written push does not
      # care what was rendered. The server has to say no on its own.
      assert render_click(lv, "reveal_votes", %{}) =~ "permission"

      refute Retro.fetch_session(ctx.facilitator, ctx.session.id)
             |> elem(1)
             |> Map.get(:votes_revealed)
    end

    @tag req: ["NFR-201"]
    test "a participant pushing a focus change is still refused", ctx do
      {:ok, lv, _html} = live(ctx.participant_conn, ~p"/sessions/#{ctx.session}")

      assert render_click(lv, "set_focus", %{"topic" => "group:#{ctx.group.id}"}) =~ "permission"
      assert render_click(lv, "clear_focus", %{}) =~ "permission"
    end

    @tag req: ["NFR-201"]
    test "a participant pushing a note is still refused", ctx do
      {:ok, lv, _html} = live(ctx.participant_conn, ~p"/sessions/#{ctx.session}")

      html =
        render_submit(lv, "save_note", %{
          "note" => %{"topic" => "group:#{ctx.group.id}", "body" => "mine"}
        })

      assert html =~ "permission"
      assert Board.list_notes(ctx.session) == []
    end
  end

  describe "the record of the conversation (FR-407)" do
    setup ctx, do: Map.merge(ctx, discussing(ctx))

    @tag req: ["FR-407"]
    test "the facilitator writes a note and everyone reads it", ctx do
      {facilitator_lv, participant_lv} = open_two(ctx, ctx.session)

      facilitator_lv |> element("#note-group-#{ctx.group.id}") |> render_click()

      facilitator_lv
      |> form("#note-form-group-#{ctx.group.id}", note: %{body: "Fix the build first"})
      |> render_submit()

      assert has_element?(participant_lv, "#topic-note-group-#{ctx.group.id}", "Fix the build")
      refute has_element?(facilitator_lv, "#note-form-group-#{ctx.group.id}")
    end

    @tag req: ["FR-407"]
    test "an empty note is reported rather than saved", ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/sessions/#{ctx.session}")

      lv |> element("#note-group-#{ctx.group.id}") |> render_click()

      html =
        lv
        |> form("#note-form-group-#{ctx.group.id}", note: %{body: "  "})
        |> render_submit()

      assert html =~ "body"
      assert Board.list_notes(ctx.session) == []
    end

    @tag req: ["FR-407"]
    test "the note editor can be closed without writing anything", ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/sessions/#{ctx.session}")

      lv |> element("#note-group-#{ctx.group.id}") |> render_click()
      assert has_element?(lv, "#note-form-group-#{ctx.group.id}")

      lv |> element("#cancel-note") |> render_click()

      refute has_element?(lv, "#note-form-group-#{ctx.group.id}")
    end

    @tag req: ["FR-407"]
    test "a participant has no note control", ctx do
      {:ok, lv, _html} = live(ctx.participant_conn, ~p"/sessions/#{ctx.session}")

      refute has_element?(lv, "#note-group-#{ctx.group.id}")
    end
  end

  describe "the topic list itself (FR-405)" do
    setup ctx, do: Map.merge(ctx, discussing(ctx))

    @tag req: ["FR-405"]
    test "a cluster shows the cards it holds, and they are not topics too", ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/sessions/#{ctx.session}")

      assert has_element?(lv, "#topic-group-#{ctx.group.id}", "Slow builds")
      assert has_element?(lv, "#topic-card-#{ctx.loose.id}")

      # The two clustered cards are named inside the cluster, not beside it.
      assert lv
             |> element("#topics")
             |> render()
             |> then(&Regex.scan(~r/<li id="topic-/, &1))
             |> length() == 2
    end

    @tag req: ["FR-405"]
    test "an empty board says so rather than showing nothing", ctx do
      empty = active_session(ctx.team, ctx.facilitator)
      on_exit(fn -> SessionServer.stop(empty.id) end)
      {:ok, empty} = Retro.set_phase(ctx.facilitator, empty, :discuss)

      {:ok, lv, _html} = live(ctx.conn, ~p"/sessions/#{empty}")

      assert has_element?(lv, "#topics-empty")
    end

    @tag req: ["FR-405"]
    test "the ranking follows the totals once they are out", ctx do
      {facilitator_lv, participant_lv} = open_two(ctx, ctx.session)

      # Vote in the phase that allows it, then come back to discuss.
      {:ok, voting} = Retro.set_phase(ctx.facilitator, ctx.session, :vote)
      {:ok, _vote} = Board.cast_vote(ctx.participant, voting, {:card, ctx.loose.id})
      {:ok, _revealed} = Board.reveal_votes(ctx.facilitator, voting)
      {:ok, _discussing} = Retro.set_phase(ctx.facilitator, voting, :discuss)

      for lv <- [facilitator_lv, participant_lv] do
        [first | _rest] = lv |> render() |> topic_ids()
        assert first == "topic-card-#{ctx.loose.id}"
      end
    end
  end

  defp topic_ids(html) do
    ~r/<li id="(topic-[a-z]+-\d+)"/
    |> Regex.scan(html)
    |> Enum.map(fn [_match, id] -> id end)
  end
end
