# Tests tagged `:postgres` need a database that can hold two transactions open
# at once. SQLite cannot — it takes one writer at a time, which is exactly why
# the races they cover cannot happen there — so on a SQLite build they are
# excluded rather than failing or, worse, passing for the wrong reason.
exclusions = if SprintLens.Repo.postgres?(), do: [], else: [:postgres]

ExUnit.start(exclude: exclusions)
Ecto.Adapters.SQL.Sandbox.mode(SprintLens.Repo, :manual)
