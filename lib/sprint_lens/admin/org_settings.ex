defmodule SprintLens.Admin.OrgSettings do
  @moduledoc """
  The organisation's own configuration (section 6.3, ORG_SETTINGS, FR-802).

  One row, seeded by the migration, read by id. There is no create path
  because there is nothing to create — see the migration for why that is a
  design decision rather than an omission.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias SprintLens.Teams.Team

  @type t :: %__MODULE__{}

  # The singleton's id. Named rather than inlined so the two places that use
  # it cannot drift.
  @id 1

  @languages ~w(th en)

  schema "org_settings" do
    field :default_language, :string
    field :default_vote_budget, :integer
    field :retention_days, :integer
    field :ai_enabled, :boolean, default: true
    field :webhooks_enabled, :boolean, default: true

    timestamps(type: :utc_datetime)
  end

  @doc """
  The singleton's id.
  """
  @spec id() :: pos_integer()
  def id, do: @id

  @doc """
  The languages the organisation can default to (FR-802, FR-906).
  """
  @spec languages() :: [String.t()]
  def languages, do: @languages

  @doc """
  A changeset for the settings form (FR-802, FR-806).
  """
  def changeset(settings, attrs) do
    {min_budget, max_budget} = Team.vote_budget_bounds()

    settings
    |> cast(attrs, [
      :default_language,
      :default_vote_budget,
      :retention_days,
      :ai_enabled,
      :webhooks_enabled
    ])
    |> validate_required([:default_language, :default_vote_budget, :retention_days])
    |> validate_inclusion(:default_language, @languages)
    |> validate_number(:default_vote_budget,
      greater_than_or_equal_to: min_budget,
      less_than_or_equal_to: max_budget
    )
    # A month at the short end, ten years at the long. Shorter than a month
    # would delete a retrospective before the team's next one; the upper bound
    # exists so a typo cannot mean "keep everything forever" by accident.
    |> validate_number(:retention_days, greater_than_or_equal_to: 30, less_than_or_equal_to: 3650)
  end
end
