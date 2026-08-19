defmodule SprintLens.AI.SuggestionTest do
  @moduledoc """
  The suggestion row (section 6.3 AI_SUGGESTION, §5.2).
  """

  use SprintLens.UnitCase, async: true

  alias SprintLens.AI.Suggestion

  describe "the closed sets" do
    @tag req: ["AI-005"]
    test "six types, one per feature of section 5.4", _ctx do
      assert Suggestion.types() == [
               :session_summary,
               :clustering,
               :action_draft,
               :recurring_themes,
               :icebreakers,
               :translation
             ]
    end

    @tag req: ["AI-005"]
    test "and six statuses, as section 6.3 lists them", _ctx do
      assert Suggestion.statuses() == [
               :queued,
               :running,
               :ready,
               :failed,
               :accepted,
               :rejected
             ]
    end
  end

  describe "reading a type" do
    @tag req: ["AI-005"]
    test "from a name or an atom", _ctx do
      assert Suggestion.parse_type("clustering") == {:ok, :clustering}
      assert Suggestion.parse_type(:clustering) == {:ok, :clustering}
      assert Suggestion.type(%Suggestion{type: "translation"}) == :translation
    end

    @tag req: ["AI-005"]
    test "and anything else is not one", _ctx do
      assert Suggestion.parse_type("horoscope") == :error
      assert Suggestion.parse_type(nil) == :error
      assert Suggestion.type(%Suggestion{type: "horoscope"}) == nil
    end
  end

  describe "reading a status" do
    @tag req: ["AI-005"]
    test "from a row, a name or an atom", _ctx do
      assert Suggestion.status(%Suggestion{status: "ready"}) == :ready
      assert Suggestion.status("failed") == :failed
      assert Suggestion.status(:accepted) == :accepted
    end

    @tag req: ["AI-005"]
    test "and anything else is not one", _ctx do
      assert Suggestion.status("exploded") == nil
      assert Suggestion.status(nil) == nil
    end

    @tag req: ["AI-002"]
    test "three of them still have a question for a human", _ctx do
      for status <- ~w(queued running ready) do
        assert Suggestion.open?(%Suggestion{status: status})
      end

      for status <- ~w(failed accepted rejected) do
        refute Suggestion.open?(%Suggestion{status: status})
      end
    end
  end

  describe "the envelope's fields (§5.2)" do
    @tag req: ["AI-015"]
    test "input_scope reads back as the list the envelope shows", _ctx do
      assert Suggestion.input_scope(%Suggestion{input_scope: "cards,notes"}) == ~w(cards notes)
      assert Suggestion.input_scope(%Suggestion{input_scope: ""}) == []
      assert Suggestion.input_scope(%Suggestion{input_scope: nil}) == []
    end

    @tag req: ["AI-005"]
    test "a request needs a team and a type", _ctx do
      changeset = Suggestion.request_changeset(%Suggestion{}, %{team_id: 1, type: "clustering"})

      assert changeset.valid?
      assert get_change(changeset, :input_scope) == ""

      refute Suggestion.request_changeset(%Suggestion{}, %{type: "clustering"}).valid?
      refute Suggestion.request_changeset(%Suggestion{}, %{team_id: 1, type: "nope"}).valid?
    end

    @tag req: ["AI-006"]
    test "a result needs a status, and a long error is trimmed", _ctx do
      long = String.duplicate("x", 900)

      changeset =
        Suggestion.result_changeset(%Suggestion{}, %{status: "failed", error: long})

      assert String.length(get_change(changeset, :error)) == 500
      refute Suggestion.result_changeset(%Suggestion{}, %{status: "exploded"}).valid?
    end

    @tag req: ["AI-002"]
    test "a decision keeps the human's version when there is one", _ctx do
      edited = Suggestion.decision_changeset(%Suggestion{}, :accepted, "mine")
      plain = Suggestion.decision_changeset(%Suggestion{}, :rejected)

      assert get_change(edited, :accepted_output) == "mine"
      assert get_change(plain, :accepted_output) == nil
      assert get_change(plain, :status) == "rejected"
    end
  end
end
