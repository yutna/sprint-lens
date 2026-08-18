defmodule SprintLens.E2E.Plan do
  @moduledoc """
  Decides what `mix e2e` should do, without doing any of it.

  Kept apart from `Mix.Tasks.SprintLens.E2e` so the decisions — which
  environment is allowed, what to do when Node is missing, which steps run in
  which order — are unit-tested, while the task module is left with nothing
  but the shelling out.
  """

  @e2e_dir "e2e"

  @typedoc """
  A step is either a mix task to invoke, or an external command to shell out
  to from a working directory.
  """
  @type step ::
          {:mix, String.t(), [String.t()]}
          | {:cmd, String.t(), [String.t()], Path.t()}

  @doc """
  The directory the Playwright project lives in.
  """
  @spec dir() :: Path.t()
  def dir, do: @e2e_dir

  @doc """
  The steps needed to run the suite, in order.

  Installing Playwright is skipped once `e2e/node_modules` exists — it takes
  minutes and downloads three browsers, so repeating it on every run would
  make the suite unusable during development.
  """
  @spec steps([String.t()], boolean()) :: [step()]
  def steps(argv, node_deps_installed?) do
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
  Fails unless the suite is running in the `:e2e` environment, which is where
  the throwaway database and the real server live.
  """
  @spec ensure_env!(atom()) :: :ok
  def ensure_env!(:e2e), do: :ok

  def ensure_env!(env) do
    Mix.raise("the e2e suite must run in the :e2e environment, got #{inspect(env)}")
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
  Whether Playwright and its browsers have already been installed.
  """
  @spec node_deps_installed?() :: boolean()
  def node_deps_installed?, do: File.dir?(Path.join(@e2e_dir, "node_modules"))
end
