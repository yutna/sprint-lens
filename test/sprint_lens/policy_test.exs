defmodule SprintLens.PolicyTest do
  @moduledoc """
  Exhaustive tests against the permission tables in spec sections 3.1 and 3.2.

  The tables are transcribed here as data and every cell is asserted, so a
  change to `SprintLens.Policy` that quietly widens a permission fails rather
  than passing unnoticed (NFR-201).
  """

  use SprintLens.UnitCase, async: true

  alias SprintLens.Accounts.Scope
  alias SprintLens.Accounts.User
  alias SprintLens.Policy

  # Section 3.1, transcribed. Each row is {action, org_admin?, lead?, member?}
  # where the flags are what the table says that column may do.
  @section_3_1 [
    {:create_team, true, true, true},
    {:manage_members, true, true, false},
    {:edit_team_settings, true, true, false},
    {:create_session, true, true, true},
    {:view_team_insights, true, true, true},
    {:view_org_insights, true, false, false},
    {:manage_webhooks, true, true, false},
    {:toggle_ai_opt_in, true, true, false},
    {:manage_users, true, false, false},
    {:purge_data, true, false, false}
  ]

  defp org_admin, do: %User{id: 1, is_org_admin: true, is_active: true}
  defp member, do: %User{id: 2, is_org_admin: false, is_active: true}

  describe "the section 3.1 table" do
    for {action, admin?, lead?, member?} <- @section_3_1 do
      @tag req: ["NFR-201"]
      test "#{action}: org admin #{admin?}, lead #{lead?}, member #{member?}" do
        action = unquote(action)

        # An Org Admin may manage any team, whether or not they belong to it.
        assert Policy.can?(org_admin(), action, nil) == unquote(admin?)
        assert Policy.can?(member(), action, :lead) == unquote(lead?)
        assert Policy.can?(member(), action, :member) == unquote(member?)
      end
    end

    @tag req: ["NFR-201"]
    test "the transcribed table covers every action the module knows about" do
      transcribed = @section_3_1 |> Enum.map(&elem(&1, 0)) |> Enum.sort()

      assert Enum.sort(Policy.team_actions()) == transcribed
    end

    @tag req: ["NFR-201"]
    test "a non-member with no org-admin flag may only create a team" do
      allowed = Enum.filter(Policy.team_actions(), &Policy.can?(member(), &1, nil))

      assert allowed == [:create_team]
    end
  end

  describe "can?/3" do
    @tag req: ["NFR-201"]
    test "a signed-out caller may do nothing" do
      for action <- Policy.team_actions() do
        refute Policy.can?(nil, action, :lead)
      end
    end

    @tag req: ["FR-005"]
    test "a deactivated user may do nothing, whatever their roles say" do
      deactivated = %User{id: 3, is_org_admin: true, is_active: false}

      for action <- Policy.team_actions() do
        refute Policy.can?(deactivated, action, :lead)
      end
    end

    @tag req: ["NFR-201"]
    test "an unknown action is refused rather than allowed by default" do
      refute Policy.can?(org_admin(), :launch_the_missiles, :lead)
    end

    @tag req: ["NFR-201"]
    test "accepts a scope, which is what the web layer carries" do
      assert Policy.can?(Scope.for_user(member()), :create_team)
      refute Policy.can?(Scope.for_user(member()), :manage_users)
    end
  end

  describe "see_team?/2" do
    @tag req: ["FR-103"]
    test "members and leads see their team" do
      assert Policy.see_team?(member(), :lead)
      assert Policy.see_team?(member(), :member)
    end

    @tag req: ["FR-103", "FR-605"]
    test "an Org Admin does not see a team they do not belong to" do
      # Section 3.3 gives Org Admin org-wide aggregates, never another team's
      # board. Managing a team and reading its cards are different things.
      refute Policy.see_team?(org_admin(), nil)
      assert Policy.can?(org_admin(), :manage_members, nil)
    end

    @tag req: ["FR-103"]
    test "a non-member sees nothing" do
      refute Policy.see_team?(member(), nil)
      refute Policy.see_team?(nil, :lead)
    end

    @tag req: ["FR-005"]
    test "a deactivated member sees nothing" do
      refute Policy.see_team?(%User{id: 4, is_active: false}, :lead)
    end

    @tag req: ["FR-103"]
    test "accepts a scope" do
      assert Policy.see_team?(Scope.for_user(member()), :member)
    end
  end

  describe "manage?/4" do
    @tag req: ["FR-106"]
    test "an archived team is read-only, even for its lead" do
      refute Policy.manage?(member(), :edit_team_settings, :lead, true)
      assert Policy.manage?(member(), :edit_team_settings, :lead, false)
    end

    @tag req: ["FR-106"]
    test "an archived team is read-only for an Org Admin too" do
      refute Policy.manage?(org_admin(), :manage_members, nil, true)
    end
  end

  describe "the section 3.2 table" do
    @tag req: ["NFR-201"]
    test "the facilitator has every listed control" do
      for control <- Policy.session_controls() do
        assert Policy.session_can?(:facilitator, control), "facilitator should have #{control}"
      end
    end

    @tag req: ["NFR-201"]
    test "a participant has none of them" do
      for control <- Policy.session_controls() do
        refute Policy.session_can?(:participant, control),
               "participant should not have #{control}"
      end
    end

    @tag req: ["FR-206", "FR-208", "FR-404", "FR-406", "FR-407", "FR-302", "FR-207", "FR-215"]
    test "lists exactly the controls section 3.2 names" do
      assert Enum.sort(Policy.session_controls()) ==
               Enum.sort([
                 :change_phase,
                 :control_timer,
                 :reveal,
                 :set_focus,
                 :edit_notes,
                 :delete_any_card,
                 :transfer_facilitator,
                 :close_session
               ])
    end

    @tag req: ["NFR-201"]
    test "an unknown control is refused" do
      refute Policy.session_can?(:facilitator, :rewrite_history)
    end
  end

  describe "edit_card?/2" do
    @tag req: ["FR-301"]
    test "only the author may edit their own words" do
      assert Policy.edit_card?(member(), member().id)
      refute Policy.edit_card?(member(), 999)
    end

    @tag req: ["FR-210", "FR-302"]
    test "nobody may edit a card with no author, and a signed-out caller may edit nothing" do
      # The shape an anonymous session leaves behind, and the shape a forged
      # request arrives in.
      refute Policy.edit_card?(member(), nil)
      refute Policy.edit_card?(nil, 1)
    end
  end

  describe "delete_card?/3" do
    @tag req: ["FR-302"]
    test "the facilitator may delete any card" do
      assert Policy.delete_card?(:facilitator, member(), 999)
    end

    @tag req: ["FR-301"]
    test "a participant may delete their own card" do
      assert Policy.delete_card?(:participant, member(), member().id)
    end

    @tag req: ["FR-301"]
    test "a participant may not delete someone else's card" do
      refute Policy.delete_card?(:participant, member(), 999)
    end

    @tag req: ["FR-210"]
    test "a participant may not delete a card with no author, as in an anonymous session" do
      refute Policy.delete_card?(:participant, member(), nil)
      refute Policy.delete_card?(:participant, nil, nil)
    end
  end
end
