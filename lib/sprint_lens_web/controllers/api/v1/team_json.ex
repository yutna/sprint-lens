defmodule SprintLensWeb.Api.V1.TeamJSON do
  @moduledoc """
  Serialises teams, memberships and templates for the API (§7.2).
  """

  alias SprintLens.Teams.Membership
  alias SprintLens.Teams.Team
  alias SprintLens.Teams.Template
  alias SprintLensWeb.Api.V1.UserJSON

  @doc """
  A team as it appears in a list: enough to choose one, without its members.
  """
  @spec team(Team.t()) :: map()
  def team(%Team{} = team) do
    %{
      id: team.id,
      name: team.name,
      description: team.description,
      is_archived: team.is_archived,
      default_template_id: team.default_template_id,
      default_vote_budget: team.default_vote_budget,
      ai_opt_in: team.ai_opt_in,
      created_at: team.inserted_at
    }
  end

  @doc """
  A team with its membership, for the detail endpoint.
  """
  @spec team_detail(Team.t(), [Membership.t()]) :: map()
  def team_detail(%Team{} = team, members) do
    team |> team() |> Map.put(:members, Enum.map(members, &membership/1))
  end

  @doc """
  One membership, carrying the teammate's public identity only.
  """
  @spec membership(Membership.t()) :: map()
  def membership(%Membership{} = membership) do
    %{
      user: UserJSON.summary(membership.user),
      role: membership.role,
      joined_at: membership.inserted_at
    }
  end

  @doc """
  One template and its column layout.
  """
  @spec template(Template.t()) :: map()
  def template(%Template{} = template) do
    %{
      id: template.id,
      name: template.name,
      is_builtin: template.is_builtin,
      team_id: template.team_id,
      columns: Enum.map(template.columns, &%{name: &1["name"], hint: &1["hint"]})
    }
  end
end
