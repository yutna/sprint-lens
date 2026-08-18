defmodule SprintLens.Retro.VoteTest do
  @moduledoc """
  The vote row itself (section 6.3, VOTE).

  The rule worth a test here is the one section 6.3 states and no database
  constraint can: exactly one of card or card_group is set.
  """

  use SprintLens.UnitCase, async: true

  alias SprintLens.Retro.Vote

  defp changeset(attrs) do
    Vote.changeset(%Vote{}, Map.merge(%{session_id: 1, voter_id: 2}, attrs))
  end

  @tag req: ["FR-401"]
  test "a vote names a session, a voter and one target" do
    assert changeset(%{card_id: 3}).valid?
    assert changeset(%{card_group_id: 3}).valid?
  end

  @tag req: ["FR-401"]
  test "a vote for nothing is refused" do
    assert %{card_id: [_message]} = errors_on(changeset(%{}))
  end

  @tag req: ["FR-401"]
  test "a vote for both a card and a group is refused" do
    # It would be counted twice — once under each total.
    assert %{card_id: [_message]} = errors_on(changeset(%{card_id: 3, card_group_id: 4}))
  end

  @tag req: ["FR-403"]
  test "a vote without a voter is refused" do
    changeset = Vote.changeset(%Vote{}, %{session_id: 1, card_id: 3})

    assert %{voter_id: [_message]} = errors_on(changeset)
  end

  @tag req: ["FR-301"]
  test "the client's request id rides along for idempotency (§7.5)" do
    changeset = changeset(%{card_id: 3, client_request_id: "abc"})

    assert get_change(changeset, :client_request_id) == "abc"
  end
end
