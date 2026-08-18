import Config

# Only in tests, remove the complexity from the password hashing algorithm
config :bcrypt_elixir, :log_rounds, 1

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :sprint_lens, SprintLens.Repo,
  database: Path.expand("../sprint_lens_test#{System.get_env("MIX_TEST_PARTITION")}.db", __DIR__),
  pool_size: 5,
  pool: Ecto.Adapters.SQL.Sandbox,
  # The sandbox holds every test inside an outer transaction, so per-test
  # durability is irrelevant and `:full` only slows the suite down.
  synchronous: :off

# Jobs are asserted on, never executed in the background, so every test can
# make deterministic assertions with `Oban.Testing`.
config :sprint_lens, Oban, testing: :manual

# Keep the facilitator hand-off deterministic without sleeping for a minute
# (FR-207).
config :sprint_lens, :facilitator_grace_ms, 50

# Off by default so a test that makes many requests does not trip a limiter it
# is not testing. The rate limit tests switch it back on for themselves.
config :sprint_lens, SprintLens.RateLimit,
  enabled: false,
  api: {300, 60_000},
  auth: {10, 60_000},
  realtime: {600, 60_000}

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :sprint_lens, SprintLensWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "hL+PaDwU7+tONKnSJndb4l1XvDTaq7Vow9Vn3Gkm3GZMnxqquMWgQuQca9izthT7",
  server: false

# In test we don't send emails
config :sprint_lens, SprintLens.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
