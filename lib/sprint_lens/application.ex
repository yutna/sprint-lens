defmodule SprintLens.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl Application
  def start(_type, _args) do
    # Crashes go wherever this deployment configured (NFR-504). Attached
    # before anything can raise.
    SprintLens.ErrorReporter.attach()

    children = [
      SprintLensWeb.Telemetry,
      SprintLens.Repo,
      {Ecto.Migrator,
       repos: Application.fetch_env!(:sprint_lens, :ecto_repos), skip: skip_migrations?()},
      {DNSCluster, query: Application.get_env(:sprint_lens, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: SprintLens.PubSub},
      {SprintLens.RateLimit, clean_period: :timer.minutes(5)},
      {Oban, Application.fetch_env!(:sprint_lens, Oban)},
      SprintLensWeb.Presence,
      # Time-based orchestration for live sessions: facilitator hand-off
      # (FR-207) and timer expiry (FR-208). Not a source of truth — the
      # database is (NFR-402).
      {Registry, keys: :unique, name: SprintLens.Retro.SessionRegistry},
      {DynamicSupervisor, strategy: :one_for_one, name: SprintLens.Retro.SessionSupervisor},
      # Start to serve requests, typically the last entry
      SprintLensWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: SprintLens.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl Application
  def config_change(changed, _new, removed) do
    SprintLensWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp skip_migrations? do
    # By default, sqlite migrations are run when using a release
    System.get_env("RELEASE_NAME") == nil
  end
end
