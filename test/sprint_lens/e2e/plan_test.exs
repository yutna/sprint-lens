defmodule SprintLens.E2E.PlanTest do
  use SprintLens.UnitCase, async: true

  alias SprintLens.E2E.Plan

  describe "steps/2" do
    test "rebuilds the database, builds assets, then runs Playwright" do
      assert Plan.steps([], true) == [
               {:mix, "ecto.drop", ["--quiet"]},
               {:mix, "ecto.create", ["--quiet"]},
               {:mix, "ecto.migrate", ["--quiet"]},
               {:mix, "assets.build", []},
               {:cmd, "npx", ["playwright", "test"], "e2e"}
             ]
    end

    test "installs Playwright and its browsers on the first run" do
      [install, browsers | rest] = Plan.steps([], false)

      assert install == {:cmd, "npm", ["install"], "e2e"}
      assert browsers == {:cmd, "npx", ["playwright", "install", "--with-deps"], "e2e"}
      assert length(rest) == 5
    end

    test "skips the install once the browsers are there, so reruns stay fast" do
      refute Enum.any?(Plan.steps([], true), &match?({:cmd, "npm", _, _}, &1))
    end

    test "passes arguments straight through to Playwright" do
      assert List.last(Plan.steps(["--grep", "@spec-10"], true)) ==
               {:cmd, "npx", ["playwright", "test", "--grep", "@spec-10"], "e2e"}
    end

    test "drops the database before creating it, so runs cannot leak into each other" do
      steps = Plan.steps([], true)

      drop = Enum.find_index(steps, &match?({:mix, "ecto.drop", _}, &1))
      create = Enum.find_index(steps, &match?({:mix, "ecto.create", _}, &1))

      assert drop < create
    end

    test "builds assets before starting the browser" do
      steps = Plan.steps([], true)

      assets = Enum.find_index(steps, &match?({:mix, "assets.build", _}, &1))

      playwright =
        Enum.find_index(steps, &match?({:cmd, "npx", ["playwright", "test" | _], _}, &1))

      assert assets < playwright
    end
  end

  describe "ensure_env!/1" do
    test "accepts the e2e environment" do
      assert Plan.ensure_env!(:e2e) == :ok
    end

    test "refuses any other environment, which would point at the wrong database" do
      assert_raise Mix.Error, ~r/:e2e environment/, fn -> Plan.ensure_env!(:dev) end
    end
  end

  describe "ensure_node!/1" do
    test "accepts a resolved npx path" do
      assert Plan.ensure_node!("/usr/local/bin/npx") == :ok
    end

    test "explains what is missing instead of failing with enoent" do
      assert_raise Mix.Error, ~r/Node\.js/, fn -> Plan.ensure_node!(nil) end
    end
  end

  describe "node_deps_installed?/0 and dir/0" do
    test "report where the Playwright project lives and whether it is installed" do
      assert Plan.dir() == "e2e"
      assert is_boolean(Plan.node_deps_installed?())
    end
  end
end
