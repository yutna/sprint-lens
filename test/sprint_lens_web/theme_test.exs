defmodule SprintLensWeb.ThemeTest do
  use SprintLens.UnitCase, async: true

  alias SprintLensWeb.Theme

  describe "supported/0" do
    @tag req: ["FR-910"]
    test "is light, dark and system" do
      assert Enum.sort(Theme.supported()) == ~w(dark light system)
    end
  end

  describe "supported?/1" do
    @tag req: ["FR-910"]
    test "accepts the three themes and nothing else" do
      assert Theme.supported?("dark")
      assert Theme.supported?("system")
      refute Theme.supported?("neon")
      refute Theme.supported?(nil)
      refute Theme.supported?(:dark)
    end
  end

  describe "resolve/2" do
    @tag req: ["FR-911"]
    test "a signed-in user's saved theme wins over the session" do
      assert Theme.resolve(%{theme: "dark"}, "light") == "dark"
    end

    @tag req: ["FR-910"]
    test "a session choice is used when there is no profile to read" do
      assert Theme.resolve(nil, "dark") == "dark"
    end

    @tag req: ["FR-910"]
    test "a profile holding nonsense falls back rather than rendering it" do
      assert Theme.resolve(%{theme: "neon"}, "light") == "light"
      assert Theme.resolve(%{theme: nil}, nil) == "system"
    end

    @tag req: ["FR-910"]
    test "system is the answer when nobody has chosen anything" do
      assert Theme.resolve(nil) == "system"
      assert Theme.resolve(nil, "neon") == "system"
    end
  end
end
