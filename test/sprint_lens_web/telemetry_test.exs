defmodule SprintLensWeb.TelemetryTest do
  use SprintLens.UnitCase, async: false

  alias SprintLensWeb.Telemetry

  defp metric_names, do: Enum.map(Telemetry.metrics(), &Enum.join(&1.name, "."))

  defp find_metric(name), do: Enum.find(Telemetry.metrics(), &(Enum.join(&1.name, ".") == name))

  describe "metrics/0" do
    @tag req: ["NFR-503"]
    test "defines the four operational metrics the spec names" do
      names = metric_names()

      assert "sprint_lens.sessions.active.count" in names
      assert "sprint_lens.realtime.broadcast.duration" in names
      assert "sprint_lens.webhook.delivery.stop.count" in names
      assert "sprint_lens.ai.job.stop.count" in names
    end

    @tag req: ["NFR-503"]
    test "tags webhook deliveries by outcome so failures are countable" do
      assert :outcome in find_metric("sprint_lens.webhook.delivery.stop.count").tags
    end

    @tag req: ["NFR-503"]
    test "tags AI jobs by type and outcome" do
      metric = find_metric("sprint_lens.ai.job.stop.count")

      assert :type in metric.tags
      assert :outcome in metric.tags
    end

    @tag req: ["NFR-102"]
    test "measures realtime broadcast duration in milliseconds" do
      assert find_metric("sprint_lens.realtime.broadcast.duration").unit == :millisecond
    end

    @tag req: ["NFR-503"]
    test "keeps the framework and VM metrics that come with Phoenix" do
      names = metric_names()

      assert "phoenix.endpoint.stop.duration" in names
      assert "sprint_lens.repo.query.total_time" in names
      assert "vm.memory.total" in names
    end

    @tag req: ["NFR-503"]
    test "every metric declares a unit or is a plain count" do
      for metric <- Telemetry.metrics() do
        assert metric.unit != nil, "#{inspect(metric.name)} has no unit"
      end
    end
  end

  describe "measure_active_sessions/0" do
    @tag req: ["NFR-503"]
    test "emits the active session gauge" do
      handler = "test-active-sessions-#{System.unique_integer([:positive])}"
      test = self()

      :telemetry.attach(
        handler,
        [:sprint_lens, :sessions, :active],
        fn _event, measurements, _meta, _config -> send(test, {:gauge, measurements}) end,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler) end)

      Telemetry.measure_active_sessions()

      assert_receive {:gauge, %{count: count}}
      assert is_integer(count) and count >= 0
    end

    @tag req: ["NFR-503"]
    test "stays quiet rather than crashing when the session supervisor is not up" do
      pid = Process.whereis(SprintLens.Retro.SessionSupervisor)
      Process.unregister(SprintLens.Retro.SessionSupervisor)

      on_exit(fn ->
        if Process.whereis(SprintLens.Retro.SessionSupervisor) == nil do
          Process.register(pid, SprintLens.Retro.SessionSupervisor)
        end
      end)

      assert Telemetry.measure_active_sessions() == :ok

      Process.register(pid, SprintLens.Retro.SessionSupervisor)
    end
  end

  describe "supervision" do
    @tag req: ["NFR-503"]
    test "the poller runs under the telemetry supervisor" do
      assert [{:telemetry_poller, pid, :worker, _}] = Supervisor.which_children(Telemetry)
      assert is_pid(pid)
    end
  end
end
