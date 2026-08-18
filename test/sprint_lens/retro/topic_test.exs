defmodule SprintLens.Retro.TopicTest do
  @moduledoc """
  The topic value: naming one, reading one back, and ordering a list of them
  (FR-405, FR-406, FR-407).

  All of this is arithmetic on structs, so it needs no database and runs
  concurrently with everything else.
  """

  use SprintLens.UnitCase, async: true

  alias SprintLens.Retro.Card
  alias SprintLens.Retro.CardGroup
  alias SprintLens.Retro.Topic

  defp at(seconds), do: DateTime.from_unix!(1_700_000_000 + seconds)

  defp group(id, label, inserted_at) do
    Topic.from_group(%CardGroup{id: id, label: label, inserted_at: inserted_at, cards: []})
  end

  defp card(id, text, inserted_at) do
    Topic.from_card(%Card{id: id, text: text, inserted_at: inserted_at})
  end

  describe "building" do
    @tag req: ["FR-405"]
    test "a cluster becomes a topic named by its label" do
      topic = group(7, "Deploys", at(0))

      assert topic.kind == :group
      assert topic.id == 7
      assert topic.key == "group:7"
      assert topic.title == "Deploys"
      assert topic.my_votes == 0
      assert topic.votes == nil
    end

    @tag req: ["FR-405"]
    test "a cluster carries the cards it holds" do
      cards = [%Card{id: 1, text: "one"}, %Card{id: 2, text: "two"}]
      topic = Topic.from_group(%CardGroup{id: 7, label: "Deploys", cards: cards})

      assert Enum.map(topic.cards, & &1.id) == [1, 2]
    end

    @tag req: ["FR-405"]
    test "a cluster whose cards were not loaded holds none rather than raising" do
      topic = Topic.from_group(%CardGroup{id: 7, label: "Deploys", inserted_at: at(0)})

      assert topic.cards == []
    end

    @tag req: ["FR-405"]
    test "a card becomes a topic named by its own words" do
      topic = card(3, "Builds are slow", at(0))

      assert topic.kind == :card
      assert topic.key == "card:3"
      assert topic.title == "Builds are slow"
      assert Enum.map(topic.cards, & &1.id) == [3]
    end
  end

  describe "keys" do
    @tag req: ["FR-406"]
    test "a reference and a topic produce the same key" do
      topic = card(3, "text", at(0))

      assert Topic.key(topic) == "card:3"
      assert Topic.key({:card, 3}) == "card:3"
      assert Topic.key({:group, 3}) == "group:3"
    end

    @tag req: ["FR-406"]
    test "a key reads back as the reference it names" do
      assert Topic.parse("card:12") == {:ok, {:card, 12}}
      assert Topic.parse("group:4") == {:ok, {:group, 4}}
      assert Topic.parse({:card, 12}) == {:ok, {:card, 12}}
    end

    @tag req: ["FR-406"]
    test "anything else is not a topic" do
      # A hand-typed parameter must not be mistaken for a topic that happens
      # to exist.
      assert Topic.parse("card:") == :error
      assert Topic.parse("card:12x") == :error
      assert Topic.parse("cardboard:1") == :error
      assert Topic.parse("12") == :error
      assert Topic.parse(nil) == :error
      assert Topic.parse({:column, 1}) == :error
    end
  end

  describe "the two references section 6.3 models" do
    @tag req: ["FR-401"]
    test "exactly one of them names a topic" do
      assert Topic.from_ids(5, nil) == {:ok, {:card, 5}}
      assert Topic.from_ids(nil, 5) == {:ok, {:group, 5}}
    end

    @tag req: ["FR-401"]
    test "neither and both are both refused" do
      assert Topic.from_ids(nil, nil) == :error
      assert Topic.from_ids(5, 6) == :error
    end

    @tag req: ["FR-401"]
    test "a reference turns back into the pair a row stores" do
      assert Topic.to_ids({:card, 5}) == {5, nil}
      assert Topic.to_ids({:group, 5}) == {nil, 5}
      assert Topic.to_ids(card(5, "t", at(0))) == {5, nil}
    end
  end

  describe "rank/1 (FR-405)" do
    @tag req: ["FR-405"]
    test "most votes first" do
      topics = [
        %{card(1, "one", at(0)) | votes: 1},
        %{card(2, "two", at(1)) | votes: 5},
        %{card(3, "three", at(2)) | votes: 3}
      ]

      assert topics |> Topic.rank() |> Enum.map(& &1.id) == [2, 3, 1]
    end

    @tag req: ["FR-405"]
    test "ties are broken by which came first" do
      topics = [
        %{card(1, "later", at(10)) | votes: 2},
        %{card(2, "earlier", at(1)) | votes: 2}
      ]

      assert topics |> Topic.rank() |> Enum.map(& &1.id) == [2, 1]
    end

    @tag req: ["FR-404"]
    test "hidden totals leave only the tiebreak" do
      # An order derived from hidden totals would publish them as plainly as
      # a number does, so `nil` votes must not sort.
      topics = [
        card(1, "later", at(10)),
        card(2, "earlier", at(1))
      ]

      assert topics |> Topic.rank() |> Enum.map(& &1.id) == [2, 1]
    end

    @tag req: ["FR-405"]
    test "a card and a cluster created in the same second still have an order" do
      topics = [card(1, "card", at(0)), group(1, "group", at(0))]

      assert topics |> Topic.rank() |> Enum.map(& &1.key) == ["card:1", "group:1"]
    end
  end
end
