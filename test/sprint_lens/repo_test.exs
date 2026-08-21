defmodule SprintLens.RepoTest do
  use SprintLens.DataCase

  alias SprintLens.Accounts.User

  describe "which database this build talks to" do
    # SQLite for development and test, PostgreSQL for production, and the
    # application correct on either. The two predicates exist so the handful
    # of places that genuinely differ can say so out loud rather than guessing
    # from a query that happens to work.
    @tag req: ["NFR-402"]
    test "is decided once, and the two answers never disagree" do
      adapter = Application.get_env(:sprint_lens, :database_adapter)

      assert Repo.sqlite?() == (adapter == Ecto.Adapters.SQLite3)
      assert Repo.postgres?() == (adapter == Ecto.Adapters.Postgres)
      # Through a list, because the compiler folds both calls to literals and
      # then helpfully points out that the obvious form is always true.
      assert Enum.count([Repo.sqlite?(), Repo.postgres?()], & &1) == 1
    end

    @tag req: ["NFR-402"]
    test "and it is the adapter the repository was compiled against" do
      assert Repo.__adapter__() == Application.get_env(:sprint_lens, :database_adapter)
    end
  end

  describe "like_operator/0" do
    # SQLite's LIKE ignores case for ASCII and PostgreSQL's does not. Getting
    # this wrong raises nothing: search simply stops finding things.
    @tag req: ["FR-603"]
    test "is the spelling this database understands" do
      expected = if Repo.sqlite?(), do: "LIKE", else: "ILIKE"

      assert Repo.like_operator() == expected
    end
  end

  describe "to_float/1" do
    # Tested for both shapes on both adapters, because only one of them can
    # ever arrive in a given build and the other clause would otherwise be
    # dead code that nobody notices is wrong.
    @tag req: ["FR-604"]
    test "accepts what either database returns for an average" do
      assert Repo.to_float(Decimal.new("4.25")) == 4.25
      assert Repo.to_float(4.25) == 4.25
      assert Repo.to_float(4) == 4.0
    end
  end

  describe "fetch/2" do
    @tag req: ["FR-919"]
    test "an id that is not a number is nothing found rather than a crash" do
      refute Repo.fetch(User, "not-an-id")
    end
  end
end
