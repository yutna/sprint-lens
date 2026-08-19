defmodule SprintLens.Teams.Team do
  @moduledoc """
  A group that runs retrospectives together (section 6.3, TEAM).

  Archiving is not deleting: an archived team is read-only and keeps its
  history until a retention purge or an explicit admin purge removes it
  (FR-106, FR-803, FR-804).
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias SprintLens.Changesets
  alias SprintLens.Teams.Membership
  alias SprintLens.Teams.Template

  @type t :: %__MODULE__{}

  # A vote budget of zero would make the vote phase pointless; the upper bound
  # keeps the board usable on a phone (FR-902).
  @min_vote_budget 1
  @max_vote_budget 20

  schema "teams" do
    field :name, :string
    field :description, :string
    field :is_archived, :boolean, default: false
    field :default_vote_budget, :integer, default: 5
    field :ai_opt_in, :boolean, default: false

    belongs_to :default_template, Template

    has_many :memberships, Membership
    has_many :templates, Template

    timestamps(type: :utc_datetime)
  end

  @doc """
  The permitted vote budget range (FR-401).
  """
  @spec vote_budget_bounds() :: {pos_integer(), pos_integer()}
  def vote_budget_bounds, do: {@min_vote_budget, @max_vote_budget}

  @doc """
  A changeset for creating a team (FR-101). Only a name is required.
  """
  def create_changeset(team, attrs) do
    team
    |> cast(attrs, [:name, :description])
    |> validate_name()
    |> validate_length(:description, max: 2000)
  end

  @doc """
  A changeset for the settings a Team Lead controls (FR-105).
  """
  def settings_changeset(team, attrs) do
    team
    |> cast(attrs, [
      :name,
      :description,
      :default_template_id,
      :default_vote_budget,
      :ai_opt_in
    ])
    |> validate_name()
    |> validate_length(:description, max: 2000)
    |> validate_number(:default_vote_budget,
      greater_than_or_equal_to: @min_vote_budget,
      less_than_or_equal_to: @max_vote_budget
    )
    |> foreign_key_constraint(:default_template_id)
  end

  @doc """
  A changeset for archiving or restoring a team (FR-106).
  """
  def archive_changeset(team, is_archived) when is_boolean(is_archived) do
    change(team, is_archived: is_archived)
  end

  defp validate_name(changeset) do
    changeset
    |> validate_required([:name])
    |> Changesets.trim(:name)
    |> validate_length(:name, min: 1, max: 80)
  end
end
