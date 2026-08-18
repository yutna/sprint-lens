defmodule SprintLens.Retro.DiscussionNoteTest do
  @moduledoc """
  The discussion note row (FR-407).
  """

  use SprintLens.UnitCase, async: true

  alias SprintLens.Retro.DiscussionNote

  defp changeset(attrs) do
    DiscussionNote.changeset(
      %DiscussionNote{},
      Map.merge(%{session_id: 1, body: "Ship it"}, attrs)
    )
  end

  @tag req: ["FR-407"]
  test "a note belongs to a session and exactly one topic" do
    assert changeset(%{card_id: 3}).valid?
    assert changeset(%{card_group_id: 3}).valid?
  end

  @tag req: ["FR-407"]
  test "a note about nothing, or about two things, is refused" do
    assert %{card_id: [_message]} = errors_on(changeset(%{}))
    assert %{card_id: [_message]} = errors_on(changeset(%{card_id: 3, card_group_id: 4}))
  end

  @tag req: ["FR-407"]
  test "surrounding whitespace is not a note" do
    assert %{body: [_message]} = errors_on(changeset(%{card_id: 3, body: "   \n "}))
  end

  @tag req: ["FR-407"]
  test "the body is trimmed rather than stored as typed" do
    changeset = changeset(%{card_id: 3, body: "  Ship weekly  "})

    assert get_change(changeset, :body) == "Ship weekly"
  end

  @tag req: ["FR-407"]
  test "a runaway paste is refused" do
    long = String.duplicate("x", DiscussionNote.max_body() + 1)

    assert %{body: [_message]} = errors_on(changeset(%{card_id: 3, body: long}))
  end
end
