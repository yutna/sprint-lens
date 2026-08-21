import Config

# The `:e2e` environment runs a real server against a real (throwaway) SQLite
# file so Playwright can drive the app in a browser. It is production-shaped
# — no code reloading, no sandbox — but with dev-friendly error pages so a
# failing e2e run is debuggable.

config :sprint_lens, SprintLens.Repo, pool_size: 10

# Which database, and how to reach it. `DATABASE_ADAPTER` is read here rather
# than taken from `config/config.exs` because config files do not share
# bindings, and repeating one line beats inventing a way to. The connection
# details come from the environment so a developer, a compose file and a
# continuous integration service container can each point at their own.
if System.get_env("DATABASE_ADAPTER") == "postgres" do
  config :sprint_lens, SprintLens.Repo,
    username: System.get_env("PGUSER", "postgres"),
    password: System.get_env("PGPASSWORD", "postgres"),
    hostname: System.get_env("PGHOST", "localhost"),
    port: String.to_integer(System.get_env("PGPORT", "5432")),
    database: "sprint_lens_e2e"
else
  config :sprint_lens, SprintLens.Repo, database: Path.expand("../sprint_lens_e2e.db", __DIR__)
end

config :sprint_lens, SprintLensWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: String.to_integer(System.get_env("E2E_PORT") || "4010")],
  secret_key_base: "aQvsm5s5tqM7GCLnn8JYEB6ExPGGwYmMFCKEcprjyvcW5cRfCU0O2q3lOdi7bLL1",
  check_origin: false,
  debug_errors: true,
  code_reloader: false,
  server: true

config :sprint_lens, SprintLens.Mailer, adapter: Swoosh.Adapters.Local
config :swoosh, :api_client, false

# The mailbox preview is how the e2e suite gets the sign-in link the app
# emails: registration deliberately has no password step (see
# `SprintLensWeb.UserLive.Registration`).
config :sprint_lens, dev_routes: true

config :logger, level: :warning

config :phoenix, :plug_init_mode, :runtime

# Real jobs run here — webhook delivery and AI suggestions are exercised
# end to end (with stub endpoints), not asserted on in-memory.
config :sprint_lens, Oban, testing: :disabled

# Short enough that an e2e test can observe the hand-off without a long wait,
# long enough that a normal page transition never trips it (FR-207).
config :sprint_lens, :facilitator_grace_ms, 3_000

# Same reason as the test environment: the browser suite exercises every AI
# path without a model or a network (AI-004).
config :sprint_lens, :ai_adapter, SprintLens.AI.FakeAdapter
