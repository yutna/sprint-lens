defmodule SprintLens.Repo do
  use Ecto.Repo,
    otp_app: :sprint_lens,
    adapter: Ecto.Adapters.SQLite3

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
