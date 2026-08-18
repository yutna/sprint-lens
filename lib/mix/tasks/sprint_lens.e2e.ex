defmodule Mix.Tasks.SprintLens.E2e do
  @moduledoc """
  Runs the Playwright end-to-end suite against a real server.

  Playwright owns the server lifecycle through its `webServer` config, so this
  task's job is to make sure the `:e2e` database is built and seeded, the
  assets are compiled, and then hand off to `npx playwright test`.

  Every argument after the task name is passed straight through:

      mix e2e
      mix e2e --project=webkit
      mix e2e --grep "@spec-10"
      mix e2e --headed --debug

  The suite runs on chromium, firefox and webkit, which is as close as this
  repository can get to the browser matrix in NFR-601.

  ## Structure

  Deciding *what* to run is separated from actually running it. `plan/2`
  returns the list of steps as data, which is what the tests assert on; the
  side effects live in one-line runners that a test injects around.
  """

  @shortdoc "Runs the Playwright end-to-end suite"

  use Mix.Task

  @requirements ["app.config"]

  @e2e_dir "e2e"

  @typedoc """
  A step is either a mix task to invoke, or an external command to shell out
  to from a working directory.
  """
  @type step ::
          {:mix, String.t(), [String.t()]}
          | {:cmd, String.t(), [String.t()], Path.t()}

  @impl Mix.Task
  def run(argv) do
    perform(argv, Mix.env(), System.find_executable("npx"), node_deps_installed?(), &execute/1)
  end

  @doc """
  The task body, with everything it depends on passed in.

  Keeping `run/1` to a single line of wiring means the decisions here — which
  environment is allowed, what to do when Node is missing, which steps run in
  which order — are all exercised by tests rather than only by a real e2e run.
  """
  @spec perform([String.t()], atom(), String.t() | nil, boolean(), (step() -> any())) :: :ok
  def perform(argv, env, npx_path, node_deps_installed?, executor) do
    ensure_env!(env)
    ensure_node!(npx_path)

    argv
    |> plan(node_deps_installed?)
    |> Enum.each(executor)

    :ok
  end

  @doc """
  Whether Playwright and its browsers have already been installed.
  """
  @spec node_deps_installed?() :: boolean()
  def node_deps_installed?, do: File.dir?(Path.join(@e2e_dir, "node_modules"))

  @doc """
  The steps needed to run the suite, in order.

  Installing Playwright is skipped once `e2e/node_modules` exists — it takes
  minutes and downloads three browsers, so repeating it on every run would
  make the suite unusable during development.
  """
  @spec plan([String.t()], boolean()) :: [step()]
  def plan(argv, node_deps_installed?) do
    install =
      if node_deps_installed? do
        []
      else
        [
          {:cmd, "npm", ["install"], @e2e_dir},
          {:cmd, "npx", ["playwright", "install", "--with-deps"], @e2e_dir}
        ]
      end

    install ++
      [
        # A fresh database every run: e2e tests share one server, so leftover
        # rows from a previous run would make them order-dependent.
        {:mix, "ecto.drop", ["--quiet"]},
        {:mix, "ecto.create", ["--quiet"]},
        {:mix, "ecto.migrate", ["--quiet"]},
        {:mix, "assets.build", []},
        {:cmd, "npx", ["playwright", "test" | argv], @e2e_dir}
      ]
  end

  @doc """
  Fails unless the task is running in the `:e2e` environment, which is where
  the throwaway database and the real server live.
  """
  @spec ensure_env!(atom()) :: :ok
  def ensure_env!(:e2e), do: :ok

  def ensure_env!(env) do
    Mix.raise("mix e2e must run in the :e2e environment, got #{inspect(env)}")
  end

  @doc """
  Fails with an actionable message when Node is missing, rather than letting
  `System.cmd/3` raise `:enoent`.
  """
  @spec ensure_node!(String.t() | nil) :: :ok
  def ensure_node!(nil) do
    Mix.raise("npx was not found on PATH. Playwright needs Node.js to run the e2e suite.")
  end

  def ensure_node!(_path), do: :ok

  @doc """
  Carries out one step. A non-zero exit stops the run: a failed asset build
  makes every subsequent browser assertion meaningless.
  """
  @spec execute(step()) :: any()
  def execute({:mix, task, args}), do: Mix.Task.run(task, args)

  def execute({:cmd, command, args, cd}) do
    opts = [into: IO.stream(:stdio, :line), stderr_to_stdout: true, cd: cd]

    case System.cmd(command, args, opts) do
      {_output, 0} -> :ok
      {_output, status} -> Mix.raise("`#{command} #{Enum.join(args, " ")}` exited with #{status}")
    end
  end
end
