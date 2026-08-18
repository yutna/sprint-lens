defmodule SprintLensWeb.Telemetry do
  @moduledoc """
  Metric definitions and the periodic measurement poller.

  Beyond the framework and VM metrics that ship with Phoenix, NFR-503 names
  four the operator actually needs: active sessions, realtime delivery
  latency, webhook failures and AI job outcomes. Those are defined here and
  emitted from the contexts that own them.
  """

  use Supervisor

  import Telemetry.Metrics

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl Supervisor
  def init(_arg) do
    children = [
      # Telemetry poller will execute the given period measurements
      # every 10_000ms. Learn more here: https://telemetry-metrics.hexdocs.pm
      {:telemetry_poller, measurements: periodic_measurements(), period: 10_000}
      # Add reporters as children of your supervision tree.
      # {Telemetry.Metrics.ConsoleReporter, metrics: metrics()}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def metrics do
    [
      # Phoenix Metrics
      summary("phoenix.endpoint.start.system_time",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.endpoint.stop.duration",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.start.system_time",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.exception.duration",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.stop.duration",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.socket_connected.duration",
        unit: {:native, :millisecond}
      ),
      sum("phoenix.socket_drain.count"),
      summary("phoenix.channel_joined.duration",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.channel_handled_in.duration",
        tags: [:event],
        unit: {:native, :millisecond}
      ),

      # Database Metrics
      summary("sprint_lens.repo.query.total_time",
        unit: {:native, :millisecond},
        description: "The sum of the other measurements"
      ),
      summary("sprint_lens.repo.query.decode_time",
        unit: {:native, :millisecond},
        description: "The time spent decoding the data received from the database"
      ),
      summary("sprint_lens.repo.query.query_time",
        unit: {:native, :millisecond},
        description: "The time spent executing the query"
      ),
      summary("sprint_lens.repo.query.queue_time",
        unit: {:native, :millisecond},
        description: "The time spent waiting for a database connection"
      ),
      summary("sprint_lens.repo.query.idle_time",
        unit: {:native, :millisecond},
        description:
          "The time the connection spent waiting before being checked out for the query"
      ),

      # Application Metrics (NFR-503)
      last_value("sprint_lens.sessions.active.count",
        description: "Retrospective sessions currently in the active state"
      ),
      summary("sprint_lens.realtime.broadcast.duration",
        tags: [:event],
        unit: {:native, :millisecond},
        description: "Time from accepting a board mutation to broadcasting it (NFR-102)"
      ),
      counter("sprint_lens.webhook.delivery.stop.count",
        tags: [:event, :outcome],
        description: "Webhook deliveries by outcome, so failures are visible (FR-706)"
      ),
      summary("sprint_lens.webhook.delivery.stop.duration",
        unit: {:native, :millisecond}
      ),
      counter("sprint_lens.ai.job.stop.count",
        tags: [:type, :outcome],
        description: "AI job outcomes: ready, failed or timed out (AI-006)"
      ),
      summary("sprint_lens.ai.job.stop.duration",
        tags: [:type],
        unit: {:native, :millisecond}
      ),

      # VM Metrics
      summary("vm.memory.total", unit: {:byte, :kilobyte}),
      summary("vm.total_run_queue_lengths.total"),
      summary("vm.total_run_queue_lengths.cpu"),
      summary("vm.total_run_queue_lengths.io")
    ]
  end

  @doc """
  Emits the active-session gauge. Public so a test can assert it runs without
  waiting ten seconds for the poller.

  Counts live `SessionServer` processes rather than rows with `state: active`:
  a session nobody is connected to is not consuming realtime capacity, and
  this gauge exists to tell an operator how much load the node is carrying.
  """
  def measure_active_sessions do
    # The poller is a sibling of the session supervisor, so it can tick while
    # that supervisor is still starting or already shutting down. A gauge is
    # not worth crashing the poller over.
    case Process.whereis(SprintLens.Retro.SessionSupervisor) do
      nil ->
        :ok

      _pid ->
        %{active: active} = DynamicSupervisor.count_children(SprintLens.Retro.SessionSupervisor)
        :telemetry.execute([:sprint_lens, :sessions, :active], %{count: active}, %{})
    end
  end

  defp periodic_measurements do
    [
      {__MODULE__, :measure_active_sessions, []}
    ]
  end
end
