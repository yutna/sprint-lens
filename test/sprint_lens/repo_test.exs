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

  describe "fetch/2" do
    @tag req: ["FR-919"]
    test "an id that is not a number is nothing found rather than a crash" do
      refute Repo.fetch(User, "not-an-id")
    end
  end
end
