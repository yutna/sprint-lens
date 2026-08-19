defmodule SprintLens.AI.ClaudeCli.Runner do
  @moduledoc """
  Starts the Claude Code CLI and waits for it (AI-007, AI-008).

  ## Why this is its own module

  It is the one function in the AI module that cannot be tested without
  either a real model call or an elaborate fake `claude` on `PATH`, and
  neither would tell you anything the pure parts of
  `SprintLens.AI.ClaudeCliAdapter` do not. Keeping it alone in a file means
  the coverage exclusion is exactly one function wide rather than covering
  the prompt building and response parsing that surround it — those are
  tested.

  The exclusion is recorded in `coveralls.json` with this reason.
  """

  @executable "claude"

  @doc """
  Runs the CLI in `dir` with `prompt`, killing it at `timeout_ms`
  (AI-006, AI-008).

  `--allowed-tools ""` is AI-008's "no tool permissions beyond reading the
  prepared input file": the process gets its prompt and nothing else.
  Credentials come from the environment the server was started with, so they
  are the deployment's business and never this application's.
  """
  @spec run(Path.t(), String.t(), pos_integer()) ::
          {String.t(), non_neg_integer()} | {:error, term()}
  def run(dir, prompt, timeout_ms) do
    task =
      Task.async(fn ->
        System.cmd(
          @executable,
          ["-p", prompt, "--output-format", "json", "--allowed-tools", ""],
          cd: dir,
          stderr_to_stdout: true
        )
      end)

    case Task.yield(task, timeout_ms) || Task.shutdown(task, :brutal_kill) do
      {:ok, result} -> result
      nil -> {:error, {:timeout, timeout_ms}}
    end
  rescue
    error -> {:error, {:executable_missing, Exception.message(error)}}
  end
end
