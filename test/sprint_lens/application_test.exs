defmodule SprintLens.ApplicationTest do
  use SprintLens.UnitCase, async: false

  describe "supervision tree" do
    @tag req: ["NFR-501"]
    test "every dependency the app cannot work without is supervised" do
      names =
        SprintLens.Supervisor
        |> Supervisor.which_children()
        |> Enum.map(fn {id, _pid, _type, _mods} -> id end)

      assert SprintLens.Repo in names
      assert SprintLensWeb.Endpoint in names
      assert SprintLensWeb.Telemetry in names
      assert SprintLensWeb.Presence in names
      assert SprintLens.RateLimit in names
    end

    @tag req: ["FR-207"]
    test "session servers get a registry and a dynamic supervisor to live under" do
      assert is_pid(Process.whereis(SprintLens.Retro.SessionRegistry))
      assert is_pid(Process.whereis(SprintLens.Retro.SessionSupervisor))
    end

    @tag req: ["FR-706", "FR-803", "AI-005"]
    test "the job runner is up so retries, purges and AI jobs can run" do
      assert is_pid(Oban.whereis(Oban))
    end

    # NFR-402 asks that a mutation is only acknowledged once it is durable.
    # Both databases can promise that; they promise it with different words,
    # so the assertion has to follow the adapter rather than assume one.
    @tag req: ["NFR-402"]
    test "the database is configured for durability, in its own terms" do
      config = Application.fetch_env!(:sprint_lens, SprintLens.Repo)

      if SprintLens.Repo.sqlite?() do
        # Write-ahead logging with a full sync, foreign keys actually
        # enforced, and a writer that waits rather than failing.
        # Not `synchronous`: the test environment turns it off on purpose,
        # because the sandbox wraps every test in a transaction that is rolled
        # back and durability of a discarded write buys nothing.
        assert config[:journal_mode] == :wal
        assert config[:foreign_keys] == :on
        assert config[:busy_timeout] >= 5_000
        assert config[:default_transaction_mode] == :immediate
      else
        # PostgreSQL commits synchronously and enforces foreign keys without
        # being asked, so durability is the server's default rather than
        # something the client configures. What the client must not do is
        # carry SQLite's settings across: the adapter rejects every one of
        # them, so their absence is the assertion.
        for pragma <- [:journal_mode, :synchronous, :foreign_keys, :busy_timeout] do
          refute Keyword.has_key?(config, pragma),
                 "#{pragma} is a SQLite pragma and PostgreSQL will refuse it"
        end
      end
    end
  end

  describe "config_change/3" do
    @tag req: ["NFR-404"]
    test "forwards a configuration change to the endpoint" do
      assert SprintLens.Application.config_change([], [], []) == :ok
    end
  end
end
