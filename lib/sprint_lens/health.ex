defmodule SprintLens.Health do
  @moduledoc """
  Liveness and readiness checks over the app's critical dependencies (NFR-501).

  Liveness answers "is the VM up and serving?" and never touches a dependency,
  so a load balancer does not recycle a node that is merely waiting on its
  database. Readiness answers "can this node do useful work?" and probes every
  dependency the app cannot function without.

  Each check takes the thing it probes as an argument. That keeps the failure
  branches reachable from a test — a health check whose failure path has never
  run is not a health check.
  """

  alias SprintLens.Repo

  @type check :: %{name: atom(), status: :ok | :error, detail: String.t() | nil}
  @type report :: %{status: :ok | :error, checks: [check()]}

  @probe_sql "SELECT 1"

  @doc """
  Always `:ok` when the process answering is alive. Used for liveness probes.
  """
  @spec alive() :: report()
  def alive, do: %{status: :ok, checks: []}

  @doc """
  Runs every dependency check. The overall status is `:error` if any single
  check fails.
  """
  @spec ready() :: report()
  def ready, do: summarise([check_database(), check_jobs()])

  @doc """
  Combines individual checks into a report.
  """
  @spec summarise([check()]) :: report()
  def summarise(checks) do
    status = if Enum.all?(checks, &(&1.status == :ok)), do: :ok, else: :error

    %{status: status, checks: checks}
  end

  @doc """
  Probes the datastore with a trivial query.

  Two failure shapes are possible and both matter: the database answers with
  an error (corruption, a missing table, a locked file), or the repo is not
  running at all and the call raises.
  """
  @spec check_database(module(), String.t()) :: check()
  def check_database(repo \\ Repo, sql \\ @probe_sql) do
    case repo.query(sql, []) do
      {:ok, _result} -> ok(:database)
      {:error, error} -> error(:database, Exception.message(error))
    end
  rescue
    error -> error(:database, Exception.message(error))
  end

  @doc """
  Checks that the job runner is up. Without it, webhook deliveries (FR-706),
  the retention purge (FR-803) and AI jobs (AI-005) silently stop happening.
  """
  @spec check_jobs(atom()) :: check()
  def check_jobs(name \\ Oban) do
    # Oban registers its supervisor in its own registry rather than under a
    # plain process name, so `Process.whereis/1` would always say "down".
    case Oban.whereis(name) do
      nil -> error(:jobs, "#{inspect(name)} is not running")
      pid when is_pid(pid) -> ok(:jobs)
    end
  end

  @doc """
  The HTTP status code a report should be served with: 200 when healthy,
  503 when a dependency is down.
  """
  @spec http_status(report()) :: 200 | 503
  def http_status(%{status: :ok}), do: 200
  def http_status(%{status: :error}), do: 503

  defp ok(name), do: %{name: name, status: :ok, detail: nil}
  defp error(name, detail), do: %{name: name, status: :error, detail: detail}
end
