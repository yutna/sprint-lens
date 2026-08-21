defmodule SprintLens.Retro.ColumnTest do
  use SprintLens.DataCase

  alias SprintLens.Retro.Column

  describe "changeset/2" do
    @tag req: ["FR-201"]
    test "requires a name and a position" do
      changeset = Column.changeset(%Column{}, %{})

      refute changeset.valid?
      assert %{name: [_name], position: [_position]} = errors_on(changeset)
    end

    @tag req: ["FR-201"]
    test "a dangling session reference is stopped by the database, loudly" do
      # Not turned into a field error: columns are only created inside
      # `create_session/3`, in the same transaction as their session, so this
      # is a bug rather than something a person typed.
      changeset = Column.changeset(%Column{}, %{session_id: 999_999, name: "A", position: 0})

      assert_raise Ecto.ConstraintError, fn -> Repo.insert(changeset) end
    end

    @tag req: ["FR-305"]
    test "two columns cannot share a position in one session" do
      facilitator = insert(:user)
      team = team_with_lead(facilitator)
      session = insert(:session, team: team, facilitator: facilitator)

      insert(:column, session: session, position: 0)

      assert {:error, changeset} =
               %Column{}
               |> Column.changeset(%{session_id: session.id, name: "Clash", position: 0})
               |> Repo.insert()

      refute changeset.valid?
    end
  end

  describe "attrs_from_template/2" do
    @tag req: ["FR-201"]
    test "numbers the columns in the order the template lists them" do
      attrs =
        Column.attrs_from_template(
          [
            %{"name" => "Start", "hint" => "Begin?"},
            %{"name" => "Stop", "hint" => nil}
          ],
          true
        )

      assert attrs == [
               %{name: "Start", hint: "Begin?", position: 0, from_builtin: true},
               %{name: "Stop", hint: nil, position: 1, from_builtin: true}
             ]
    end

    @tag req: ["FR-909"]
    test "a team's own layout is marked as theirs, so nothing translates it" do
      attrs = Column.attrs_from_template([%{"name" => "งานค้าง", "hint" => nil}], false)

      assert [%{name: "งานค้าง", from_builtin: false}] = attrs
    end
  end
end
