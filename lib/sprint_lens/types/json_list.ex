defmodule SprintLens.Types.JsonList do
  @moduledoc """
  A list of maps, stored as JSON in a text column.

  Used for a retrospective template's column layout, which is only ever read
  and written as a whole and so has no reason to be a table of its own
  (FR-202).

  It exists because `{:array, :map}` does not mean the same thing on both
  databases. `ecto_sqlite3` quietly encodes such a field to JSON on the way
  into a text column; PostgreSQL's adapter reads the type literally, tries to
  send a real array, and is told the column is text. Sixty-odd tests failed on
  that one difference.

  Doing the encoding here makes it the application's decision rather than an
  adapter's convenience, and the stored bytes are the same JSON either way —
  so a database written by one adapter is readable by the other.
  """

  use Ecto.Type

  @impl Ecto.Type
  def type, do: :string

  @impl Ecto.Type
  def cast(value) when is_list(value), do: {:ok, value}
  def cast(nil), do: {:ok, nil}
  def cast(_value), do: :error

  @impl Ecto.Type
  def load(value) when is_binary(value) do
    case Jason.decode(value) do
      {:ok, decoded} when is_list(decoded) -> {:ok, decoded}
      _not_a_list -> :error
    end
  end

  def load(nil), do: {:ok, nil}
  def load(_value), do: :error

  @impl Ecto.Type
  def dump(value) when is_list(value), do: Jason.encode(value)
  def dump(nil), do: {:ok, nil}
  def dump(_value), do: :error
end
