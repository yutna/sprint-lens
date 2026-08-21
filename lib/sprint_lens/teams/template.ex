defmodule SprintLens.Teams.Template do
  @moduledoc """
  A reusable column layout a session is created from (section 6.3,
  RETRO_TEMPLATE).

  A template with no team is one of the built-ins every team can use
  (FR-201); one with a team is that team's own (FR-202).
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias SprintLens.Changesets
  alias SprintLens.Teams.Team

  @type t :: %__MODULE__{}

  # FR-202: two to six columns. Fewer than two is not a retrospective board;
  # more than six stops fitting on the narrow screens FR-902 has to support.
  @min_columns 2
  @max_columns 6

  schema "retro_templates" do
    field :name, :string
    field :is_builtin, :boolean, default: false
    field :columns, SprintLens.Types.JsonList, default: []

    belongs_to :team, Team

    timestamps(type: :utc_datetime)
  end

  @doc """
  The permitted number of columns (FR-202).
  """
  @spec column_bounds() :: {pos_integer(), pos_integer()}
  def column_bounds, do: {@min_columns, @max_columns}

  @doc """
  A changeset for a team's own template (FR-202).
  """
  def changeset(template, attrs) do
    template
    |> cast(attrs, [:name, :columns])
    |> validate_required([:name])
    |> Changesets.trim(:name)
    |> validate_length(:name, min: 1, max: 80)
    |> normalise_columns()
    |> validate_columns()
  end

  @doc """
  The column names of a template, in order.
  """
  @spec column_names(t()) :: [String.t()]
  def column_names(%__MODULE__{columns: columns}) do
    Enum.map(columns, &Map.get(&1, "name"))
  end

  # Columns arrive with string keys from a form or from JSON, and with atom
  # keys from Elixir callers. Both are normalised to string keys, which is
  # what the database stores.
  defp normalise_columns(changeset) do
    case fetch_change(changeset, :columns) do
      {:ok, columns} -> put_change(changeset, :columns, Enum.map(columns, &normalise_column/1))
      :error -> changeset
    end
  end

  defp normalise_column(%{"name" => name} = column) do
    %{"name" => trim(name), "hint" => trim(column["hint"])}
  end

  defp normalise_column(%{name: name} = column) do
    %{"name" => trim(name), "hint" => trim(Map.get(column, :hint))}
  end

  # A row where only the hint was filled in. Kept rather than dropped, so the
  # person is told the column needs a name instead of watching their typing
  # disappear.
  defp normalise_column(%{} = column) do
    %{"name" => nil, "hint" => trim(column["hint"] || Map.get(column, :hint))}
  end

  defp trim(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp trim(_value), do: nil

  defp validate_columns(changeset) do
    columns = get_field(changeset, :columns) || []

    changeset
    |> validate_column_count(length(columns))
    |> validate_column_names(columns)
  end

  defp validate_column_count(changeset, count) when count < @min_columns do
    add_error(changeset, :columns, "must have at least %{count} columns", count: @min_columns)
  end

  defp validate_column_count(changeset, count) when count > @max_columns do
    add_error(changeset, :columns, "must have at most %{count} columns", count: @max_columns)
  end

  defp validate_column_count(changeset, _count), do: changeset

  defp validate_column_names(changeset, columns) do
    if Enum.all?(columns, &named?/1) do
      changeset
    else
      add_error(changeset, :columns, "every column needs a name")
    end
  end

  defp named?(%{"name" => name}) when is_binary(name), do: name != ""
  defp named?(_column), do: false
end
