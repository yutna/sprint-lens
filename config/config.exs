# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :sprint_lens, :scopes,
  user: [
    default: true,
    module: SprintLens.Accounts.Scope,
    assign_key: :current_scope,
    access_path: [:user, :id],
    schema_key: :user_id,
    schema_type: :id,
    schema_table: :users,
    test_data_fixture: SprintLens.AccountsFixtures,
    test_setup_helper: :register_and_log_in_user
  ]

config :sprint_lens,
  ecto_repos: [SprintLens.Repo],
  generators: [timestamp_type: :utc_datetime]

# Times are stored in UTC and rendered in the viewer's zone (section 11), so
# the runtime needs a time zone database.
config :elixir, :time_zone_database, Tz.TimeZoneDatabase

# SQLite tuning shared by every environment.
#
# `synchronous: :full` is deliberate: NFR-402 says a mutation may only be
# acknowledged once it is durable in the datastore. `:normal` (the adapter
# default) can lose the last transactions on power loss under WAL.
#
# `default_transaction_mode: :immediate` takes the write lock up front. Our
# board mutations read-then-write inside one transaction (vote budgets,
# card positions), and a deferred transaction that upgrades to a writer can
# fail with SQLITE_BUSY instead of waiting on `busy_timeout`.
config :sprint_lens, SprintLens.Repo,
  journal_mode: :wal,
  synchronous: :full,
  foreign_keys: :on,
  busy_timeout: 5_000,
  default_transaction_mode: :immediate,
  cache_size: -64_000,
  temp_store: :memory

# Background jobs. `Oban.Engines.Lite` is the SQLite engine.
#   * webhook delivery with exponential backoff (FR-706)
#   * scheduled retention purge (FR-803)
#   * AI suggestion jobs (AI-005, AI-006)
config :sprint_lens, Oban,
  engine: Oban.Engines.Lite,
  # SQLite has no `LISTEN`/`NOTIFY`, so job notifications travel over the
  # cluster's process groups instead of the database.
  notifier: Oban.Notifiers.PG,
  repo: SprintLens.Repo,
  queues: [default: 5, webhooks: 5, retention: 1, ai: 2],
  plugins: [
    {Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 7},
    {Oban.Plugins.Cron,
     crontab: [
       # Once a day, a little after midnight UTC: the sweep asks which action
       # items have come due and announces each one once (FR-704).
       {"5 0 * * *", SprintLens.Workers.ActionDueSweep},
       # And an hour later, what has aged past the retention period
       # (FR-803). Separated so a slow purge cannot delay the reminders.
       {"5 1 * * *", SprintLens.Workers.RetentionPurge}
     ]}
  ]

# The AI provider (AI-004). The reference adapter shells out to the Claude
# Code CLI (AI-007); test and e2e override this with a fake, which is the
# proof that the interface is provider-agnostic.
config :sprint_lens, :ai_adapter, SprintLens.AI.ClaudeCliAdapter

# Rate limiting per user and per IP (NFR-202). `{limit, scale_ms}` per bucket.
config :sprint_lens, SprintLens.RateLimit,
  enabled: true,
  api: {300, 60_000},
  auth: {10, 60_000},
  realtime: {600, 60_000}

# Sign-in session inactivity window (NFR-206).
config :sprint_lens, :session_inactivity_days, 14

# How long the facilitator may be disconnected before the role is offered to
# the remaining participants (FR-207). Overridden to a tiny value in tests.
config :sprint_lens, :facilitator_grace_ms, 60_000

# Configure the endpoint
config :sprint_lens, SprintLensWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: SprintLensWeb.ErrorHTML, json: SprintLensWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: SprintLens.PubSub,
  live_view: [signing_salt: "fS8Avtfq"]

# Configure LiveView
config :phoenix_live_view,
  # the attribute set on all root tags. Used for Phoenix.LiveView.ColocatedCSS.
  root_tag_attribute: "phx-r"

# Configure the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :sprint_lens, SprintLens.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  sprint_lens: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.3.0",
  sprint_lens: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Structured JSON logs with a request correlation id on every line (NFR-502).
# Dev overrides this with a human-readable formatter.
config :logger, :default_handler, formatter: {SprintLens.LogFormatter, %{}}

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
