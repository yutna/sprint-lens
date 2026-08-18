defmodule SprintLens.TeamsTest do
  use SprintLens.DataCase

  alias SprintLens.Accounts.Scope
  alias SprintLens.Teams
  alias SprintLens.Teams.Membership
  alias SprintLens.Teams.Team
  alias SprintLens.Teams.Template

  describe "create_team/2" do
    @tag req: ["FR-101"]
    test "any user can create a team and becomes its lead" do
      user = insert(:user)

      assert {:ok, team} = Teams.create_team(user, %{name: "Alpha"})
      assert team.name == "Alpha"
      assert Teams.role(user, team) == :lead
    end

    @tag req: ["FR-101"]
    test "the description is optional" do
      assert {:ok, team} = Teams.create_team(insert(:user), %{name: "Alpha"})
      assert team.description == nil
    end

    @tag req: ["FR-101"]
    test "a team must have a name" do
      assert {:error, changeset} = Teams.create_team(insert(:user), %{name: "  "})
      refute changeset.valid?
    end

    @tag req: ["FR-101"]
    test "the lead membership and the team are written together" do
      user = insert(:user)
      {:ok, team} = Teams.create_team(user, %{name: "Alpha"})

      assert [%Membership{role: "lead"}] = Teams.list_members(team)
    end

    @tag req: ["NFR-201"]
    test "a signed-out caller cannot create a team" do
      assert Teams.create_team(nil, %{name: "Alpha"}) == {:error, :unauthorized}
    end

    @tag req: ["FR-005"]
    test "a deactivated user cannot create a team" do
      assert Teams.create_team(insert(:user, is_active: false), %{name: "Alpha"}) ==
               {:error, :unauthorized}
    end

    @tag req: ["FR-101"]
    test "accepts a scope, which is what the web layer carries" do
      assert {:ok, _team} = Teams.create_team(Scope.for_user(insert(:user)), %{name: "Alpha"})
    end
  end

  describe "list_teams/1" do
    @tag req: ["FR-103"]
    test "returns only the teams the user belongs to" do
      user = insert(:user)
      mine = team_with_lead(user)
      _theirs = team_with_lead(insert(:user))

      assert Enum.map(Teams.list_teams(user), & &1.id) == [mine.id]
    end

    @tag req: ["FR-103", "FR-605"]
    test "an Org Admin sees only their own teams here, not every team" do
      admin = insert(:org_admin)
      _someone_elses = team_with_lead(insert(:user))

      assert Teams.list_teams(admin) == []
    end

    @tag req: ["FR-106"]
    test "archived teams sort after active ones rather than disappearing" do
      user = insert(:user)
      archived = team_with_lead(user, %{is_archived: true})
      active = team_with_lead(user)

      assert Enum.map(Teams.list_teams(user), & &1.id) == [active.id, archived.id]
    end

    @tag req: ["FR-103"]
    test "a signed-out caller sees nothing" do
      assert Teams.list_teams(nil) == []
    end
  end

  describe "fetch_team/2" do
    @tag req: ["FR-103"]
    test "returns a team the caller belongs to" do
      user = insert(:user)
      team = team_with_lead(user)

      assert {:ok, found} = Teams.fetch_team(user, team.id)
      assert found.id == team.id
    end

    @tag req: ["FR-103"]
    test "hides a team the caller does not belong to behind not-found" do
      team = team_with_lead(insert(:user))

      assert Teams.fetch_team(insert(:user), team.id) == {:error, :not_found}
    end

    @tag req: ["FR-605"]
    test "hides another team from an Org Admin, who gets aggregates not boards" do
      team = team_with_lead(insert(:user))

      assert Teams.fetch_team(insert(:org_admin), team.id) == {:error, :not_found}
    end

    @tag req: ["FR-103"]
    test "returns not-found for a team that does not exist" do
      assert Teams.fetch_team(insert(:user), 999_999) == {:error, :not_found}
    end

    @tag req: ["NFR-201"]
    test "returns not-found for a signed-out caller" do
      team = team_with_lead(insert(:user))

      assert Teams.fetch_team(nil, team.id) == {:error, :not_found}
    end
  end

  describe "fetch_team_for_management/2" do
    @tag req: ["FR-801"]
    test "an Org Admin reaches any team, because section 3.1 lets them manage it" do
      team = team_with_lead(insert(:user))

      assert {:ok, found} = Teams.fetch_team_for_management(insert(:org_admin), team.id)
      assert found.id == team.id
    end

    @tag req: ["FR-102"]
    test "a member reaches their own team" do
      user = insert(:user)
      team = team_with_lead(user)

      assert {:ok, _team} = Teams.fetch_team_for_management(user, team.id)
    end

    @tag req: ["NFR-201"]
    test "an outsider reaches nothing" do
      team = team_with_lead(insert(:user))

      assert Teams.fetch_team_for_management(insert(:user), team.id) == {:error, :not_found}
    end
  end

  describe "role/2" do
    @tag req: ["FR-102"]
    test "reports the per-team role" do
      lead = insert(:user)
      member = insert(:user)
      team = team_with_lead(lead)
      join_team(member, team)

      assert Teams.role(lead, team) == :lead
      assert Teams.role(member, team) == :member
    end

    @tag req: ["FR-103"]
    test "is nil for someone who does not belong" do
      assert Teams.role(insert(:user), team_with_lead(insert(:user))) == nil
    end

    @tag req: ["FR-103"]
    test "is nil for a signed-out caller or a missing team" do
      assert Teams.role(nil, 1) == nil
      assert Teams.role(insert(:user), nil) == nil
    end

    @tag req: ["FR-102"]
    test "accepts a team id as well as a team" do
      user = insert(:user)
      team = team_with_lead(user)

      assert Teams.role(user, team.id) == :lead
      assert Teams.role(user, to_string(team.id)) == :lead
    end
  end

  describe "update_team_settings/3" do
    setup do
      lead = insert(:user)
      %{lead: lead, team: team_with_lead(lead)}
    end

    @tag req: ["FR-105"]
    test "a lead sets the default vote budget and the AI opt-in", %{lead: lead, team: team} do
      assert {:ok, updated} =
               Teams.update_team_settings(lead, team, %{default_vote_budget: 3, ai_opt_in: true})

      assert updated.default_vote_budget == 3
      assert updated.ai_opt_in
    end

    @tag req: ["FR-105"]
    test "a lead sets the default template", %{lead: lead, team: team} do
      template = insert(:template, team: team)

      assert {:ok, updated} =
               Teams.update_team_settings(lead, team, %{default_template_id: template.id})

      assert updated.default_template_id == template.id
    end

    @tag req: ["FR-401"]
    test "refuses a vote budget of zero", %{lead: lead, team: team} do
      assert {:error, changeset} =
               Teams.update_team_settings(lead, team, %{default_vote_budget: 0})

      assert %{default_vote_budget: [_message]} = errors_on(changeset)
    end

    @tag req: ["NFR-201"]
    test "a plain member cannot change settings", %{team: team} do
      member = insert(:user)
      join_team(member, team)

      assert Teams.update_team_settings(member, team, %{ai_opt_in: true}) ==
               {:error, :unauthorized}
    end

    @tag req: ["FR-801"]
    test "an Org Admin can, without belonging to the team", %{team: team} do
      assert {:ok, updated} =
               Teams.update_team_settings(insert(:org_admin), team, %{ai_opt_in: true})

      assert updated.ai_opt_in
    end

    @tag req: ["FR-106"]
    test "an archived team refuses every change", %{lead: lead} do
      archived = team_with_lead(lead, %{is_archived: true})

      assert Teams.update_team_settings(lead, archived, %{ai_opt_in: true}) ==
               {:error, :unauthorized}
    end
  end

  describe "archive_team/2 and restore_team/2" do
    @tag req: ["FR-106"]
    test "a lead archives their team, keeping its history" do
      lead = insert(:user)
      team = team_with_lead(lead)

      assert {:ok, archived} = Teams.archive_team(lead, team)
      assert archived.is_archived
      assert Teams.list_members(archived) != []
    end

    @tag req: ["FR-106"]
    test "an archived team can be restored" do
      lead = insert(:user)
      team = team_with_lead(lead, %{is_archived: true})

      assert {:ok, restored} = Teams.restore_team(lead, team)
      refute restored.is_archived
    end

    @tag req: ["NFR-201"]
    test "a member cannot archive or restore" do
      team = team_with_lead(insert(:user))
      member = insert(:user)
      join_team(member, team)

      assert Teams.archive_team(member, team) == {:error, :unauthorized}
      assert Teams.restore_team(member, team) == {:error, :unauthorized}
    end
  end

  describe "add_member/4" do
    setup do
      lead = insert(:user)
      %{lead: lead, team: team_with_lead(lead), newcomer: insert(:user)}
    end

    @tag req: ["FR-102"]
    test "a lead adds a member", ctx do
      assert {:ok, membership} = Teams.add_member(ctx.lead, ctx.team, ctx.newcomer.id)
      assert membership.role == "member"
      assert Teams.role(ctx.newcomer, ctx.team) == :member
    end

    @tag req: ["FR-102"]
    test "a lead adds another lead", ctx do
      assert {:ok, _membership} = Teams.add_member(ctx.lead, ctx.team, ctx.newcomer.id, "lead")
      assert Teams.role(ctx.newcomer, ctx.team) == :lead
    end

    @tag req: ["FR-102"]
    test "adding someone already in the team changes their role instead of failing", ctx do
      {:ok, _membership} = Teams.add_member(ctx.lead, ctx.team, ctx.newcomer.id)

      assert {:ok, _promoted} = Teams.add_member(ctx.lead, ctx.team, ctx.newcomer.id, "lead")
      assert Teams.role(ctx.newcomer, ctx.team) == :lead
      assert length(Teams.list_members(ctx.team)) == 2
    end

    @tag req: ["FR-102"]
    test "refuses a role that is not lead or member", ctx do
      assert {:error, changeset} =
               Teams.add_member(ctx.lead, ctx.team, ctx.newcomer.id, "overlord")

      assert %{role: ["is invalid"]} = errors_on(changeset)
    end

    @tag req: ["FR-102"]
    test "refuses a user that does not exist", ctx do
      assert {:error, changeset} = Teams.add_member(ctx.lead, ctx.team, 999_999)
      refute changeset.valid?
    end

    @tag req: ["NFR-201"]
    test "a member cannot add anyone", ctx do
      member = insert(:user)
      join_team(member, ctx.team)

      assert Teams.add_member(member, ctx.team, ctx.newcomer.id) == {:error, :unauthorized}
    end

    @tag req: ["FR-801"]
    test "an Org Admin can, without belonging to the team", ctx do
      assert {:ok, _membership} =
               Teams.add_member(insert(:org_admin), ctx.team, ctx.newcomer.id)
    end
  end

  describe "remove_member/3" do
    setup do
      lead = insert(:user)
      team = team_with_lead(lead)
      member = insert(:user)
      join_team(member, team)

      %{lead: lead, team: team, member: member}
    end

    @tag req: ["FR-102"]
    test "a lead removes a member", ctx do
      assert Teams.remove_member(ctx.lead, ctx.team, ctx.member.id) == :ok
      assert Teams.role(ctx.member, ctx.team) == nil
    end

    @tag req: ["FR-102"]
    test "refuses to remove the last lead, which would strand the team", ctx do
      assert Teams.remove_member(ctx.lead, ctx.team, ctx.lead.id) == {:error, :last_lead}
      assert Teams.role(ctx.lead, ctx.team) == :lead
    end

    @tag req: ["FR-102"]
    test "removes a lead once there is another one", ctx do
      second = insert(:user)
      join_team(second, ctx.team, "lead")

      assert Teams.remove_member(ctx.lead, ctx.team, ctx.lead.id) == :ok
    end

    @tag req: ["FR-102"]
    test "reports not-found for someone who is not in the team", ctx do
      assert Teams.remove_member(ctx.lead, ctx.team, insert(:user).id) == {:error, :not_found}
    end

    @tag req: ["NFR-201"]
    test "a member cannot remove anyone", ctx do
      assert Teams.remove_member(ctx.member, ctx.team, ctx.lead.id) == {:error, :unauthorized}
    end
  end

  describe "leave_team/2" do
    @tag req: ["FR-104"]
    test "a member can leave without needing anyone's permission" do
      team = team_with_lead(insert(:user))
      member = insert(:user)
      join_team(member, team)

      assert Teams.leave_team(member, team) == :ok
      assert Teams.role(member, team) == nil
    end

    @tag req: ["FR-104"]
    test "the last lead cannot leave, for the same reason they cannot be removed" do
      lead = insert(:user)
      team = team_with_lead(lead)

      assert Teams.leave_team(lead, team) == {:error, :last_lead}
    end

    @tag req: ["FR-104"]
    test "leaving a team you are not in is a no-op, not a crash" do
      assert Teams.leave_team(insert(:user), team_with_lead(insert(:user))) ==
               {:error, :not_found}
    end

    @tag req: ["NFR-201"]
    test "a signed-out caller cannot leave anything" do
      assert Teams.leave_team(nil, team_with_lead(insert(:user))) == {:error, :not_found}
    end
  end

  describe "list_members/1" do
    @tag req: ["FR-102"]
    test "lists leads before members, each with their user preloaded" do
      lead = insert(:user, display_name: "Zara")
      team = team_with_lead(lead)
      join_team(insert(:user, display_name: "Anan"), team)

      assert [%{role: "lead", user: %{display_name: "Zara"}}, %{role: "member"}] =
               Teams.list_members(team)
    end
  end

  describe "templates" do
    setup do
      lead = insert(:user)
      %{lead: lead, team: team_with_lead(lead)}
    end

    @tag req: ["FR-201"]
    test "the five built-ins are available to every team", %{team: team} do
      names = Teams.list_builtin_templates() |> Enum.map(& &1.name) |> Enum.sort()

      assert names == ["4Ls", "KPT", "Mad-Sad-Glad", "Sailboat", "Start-Stop-Continue"]
      assert Enum.all?(names, &(&1 in Enum.map(Teams.list_templates(team), fn t -> t.name end)))
    end

    @tag req: ["FR-201"]
    test "each built-in has between two and six named columns" do
      {min, max} = Template.column_bounds()

      for template <- Teams.list_builtin_templates() do
        names = Template.column_names(template)

        assert length(names) >= min and length(names) <= max
        assert Enum.all?(names, &(is_binary(&1) and &1 != ""))
      end
    end

    @tag req: ["FR-202"]
    test "a member saves a custom template for the team to reuse", %{lead: lead, team: team} do
      assert {:ok, template} =
               Teams.create_template(lead, team, %{
                 name: "Our own",
                 columns: [%{"name" => "Good"}, %{"name" => "Bad"}]
               })

      assert template.team_id == team.id
      refute template.is_builtin
      assert Template.column_names(template) == ["Good", "Bad"]
    end

    @tag req: ["FR-202"]
    test "a plain member may create one too, since FR-202 says users not leads", %{team: team} do
      member = insert(:user)
      join_team(member, team)

      assert {:ok, _template} =
               Teams.create_template(member, team, %{
                 name: "Mine",
                 columns: [%{"name" => "A"}, %{"name" => "B"}]
               })
    end

    @tag req: ["FR-202"]
    test "refuses fewer than two columns", %{lead: lead, team: team} do
      assert {:error, changeset} =
               Teams.create_template(lead, team, %{name: "One", columns: [%{"name" => "Only"}]})

      assert %{columns: [_message]} = errors_on(changeset)
    end

    @tag req: ["FR-202"]
    test "refuses more than six columns", %{lead: lead, team: team} do
      columns = Enum.map(1..7, &%{"name" => "Column #{&1}"})

      assert {:error, changeset} =
               Teams.create_template(lead, team, %{name: "Too many", columns: columns})

      assert %{columns: [_message]} = errors_on(changeset)
    end

    @tag req: ["FR-202"]
    test "refuses a column with no name", %{lead: lead, team: team} do
      assert {:error, changeset} =
               Teams.create_template(lead, team, %{
                 name: "Blank",
                 columns: [%{"name" => "Good"}, %{"name" => "  "}]
               })

      assert %{columns: [_message]} = errors_on(changeset)
    end

    @tag req: ["FR-202"]
    test "keeps the optional hint alongside each column", %{lead: lead, team: team} do
      {:ok, template} =
        Teams.create_template(lead, team, %{
          name: "Hinted",
          columns: [%{"name" => "Good", "hint" => "What worked?"}, %{"name" => "Bad"}]
        })

      assert [%{"hint" => "What worked?"}, %{"hint" => nil}] = template.columns
    end

    @tag req: ["FR-202"]
    test "updates and deletes a team's own template", %{lead: lead, team: team} do
      {:ok, template} =
        Teams.create_template(lead, team, %{
          name: "Draft",
          columns: [%{"name" => "A"}, %{"name" => "B"}]
        })

      assert {:ok, renamed} = Teams.update_template(lead, team, template, %{name: "Final"})
      assert renamed.name == "Final"

      assert Teams.delete_template(lead, team, renamed) == :ok
      assert Teams.fetch_template(team, renamed.id) == {:error, :not_found}
    end

    @tag req: ["FR-201"]
    test "a built-in cannot be edited or deleted", %{lead: lead, team: team} do
      builtin = hd(Teams.list_builtin_templates())

      assert Teams.update_template(lead, team, builtin, %{name: "Hijacked"}) == {:error, :builtin}
      assert Teams.delete_template(lead, team, builtin) == {:error, :builtin}
    end

    @tag req: ["FR-201"]
    test "fetch_template reaches the built-ins and the team's own", %{lead: lead, team: team} do
      builtin = hd(Teams.list_builtin_templates())

      {:ok, own} =
        Teams.create_template(lead, team, %{
          name: "Own",
          columns: [%{"name" => "A"}, %{"name" => "B"}]
        })

      assert {:ok, _builtin} = Teams.fetch_template(team, builtin.id)
      assert {:ok, _own} = Teams.fetch_template(team, own.id)
    end

    @tag req: ["FR-103"]
    test "another team's template is not reachable", %{lead: lead, team: team} do
      {:ok, theirs} =
        Teams.create_template(lead, team, %{
          name: "Theirs",
          columns: [%{"name" => "A"}, %{"name" => "B"}]
        })

      other_team = team_with_lead(insert(:user))

      assert Teams.fetch_template(other_team, theirs.id) == {:error, :not_found}
      refute Enum.any?(Teams.list_templates(other_team), &(&1.id == theirs.id))
    end

    @tag req: ["NFR-201"]
    test "an outsider cannot create a template for the team", %{team: team} do
      assert Teams.create_template(insert(:user), team, %{name: "X", columns: []}) ==
               {:error, :unauthorized}
    end

    @tag req: ["FR-106"]
    test "an archived team accepts no new templates", %{lead: lead} do
      archived = team_with_lead(lead, %{is_archived: true})

      assert Teams.create_template(lead, archived, %{name: "X", columns: []}) ==
               {:error, :unauthorized}
    end
  end

  describe "schema bounds exposed to forms" do
    @tag req: ["FR-102"]
    test "the per-team roles are lead and member" do
      assert Enum.sort(Membership.roles()) == ["lead", "member"]
    end

    @tag req: ["FR-401"]
    test "the vote budget has a usable range" do
      {min, max} = Team.vote_budget_bounds()

      assert min == 1
      assert max > min
    end

    @tag req: ["FR-202"]
    test "the column count is two to six" do
      assert Template.column_bounds() == {2, 6}
    end
  end

  describe "template columns from Elixir callers" do
    @tag req: ["FR-202"]
    test "atom-keyed columns are accepted and normalised to string keys" do
      lead = insert(:user)
      team = team_with_lead(lead)

      assert {:ok, template} =
               Teams.create_template(lead, team, %{
                 name: "Atoms",
                 columns: [%{name: "Good", hint: "What worked?"}, %{name: "Bad"}]
               })

      assert template.columns == [
               %{"name" => "Good", "hint" => "What worked?"},
               %{"name" => "Bad", "hint" => nil}
             ]
    end

    @tag req: ["FR-202"]
    test "a blank hint is stored as nothing rather than as an empty string" do
      lead = insert(:user)
      team = team_with_lead(lead)

      {:ok, template} =
        Teams.create_template(lead, team, %{
          name: "Blank hints",
          columns: [%{"name" => "A", "hint" => "   "}, %{"name" => "B"}]
        })

      assert Enum.all?(template.columns, &(&1["hint"] == nil))
    end
  end

  describe "changesets for forms" do
    @tag req: ["FR-101"]
    test "change_team/2 builds a create changeset" do
      assert %Ecto.Changeset{} = Teams.change_team()
    end

    @tag req: ["FR-105"]
    test "change_team_settings/2 builds a settings changeset" do
      assert %Ecto.Changeset{} = Teams.change_team_settings(build(:team))
    end

    @tag req: ["FR-202"]
    test "change_template/2 builds a template changeset" do
      assert %Ecto.Changeset{} = Teams.change_template()
    end
  end
end
