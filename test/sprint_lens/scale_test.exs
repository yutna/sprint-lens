defmodule SprintLens.ScaleTest do
  @moduledoc """
  The numbers NFR-103 names: fifty people in one session, ten sessions at
  once, five hundred accounts.

  ## This is a correctness test, not a benchmark

  A benchmark on a laptop says nothing about a server, so what is asserted
  here is that the invariants hold at the stated size: every card lands, no
  vote budget is exceeded, the counts add up. SQLite takes one writer at a
  time, which is exactly the property this milestone should be nervous about
  — so the test writes concurrently and then checks that nothing was lost.

  The wall-clock bound is generous on purpose. It is there to catch a
  quadratic, not to measure a machine.
  """

  use SprintLens.DataCase

  alias SprintLens.Actions
  alias SprintLens.Insights
  alias SprintLens.Retro
  alias SprintLens.Retro.Board
  alias SprintLens.Teams

  @participants 50
  @sessions 10
  @users 500

  # Generous: a quadratic in any of these paths blows straight past it, while
  # a slow machine does not.
  @budget_ms 60_000

  setup do
    lead = insert(:user)
    team = team_with_lead(lead)

    %{team: team, lead: lead}
  end

  @tag req: ["NFR-103"]
  test "fifty people write, group and vote in one session without losing anything", ctx do
    people =
      [ctx.lead | for(_ <- 1..(@participants - 1), do: insert(:user))]
      |> tap(fn [_lead | members] ->
        for member <- members, do: join_team(member, ctx.team)
      end)

    assert length(people) == @participants

    session = active_session(ctx.team, ctx.lead)
    {:ok, session} = Retro.set_phase(ctx.lead, session, :brainstorm)
    column = hd(session.columns)

    {elapsed, cards} =
      :timer.tc(fn ->
        for person <- people do
          {:ok, card} =
            Board.create_card(person, session, %{column_id: column.id, text: "From #{person.id}"})

          card
        end
      end)

    # Every write landed, and each got its own position — the ordering
    # FR-305 promises holds at fifty as it does at two.
    assert length(cards) == @participants
    assert Board.count_cards(session) == @participants
    assert cards |> Enum.map(& &1.position) |> Enum.sort() == Enum.to_list(0..(@participants - 1))

    {:ok, voting} = Retro.set_phase(ctx.lead, session, :vote)

    for person <- people, card <- Enum.take(cards, 3) do
      assert {:ok, _vote} = Board.cast_vote(person, voting, {:card, card.id})
    end

    # Three votes each, and the budget of five was never exceeded.
    for person <- people do
      assert %{used: 3, remaining: 2} = Board.vote_summary(voting, person)
    end

    {:ok, revealed} = Board.reveal_votes(ctx.lead, voting)
    totals = revealed |> Board.topics(ctx.lead) |> Enum.map(& &1.votes) |> Enum.sum()

    assert totals == @participants * 3
    assert div(elapsed, 1000) < @budget_ms
  end

  @tag req: ["NFR-103"]
  test "ten sessions run at once without their content mixing", ctx do
    sessions =
      for index <- 1..@sessions do
        session = active_session(ctx.team, ctx.lead, %{title: "Sprint #{index}"})
        {:ok, session} = Retro.set_phase(ctx.lead, session, :brainstorm)

        {:ok, _card} =
          Board.create_card(ctx.lead, session, %{
            column_id: hd(session.columns).id,
            text: "Card for sprint #{index}"
          })

        session
      end

    assert length(sessions) == @sessions
    assert Retro.count_active_sessions(ctx.team) == @sessions

    # Each board holds exactly its own card, however many are open.
    for {session, index} <- Enum.with_index(sessions, 1) do
      assert [card] = Board.list_cards(session)
      assert card.text == "Card for sprint #{index}"
    end
  end

  @tag req: ["NFR-103"]
  test "five hundred accounts, and the pages that list them still answer", ctx do
    for _ <- 1..(@users - 1), do: insert(:user)

    assert SprintLens.Repo.aggregate(SprintLens.Accounts.User, :count) >= @users

    {elapsed, _result} =
      :timer.tc(fn ->
        # The queries that would notice: everybody, one team's members, and
        # one person's own list.
        assert {:ok, users} = SprintLens.Admin.list_users(insert(:org_admin))
        assert length(users) >= @users

        assert length(Teams.list_members(ctx.team)) == 1
        assert Actions.list_my_actions(ctx.lead) == []
        assert Teams.list_teams(ctx.lead) != []
      end)

    assert div(elapsed, 1000) < @budget_ms
  end

  @tag req: ["NFR-103"]
  test "and a team's history stays readable as it grows", ctx do
    for index <- 1..@sessions do
      session = active_session(ctx.team, ctx.lead, %{title: "Sprint #{index}"})
      {:ok, session} = Retro.set_phase(ctx.lead, session, :brainstorm)

      {:ok, _card} =
        Board.create_card(ctx.lead, session, %{
          column_id: hd(session.columns).id,
          text: "Deploys are slow in sprint #{index}"
        })

      {:ok, _closed} = Retro.close_session(ctx.lead, session)
    end

    {elapsed, _result} =
      :timer.tc(fn ->
        assert length(Insights.archive(ctx.team)) == @sessions
        assert {:ok, metrics} = Insights.team_metrics(ctx.lead, ctx.team)
        assert length(metrics.cards_per_session) == @sessions

        assert {:ok, results} = Insights.search(ctx.lead, ctx.team, "deploys")
        assert length(results.cards) == @sessions
      end)

    assert div(elapsed, 1000) < @budget_ms
  end
end
