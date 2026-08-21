defmodule SprintLens.Types.JsonListTest do
  use SprintLens.UnitCase, async: true

  alias SprintLens.Types.JsonList

  @columns [%{"name" => "Start", "hint" => nil}, %{"name" => "Stop", "hint" => "Why?"}]

  describe "the type itself" do
    @tag req: ["FR-202"]
    test "is stored as text, which both databases have" do
      assert JsonList.type() == :string
    end
  end

  describe "cast/1" do
    @tag req: ["FR-202"]
    test "takes a list of columns, and nothing else" do
      assert JsonList.cast(@columns) == {:ok, @columns}
      assert JsonList.cast(nil) == {:ok, nil}
      assert JsonList.cast(%{"name" => "Start"}) == :error
      assert JsonList.cast("Start") == :error
    end
  end

  describe "dump/1 and load/1" do
    @tag req: ["FR-202"]
    test "round-trip through JSON without changing the layout" do
      assert {:ok, encoded} = JsonList.dump(@columns)
      assert is_binary(encoded)
      assert JsonList.load(encoded) == {:ok, @columns}
    end

    @tag req: ["FR-202"]
    test "nothing is nothing, in both directions" do
      assert JsonList.dump(nil) == {:ok, nil}
      assert JsonList.load(nil) == {:ok, nil}
    end

    @tag req: ["FR-202"]
    test "refuses to dump anything that is not a layout" do
      assert JsonList.dump(%{"name" => "Start"}) == :error
      assert JsonList.dump("Start") == :error
    end

    # A column holding valid JSON that is not a list is a row nobody can
    # render. Better an error at the boundary than a page that half works.
    @tag req: ["FR-202"]
    test "refuses to load anything that is not a layout" do
      assert JsonList.load(~s({"name": "Start"})) == :error
      assert JsonList.load("not json at all") == :error
      assert JsonList.load(42) == :error
    end
  end
end
