defmodule SprintLens.Retro.Column do
  @moduledoc """
  One board column in a session (section 6.3, COLUMN).

  Columns are copied onto the session when it is created rather than read
  from the template each time. A team editing a template must not silently
  rewrite the headings of a retrospective that already happened, and a recap
  has to keep showing the board as it was (FR-602).
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias SprintLens.Changesets
  alias SprintLens.Retro.Session

  @type t :: %__MODULE__{}

  schema "retro_columns" do
    field :name, :string
    field :hint, :string
    field :position, :integer

    # Whether the heading is the product's wording or the team's. Decided when
    # the session is created and never revisited, for the same reason the name
    # itself is copied rather than read back from the template. It is what
    # lets the interface translate our words (FR-906) without ever translating
    # theirs (FR-909).
    field :from_builtin, :boolean, default: false

    belongs_to :session, Session

    timestamps(type: :utc_datetime)
  end

  @doc """
  A changeset for a column of a newly created session.
  """
  def changeset(column, attrs) do
    column
    |> cast(attrs, [:session_id, :name, :hint, :position, :from_builtin])
    |> validate_required([:name, :position])
    |> Changesets.trim(:name)
    |> validate_length(:name, min: 1, max: 80)
    |> validate_length(:hint, max: 200)
    |> validate_number(:position, greater_than_or_equal_to: 0)
    |> unique_constraint([:session_id, :position])
  end

  # No `foreign_key_constraint(:session_id)`: SQLite reports a violated
  # foreign key without naming the constraint, so Ecto cannot turn it into a
  # field error. Columns are only ever created inside
  # `SprintLens.Retro.create_session/3`, in the same transaction as their
  # session, so a dangling session_id is a bug rather than user input.

  @doc """
  Turns a template's stored column layout into changeset attributes.

  `from_builtin?` says whether the wording came from the product or from the
  team, and is stamped on every column here because it is true of the layout
  as a whole rather than of any one column.
  """
  @spec attrs_from_template([map()], boolean()) :: [map()]
  def attrs_from_template(columns, from_builtin?) do
    columns
    |> Enum.with_index()
    |> Enum.map(fn {column, position} ->
      %{
        name: Map.get(column, "name"),
        hint: Map.get(column, "hint"),
        position: position,
        from_builtin: from_builtin?
      }
    end)
  end
end
