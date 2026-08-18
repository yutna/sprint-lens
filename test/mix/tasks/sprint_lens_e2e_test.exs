defmodule Mix.Tasks.SprintLens.E2eTest do
  use SprintLens.UnitCase, async: false

  alias Mix.Tasks.SprintLens.E2e

  defp record_steps(argv, node_deps_installed? \\ true) do
    test = self()
    E2e.perform(argv, :e2e, "/usr/bin/npx", node_deps_installed?, &send(test, {:step, &1}))
    collect()
  end

  defp collect(acc \\ []) do
    receive do
      {:step, step} -> collect([step | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end

  describe "plan/2" do
    test "rebuilds the database, builds assets, then runs Playwright" do
      assert E2e.plan([], true) == [
               {:mix, "ecto.drop", ["--quiet"]},
               {:mix, "ecto.create", ["--quiet"]},
               {:mix, "ecto.migrate", ["--quiet"]},
               {:mix, "assets.build", []},
               {:cmd, "npx", ["playwright", "test"], "e2e"}
             ]
    end

    test "installs Playwright and its browsers on the first run" do
      [install, browsers | rest] = E2e.plan([], false)

      assert install == {:cmd, "npm", ["install"], "e2e"}
      assert browsers == {:cmd, "npx", ["playwright", "install", "--with-deps"], "e2e"}
      assert length(rest) == 5
    end

    test "skips the install once the browsers are there, so reruns stay fast" do
      refute Enum.any?(E2e.plan([], true), &match?({:cmd, "npm", _, _}, &1))
    end

    test "passes arguments straight through to Playwright" do
      assert List.last(E2e.plan(["--grep", "@spec-10"], true)) ==
               {:cmd, "npx", ["playwright", "test", "--grep", "@spec-10"], "e2e"}
    end

    test "drops the database before creating it, so runs cannot leak into each other" do
      steps = E2e.plan([], true)

      drop = Enum.find_index(steps, &match?({:mix, "ecto.drop", _}, &1))
      create = Enum.find_index(steps, &match?({:mix, "ecto.create", _}, &1))

      assert drop < create
    end

    test "builds assets before starting the browser" do
      steps = E2e.plan([], true)

      assets = Enum.find_index(steps, &match?({:mix, "assets.build", _}, &1))

      playwright =
        Enum.find_index(steps, &match?({:cmd, "npx", ["playwright", "test" | _], _}, &1))

      assert assets < playwright
    end
  end

  describe "perform/5" do
    test "runs every planned step in order" do
      assert [{:mix, "ecto.drop", _} | _] = record_steps([])
    end

    test "runs the install steps first when Playwright is missing" do
      assert [{:cmd, "npm", ["install"], "e2e"} | _] = record_steps([], false)
    end
  end

  describe "ensure_env!/1" do
    test "accepts the e2e environment" do
      assert E2e.ensure_env!(:e2e) == :ok
    end

    test "refuses any other environment, which would point at the wrong database" do
      assert_raise Mix.Error, ~r/must run in the :e2e environment/, fn ->
        E2e.ensure_env!(:dev)
      end
    end
  end

  describe "ensure_node!/1" do
    test "accepts a resolved npx path" do
      assert E2e.ensure_node!("/usr/local/bin/npx") == :ok
    end

    test "explains what is missing instead of failing with enoent" do
      assert_raise Mix.Error, ~r/Node\.js/, fn -> E2e.ensure_node!(nil) end
    end
  end

  describe "execute/1" do
    test "runs a mix task step" do
      assert E2e.execute({:mix, "app.config", []}) != :error
    end

    test "runs a shell step and accepts a zero exit" do
      assert E2e.execute({:cmd, "true", [], "."}) == :ok
    end

    test "stops the run on a non-zero exit rather than carrying on" do
      assert_raise Mix.Error, ~r/exited with 1/, fn ->
        E2e.execute({:cmd, "false", [], "."})
      end
    end
  end

  describe "run/1" do
    test "refuses to run outside the e2e environment" do
      assert_raise Mix.Error, ~r/:e2e environment/, fn -> E2e.run([]) end
    end
  end

  describe "node_deps_installed?/0" do
    test "reports whether the browsers have been downloaded" do
      assert is_boolean(E2e.node_deps_installed?())
    end
  end
end
