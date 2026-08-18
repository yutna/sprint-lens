defmodule SprintLens.Retro.MoodEntryTest do
  use SprintLens.UnitCase, async: true

  alias SprintLens.Retro.MoodEntry

  describe "kinds/0 and score_bounds/0" do
    @tag req: ["FR-211", "FR-214"]
    test "there are two kinds of answer, both scored one to five" do
      assert MoodEntry.kinds() == [:checkin_mood, :roti]
      assert MoodEntry.score_bounds() == {1, 5}
    end
  end

  describe "kind/1" do
    @tag req: ["FR-211"]
    test "reads the stored string, and passes an atom through" do
      assert MoodEntry.kind(%MoodEntry{kind: "roti"}) == :roti
      assert MoodEntry.kind("checkin_mood") == :checkin_mood
      assert MoodEntry.kind(:roti) == :roti
    end

    @tag req: ["FR-211"]
    test "is nil for anything unrecognised" do
      assert MoodEntry.kind("nonsense") == nil
      assert MoodEntry.kind(nil) == nil
    end
  end

  describe "changeset/2" do
    @tag req: ["FR-211"]
    test "requires a session, a kind and a score" do
      changeset = MoodEntry.changeset(%MoodEntry{}, %{})

      refute changeset.valid?
      errors = errors_on(changeset)
      assert errors.session_id
      assert errors.kind
      assert errors.score
    end

    @tag req: ["FR-211"]
    test "refuses a kind that is not one of the two" do
      changeset =
        MoodEntry.changeset(%MoodEntry{}, %{session_id: 1, kind: "vibes", score: 3})

      assert %{kind: ["is invalid"]} = errors_on(changeset)
    end

    @tag req: ["FR-211"]
    test "a note can be taken back, leaving nothing rather than an empty string" do
      entry = %MoodEntry{session_id: 1, kind: "checkin_mood", score: 3, word: "tired"}

      changeset = MoodEntry.changeset(entry, %{word: nil})

      assert Ecto.Changeset.get_field(changeset, :word) == nil
    end

    @tag req: ["FR-211"]
    test "keeps only the first word of the note" do
      changeset =
        MoodEntry.changeset(%MoodEntry{}, %{
          session_id: 1,
          kind: "checkin_mood",
          score: 3,
          word: "  cautiously optimistic  "
        })

      assert Ecto.Changeset.get_change(changeset, :word) == "cautiously"
    end
  end
end
