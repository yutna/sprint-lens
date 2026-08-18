defmodule Mix.Tasks.SprintLens.E2e do
  @moduledoc """
  Runs the Playwright end-to-end suite against a real server.

  Playwright owns the server lifecycle through its `webServer` config, so this
  task's job is to make sure the `:e2e` database is built, the assets are
  compiled, and then hand off to `npx playwright test`.

  Every argument after the task name is passed straight through:

      mix e2e
      mix e2e --project=webkit
      mix e2e --grep "@spec-10"
      mix e2e --headed --debug

  The suite runs on chromium, firefox and webkit, which is as close as this
  repository can get to the browser matrix in NFR-601.

  ## Why this module is excluded from coverage

  Every line here shells out or launches a browser fleet; there is nothing to
  unit-test that would not mean running the suite from inside the suite. The
  decisions live in `SprintLens.E2E.Plan`, which is fully covered, and this
  module is exercised for real by `mix verify`. The exclusion is recorded in
  `coveralls.json`.
  """

  @shortdoc "Runs the Playwright end-to-end suite"

  use Mix.Task

  alias SprintLens.E2E.Plan

  @requirements ["app.config"]

  @impl Mix.Task
  def run(argv), do: dispatch(argv, Mix.env())

  # Mix runs the sub-tasks of an alias in the parent's environment, so
  # `mix verify` (which runs in `:test`) would otherwise reach the suite in
  # the wrong environment. Re-exec rather than refuse: `mix e2e` then works
  # from anywhere, which is what a person typing it expects.
  defp dispatch(argv, :e2e) do
    Plan.ensure_env!(:e2e)
    Plan.ensure_node!(System.find_executable("npx"))

    argv
    |> Plan.steps(Plan.node_deps_installed?())
    |> Enum.each(&execute/1)
  end

  defp dispatch(argv, _env) do
    opts = [env: [{"MIX_ENV", "e2e"}], into: IO.stream(:stdio, :line), stderr_to_stdout: true]

    case System.cmd("mix", ["e2e" | argv], opts) do
      {_output, 0} -> :ok
      {_output, status} -> Mix.raise("mix e2e exited with #{status}")
    end
  end

  # A non-zero exit stops the run: a failed asset build makes every
  # subsequent browser assertion meaningless.
  defp execute({:mix, task, args}), do: Mix.Task.run(task, args)

  defp execute({:cmd, command, args, cd}) do
    opts = [into: IO.stream(:stdio, :line), stderr_to_stdout: true, cd: cd]

    case System.cmd(command, args, opts) do
      {_output, 0} -> :ok
      {_output, status} -> Mix.raise("`#{command} #{Enum.join(args, " ")}` exited with #{status}")
    end
  end
end
