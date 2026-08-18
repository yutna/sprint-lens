defmodule SprintLens.Factory do
  @moduledoc """
  Test data builders.

  Factories produce the *minimum valid* record. Anything a test cares about it
  states explicitly in the overrides, so a test reads as a description of the
  case it covers rather than of the fixture. Grows one factory per schema as
  the milestones land.
  """

  use ExMachina.Ecto, repo: SprintLens.Repo

  alias SprintLens.Accounts.User
  alias SprintLens.Teams.Membership
  alias SprintLens.Teams.Team
  alias SprintLens.Teams.Template

  @doc """
  A value unique to this call, for fields with a uniqueness constraint.
  """
  def unique(prefix), do: "#{prefix}-#{System.unique_integer([:positive])}"

  def user_factory do
    %User{
      email: unique("user") <> "@example.com",
      display_name: "User #{System.unique_integer([:positive])}",
      language: "th",
      theme: "system",
      is_org_admin: false,
      is_active: true,
      confirmed_at: DateTime.utc_now(:second)
    }
  end

  def org_admin_factory do
    struct!(user_factory(), is_org_admin: true)
  end

  def team_factory do
    %Team{
      name: unique("Team"),
      default_vote_budget: 5,
      ai_opt_in: false,
      is_archived: false
    }
  end

  def membership_factory do
    %Membership{
      user: build(:user),
      team: build(:team),
      role: "member"
    }
  end

  def template_factory do
    %Template{
      name: unique("Template"),
      is_builtin: false,
      team: build(:team),
      columns: [
        %{"name" => "Went well", "hint" => nil},
        %{"name" => "To improve", "hint" => nil}
      ]
    }
  end

  @doc """
  A team with `user` as its Team Lead — the shape `FR-101` creates.
  """
  def team_with_lead(user, attrs \\ %{}) do
    team = insert(:team, attrs)
    insert(:membership, user: user, team: team, role: "lead")
    team
  end

  @doc """
  Adds `user` to `team` in the given role.
  """
  def join_team(user, team, role \\ "member") do
    insert(:membership, user: user, team: team, role: role)
    team
  end
end
