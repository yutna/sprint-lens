defmodule SprintLens.MixProject do
  use Mix.Project

  def project do
    [
      app: :sprint_lens,
      version: "0.1.0",
      elixir: "~> 1.17",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      compilers: [:phoenix_live_view] ++ Mix.compilers(),
      listeners: [Phoenix.CodeReloader],
      test_coverage: [tool: ExCoveralls],
      dialyzer: [
        plt_add_apps: [:mix, :ex_unit],
        plt_local_path: "priv/plts",
        plt_core_path: "priv/plts",
        ignore_warnings: ".dialyzer_ignore.exs",
        list_unused_filters: true
      ]
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {SprintLens.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  def cli do
    [
      preferred_envs: [
        precommit: :test,
        dialyzer: :test,
        ci: :test,
        verify: :test,
        trace: :test,
        "sprint_lens.trace": :test,
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.html": :test,
        "coveralls.json": :test,
        e2e: :e2e,
        "sprint_lens.e2e": :e2e
      ]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:bcrypt_elixir, "~> 3.0"},
      {:phoenix, "~> 1.8.9"},
      {:phoenix_ecto, "~> 4.5"},
      {:ecto_sql, "~> 3.13"},
      {:ecto_sqlite3, ">= 0.0.0"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 1.2.0"},
      {:lazy_html, ">= 0.1.0", only: :test},
      {:phoenix_live_dashboard, "~> 0.8.3"},
      {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.5", runtime: Mix.env() == :dev},
      {:heroicons,
       github: "tailwindlabs/heroicons",
       tag: "v2.2.0",
       sparse: "optimized",
       app: false,
       compile: false,
       depth: 1},
      {:daisyui,
       github: "saadeghi/daisyui",
       tag: "v5.5.20",
       sparse: "packages/bundle",
       app: false,
       compile: false,
       depth: 1},
      {:swoosh, "~> 1.16"},
      {:req, "~> 0.5"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 1.0"},
      {:jason, "~> 1.2"},
      {:dns_cluster, "~> 0.2.0"},
      {:bandit, "~> 1.5"},
      # Background jobs: webhook retries (FR-706), retention purge (FR-803), AI jobs (AI-005)
      {:oban, "~> 2.23"},
      # Rate limiting per user and per IP (NFR-202)
      {:hammer, "~> 7.4"},
      # Locale-aware dates, times and numbers (FR-908). `tz` supplies the
      # time zone database Elixir needs to render UTC values in the viewer's
      # zone (section 11).
      {:tz, "~> 0.28"},
      {:ex_cldr, "~> 2.47"},
      {:ex_cldr_dates_times, "~> 2.25"},
      {:ex_cldr_numbers, "~> 2.38"},
      # Tooling
      {:excoveralls, "~> 0.18", only: :test},
      {:ex_machina, "~> 2.8", only: :test},
      {:mox, "~> 1.2", only: :test},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "ecto.setup", "assets.setup", "assets.build"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["compile", "tailwind sprint_lens", "esbuild sprint_lens"],
      "assets.deploy": [
        "tailwind sprint_lens --minify",
        "esbuild sprint_lens --minify",
        "phx.digest"
      ],
      precommit: ["compile --warnings-as-errors", "deps.unlock --unused", "format", "test"],
      # Requirement traceability report (see Mix.Tasks.SprintLens.Trace)
      trace: ["sprint_lens.trace"],
      # Per-milestone gate. Every milestone must leave this green.
      # Traceability ran in report mode while the milestones were landing —
      # requirements a later milestone owned were legitimately uncovered until
      # it arrived. The last one has landed, so this is the strict form now.
      ci: [
        "compile --warnings-as-errors",
        "format --check-formatted",
        "deps.unlock --check-unused",
        "credo --strict",
        "ecto.create --quiet",
        "ecto.migrate --quiet",
        "coveralls",
        "dialyzer",
        "sprint_lens.trace --write"
      ],
      # Acceptance gate. The finished app must pass this.
      verify: ["ci", "e2e"],
      # Playwright end-to-end suite (see e2e/)
      e2e: ["sprint_lens.e2e"]
    ]
  end
end
