defmodule SprintLens.Retro.VoteBudgetConcurrencyTest do
  @moduledoc """
  That a vote budget is a budget when two people spend it at the same moment.

  ## Why this test is not a `DataCase`

  The sandbox hands every process the same connection inside one transaction,
  which is the opposite of what is being tested here. This runs against the
  real database with two genuine connections, and cleans up after itself.

  ## Why it only runs on PostgreSQL

  SQLite takes one writer at a time, so the race cannot happen there and the
  test would prove nothing about the code — only about the engine. It is
  tagged, and `test/test_helper.exs` excludes it unless the build is against
  PostgreSQL.
  """

  use ExUnit.Case, async: false

  import SprintLens.Factory

  import Ecto.Query

  alias Ecto.Adapters.SQL.Sandbox
  alias SprintLens.Accounts.User
  alias SprintLens.Repo
  alias SprintLens.Retro
  alias SprintLens.Retro.Board
  alias SprintLens.Retro.Card
  alias SprintLens.Retro.Column
  alias SprintLens.Retro.Session
  alias SprintLens.Retro.Vote
  alias SprintLens.Teams.Membership
  alias SprintLens.Teams.Team

  @moduletag :postgres

  setup do
    Sandbox.mode(Repo, :auto)
    on_exit(fn -> Sandbox.mode(Repo, :manual) end)

    facilitator = insert(:user)
    team = team_with_lead(facilitator)
    voter = insert(:user)
    join_team(voter, team)

    # One vote to spend, and two different topics to spend it on — so the only
    # thing that can stop the second vote is the budget itself.
    session = active_session(team, facilitator, %{vote_budget: 1, multi_vote: false})
    {:ok, session} = Retro.set_phase(facilitator, session, :brainstorm)
    column = hd(session.columns)

    {:ok, first} = Board.create_card(voter, session, %{column_id: column.id, text: "Slow builds"})
    {:ok, second} = Board.create_card(voter, session, %{column_id: column.id, text: "Flaky CI"})

    {:ok, session} = Retro.set_phase(facilitator, session, :group)
    {:ok, session} = Retro.set_phase(facilitator, session, :vote)

    on_exit(&destroy/0)

    %{session: session, voter: voter, cards: [first, second]}
  end

  @tag req: ["FR-403"]
  test "a budget of one buys one vote, even when two are cast at once", ctx do
    [first, second] = ctx.cards

    results =
      [first, second]
      |> Enum.map(fn card ->
        Task.async(fn -> Board.cast_vote(ctx.voter, ctx.session, {:card, card.id}) end)
      end)
      |> Task.await_many(10_000)

    accepted = Enum.count(results, &match?({:ok, _vote}, &1))
    refused = Enum.count(results, &match?({:error, :vote_budget_exceeded, _details}, &1))

    assert accepted == 1, "both votes were accepted: #{inspect(results)}"
    assert refused == 1, "expected one refusal, got: #{inspect(results)}"

    # And the database agrees, which is the part that was wrong: before the
    # session row was locked, both transactions read a budget of one as unspent
    # and both inserted.
    assert Repo.aggregate(from(v in Vote, where: v.session_id == ^ctx.session.id), :count) == 1
  end

  # A sweep rather than a targeted delete. This test writes outside the
  # sandbox, so anything it leaves behind is still there for every test that
  # follows — and two of them count rows across the whole table. Clearing the
  # tables it touches is the only cleanup that cannot miss something: the
  # sandbox rolls back everything else, so empty is exactly the state the rest
  # of the suite expects. Seeded rows (the built-in templates, the
  # organisation's settings) are in other tables and are left alone.
  defp destroy do
    for schema <- [Vote, Card, Column, Session, Membership, Team, User] do
      Repo.delete_all(schema)
    end
  end
end
