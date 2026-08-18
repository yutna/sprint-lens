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

    @tag req: ["NFR-402"]
    test "SQLite is configured for durability and for waiting rather than failing" do
      config = Application.fetch_env!(:sprint_lens, SprintLens.Repo)

      assert config[:journal_mode] == :wal
      assert config[:foreign_keys] == :on
      assert config[:busy_timeout] >= 5_000
      assert config[:default_transaction_mode] == :immediate
    end
  end

  describe "config_change/3" do
    @tag req: ["NFR-404"]
    test "forwards a configuration change to the endpoint" do
      assert SprintLens.Application.config_change([], [], []) == :ok
    end
  end
end
