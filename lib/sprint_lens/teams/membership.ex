defmodule SprintLens.Teams.Membership do
  @moduledoc """
  Links a user to a team with a per-team role (section 6.3,
  TEAM_MEMBERSHIP).

  Team Lead and Member are per-team roles, so the same person can lead one
  team and merely belong to another (section 3.1).
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias SprintLens.Accounts.User
  alias SprintLens.Teams.Team

  @type t :: %__MODULE__{}
  @type role :: :lead | :member

  @roles ~w(lead member)

  schema "team_memberships" do
    field :role, :string, default: "member"

    belongs_to :user, User
    belongs_to :team, Team

    timestamps(type: :utc_datetime)
  end

  @doc """
  The per-team roles (section 3.1).
  """
  @spec roles() :: [String.t()]
  def roles, do: @roles

  @doc """
  A changeset for adding someone to a team or changing their role.
  """
  def changeset(membership, attrs) do
    membership
    |> cast(attrs, [:user_id, :team_id, :role])
    |> validate_required([:user_id, :team_id, :role])
    |> validate_inclusion(:role, @roles)
    |> unique_constraint([:team_id, :user_id],
      message: "is already a member of this team"
    )
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:team_id)
  end

  @doc """
  A changeset for the add-member form, which identifies people by email
  rather than by id (FR-102).
  """
  @spec invite_changeset(map()) :: Ecto.Changeset.t()
  def invite_changeset(attrs) do
    {%{email: nil, role: "member"}, %{email: :string, role: :string}}
    |> cast(attrs, [:email, :role])
    |> validate_required([:email])
    |> validate_inclusion(:role, @roles)
  end

  @doc """
  The role as an atom, which is what `SprintLens.Policy` reasons about.
  """
  @spec role(t() | String.t() | nil) :: role() | nil
  def role(%__MODULE__{role: role}), do: role(role)
  def role("lead"), do: :lead
  def role("member"), do: :member
  def role(_other), do: nil
end
