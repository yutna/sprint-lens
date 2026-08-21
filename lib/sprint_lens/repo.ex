defmodule SprintLens.Repo do
  @moduledoc """
  The repository, on whichever of the two databases this build was made for.

  SQLite is the development and test database, and PostgreSQL is the supported
  production one. Both have to work, and the choice is made once at compile
  time by `DATABASE_ADAPTER` — Ecto needs its adapter before the module
  exists, so this is not something a release can be told at boot.

  Two rules follow, and they are in `AGENTS.md` as well because they are easy
  to break by accident:

    * no adapter-specific SQL in a context without an explicit, commented
      branch, and both branches tested;
    * where the two disagree, PostgreSQL decides what is correct. SQLite is
      more forgiving in several places, and code written for the forgiving one
      is code that breaks in production.
  """

  @adapter Application.compile_env(:sprint_lens, :database_adapter, Ecto.Adapters.SQLite3)
  @sqlite? @adapter == Ecto.Adapters.SQLite3

  use Ecto.Repo, otp_app: :sprint_lens, adapter: @adapter

  @doc """
  Whether this build talks to SQLite.

  For the handful of places that genuinely have to differ — a pattern match
  that is case-insensitive on one engine and not the other, a durability
  setting that only one of them has. Resolved at compile time, because the
  adapter is.
  """
  @spec sqlite?() :: boolean()
  def sqlite?, do: @sqlite?

  @doc """
  Whether this build talks to PostgreSQL.
  """
  @spec postgres?() :: boolean()
  def postgres?, do: not @sqlite?

  @like_operator if @sqlite?, do: "LIKE", else: "ILIKE"

  @doc """
  How this database spells a case-insensitive pattern match.

  SQLite's `LIKE` already ignores case for ASCII; PostgreSQL's does not and
  needs `ILIKE`. Resolved here so the difference is named once instead of
  branched over at each of the four places that search.
  """
  @spec like_operator() :: String.t()
  def like_operator, do: @like_operator

  @doc """
  Whatever a database returned for an average, as a float.

  `avg()` over an integer column is a float on SQLite and a decimal on
  PostgreSQL, and `Float.round/2` has no clause for a decimal — which was a
  raise on the insights screen, a page a person opens rather than a background
  job. Converted once, here at the boundary, so nothing further in has to know
  which database it is talking to.
  """
  @spec to_float(Decimal.t() | float() | integer()) :: float()
  def to_float(%Decimal{} = value), do: Decimal.to_float(value)
  def to_float(value) when is_float(value), do: value
  def to_float(value) when is_integer(value), do: value * 1.0

  @doc """
  `get/2` for an id that arrived in a URL.

  A path segment is a string a stranger chose, so it may not be a number at
  all. `Repo.get/2` raises `Ecto.Query.CastError` on that, which turns a
  mistyped link into a 500 and a stack trace in the logs; here it is simply
  nothing found, which is what a caller asking for a record that cannot exist
  should be told (FR-919).
  """
  @spec fetch(module(), term()) :: Ecto.Schema.t() | nil
  def fetch(schema, id) do
    get(schema, id)
  rescue
    Ecto.Query.CastError -> nil
  end
end
