defmodule SprintLens.Actions.ActionItemTest do
  @moduledoc """
  The action item row itself (section 6.3, ACTION_ITEM).
  """

  use SprintLens.UnitCase, async: true

  alias SprintLens.Actions.ActionItem

  describe "status/1" do
    @tag req: ["FR-502"]
    test "reads the four statuses off a row or a string" do
      assert ActionItem.status(%ActionItem{status: "in_progress"}) == :in_progress
      assert ActionItem.status("done") == :done
    end

    @tag req: ["FR-502"]
    test "an atom is already an answer" do
      assert ActionItem.status(:dropped) == :dropped
    end

    @tag req: ["FR-502"]
    test "and anything else is not a status" do
      assert ActionItem.status("maybe") == nil
      assert ActionItem.status(nil) == nil
    end

    @tag req: ["FR-506"]
    test "open and in progress still ask something of the team" do
      assert ActionItem.live?(%ActionItem{status: "open"})
      assert ActionItem.live?(%ActionItem{status: "in_progress"})
      refute ActionItem.live?(%ActionItem{status: "done"})
      refute ActionItem.live?(%ActionItem{status: "dropped"})
    end
  end

  defp changeset(attrs) do
    ActionItem.create_changeset(%ActionItem{}, Map.merge(%{team_id: 1, title: "Fix it"}, attrs))
  end

  describe "the topic link" do
    @tag req: ["FR-501"]
    test "an action may point at nothing" do
      assert changeset(%{}).valid?
    end

    @tag req: ["FR-501"]
    test "or at one card, or at one cluster" do
      assert changeset(%{card_id: 3}).valid?
      assert changeset(%{card_group_id: 3}).valid?
    end

    @tag req: ["FR-501"]
    test "but not at both at once" do
      assert %{card_id: [_message]} = errors_on(changeset(%{card_id: 3, card_group_id: 4}))
    end
  end

  @tag req: ["FR-502"]
  test "a title longer than the limit is refused" do
    long = String.duplicate("x", ActionItem.max_title() + 1)

    assert %{title: [_message]} = errors_on(changeset(%{title: long}))
  end
end
