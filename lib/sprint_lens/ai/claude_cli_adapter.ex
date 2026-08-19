defmodule SprintLens.AI.ClaudeCliAdapter do
  @moduledoc """
  The reference adapter: the Claude Code CLI, run on the server (AI-007,
  AI-008).

  ## The shape of an invocation

      claude -p "$(cat job-prompt.txt)" --output-format json > result.json

  Prompt in, JSON out, parsed into §5.2's envelope. Browsers never call a
  model; the only thing that leaves this machine is what
  `SprintLens.AI.Scope.build/2` allowed (AI-007, AI-015).

  ## The sandbox

  AI-008 asks for a sandboxed working directory, credentials from the server
  environment, no tool permissions beyond reading the prepared input, and the
  timeout from AI-006. Each job gets:

    * a fresh temporary directory, deleted afterwards, holding one file;
    * `--allowed-tools ""`, so the CLI cannot reach anything but its prompt;
    * the environment the server was started with, so credentials are the
      deployment's business and never this application's;
    * a hard kill at the timeout, because a provider that hangs is the
      failure this adapter exists to turn into a retryable error.

  ## Why almost none of this is unit-tested

  Everything decidable — the prompt, the parsing, the sandbox, the cleanup —
  is testable, because the one thing that is not is behind
  `SprintLens.AI.ClaudeCli.Runner`, which is swappable by configuration. A
  test supplies a runner that answers without starting anything, and
  everything around it runs for real: a directory is created, a file is
  written, the answer is parsed, the directory is removed.

  Running the CLI itself in a test would mean either a real model call or an
  elaborate fake `claude` on `PATH`, and neither tells you anything the rest
  of this module does not. The suite runs against
  `SprintLens.AI.FakeAdapter` anyway, and that substitution is itself the
  test of AI-004.
  """

  @behaviour SprintLens.AI.Adapter

  @prompt_file "job-prompt.txt"

  @impl SprintLens.AI.Adapter
  def generate(request, timeout_ms) do
    prompt = build_prompt(request)

    with {:ok, dir} <- sandbox() do
      try do
        dir
        |> Path.join(@prompt_file)
        |> File.write!(prompt)

        dir
        |> runner().run(prompt, timeout_ms)
        |> interpret(request)
      after
        File.rm_rf(dir)
      end
    end
  end

  @doc """
  Where the prepared input file is written, which is the only thing the CLI
  is allowed to read (AI-008).
  """
  @spec prompt_file() :: String.t()
  def prompt_file, do: @prompt_file

  @doc """
  The prompt one job sends.

  Built from the request rather than from a template file: the instruction
  and the content belong together, and a prompt assembled in two places is a
  prompt nobody can read.
  """
  @spec build_prompt(SprintLens.AI.Adapter.request()) :: String.t()
  def build_prompt(%{type: type, language: language, input: input}) do
    """
    #{instruction(type)}

    Answer in #{language_name(language)}. Reply with #{format_for(type)} and
    nothing else — no preamble, no explanation of what you did.

    The retrospective's content follows as JSON. It carries no names: who
    wrote what is deliberately not included, and you must not speculate
    about it.

    #{Jason.encode!(input, pretty: true)}
    """
  end

  @doc """
  Reads the CLI's JSON output into the envelope's `output` object (AI-007).

  The CLI wraps the model's answer in an object of its own; anything else in
  there is the tool's business rather than this application's.
  """
  @spec parse(String.t()) :: {:ok, String.t()} | {:error, term()}
  def parse(output) do
    case Jason.decode(output) do
      {:ok, %{"result" => content}} when is_binary(content) -> {:ok, content}
      {:ok, %{"content" => content}} when is_binary(content) -> {:ok, content}
      {:ok, _other} -> {:error, :unexpected_response}
      {:error, _reason} -> {:error, :invalid_json}
    end
  end

  @doc """
  Turns what the subprocess did into what the adapter promises.
  """
  @spec interpret({String.t(), non_neg_integer()} | {:error, term()}, map()) ::
          {:ok, SprintLens.AI.Adapter.response()} | {:error, term()}
  def interpret({:error, reason}, _request), do: {:error, reason}

  def interpret({output, 0}, request) do
    with {:ok, content} <- parse(output) do
      {:ok, %{format: format_for(request.type), content: content}}
    end
  end

  def interpret({output, status}, _request) do
    # The CLI's own message is kept, trimmed: an operator needs to know
    # whether it was a credential problem or a network one, and the answer
    # is usually in the first line.
    {:error, {:exit_status, status, output |> String.trim() |> String.slice(0, 200)}}
  end

  # Swappable so the sandbox, the file and the parsing can all be exercised
  # without starting a subprocess.
  defp runner do
    Application.get_env(:sprint_lens, :ai_cli_runner, SprintLens.AI.ClaudeCli.Runner)
  end

  # Raises rather than branching on a temporary directory that cannot be
  # created: the worker turns any exception into a failed suggestion with a
  # retry, and a machine that cannot write to its own tmp has a bigger
  # problem than this job.
  defp sandbox do
    dir =
      Path.join(
        System.tmp_dir!(),
        "sprintlens-ai-#{Base.url_encode64(:crypto.strong_rand_bytes(9), padding: false)}"
      )

    File.mkdir_p!(dir)

    {:ok, dir}
  end

  ## What each feature asks for (section 5.4)

  defp instruction(:session_summary) do
    "Draft a structured recap of this retrospective: the themes that came " <>
      "up, what the team decided, and what they agreed to do."
  end

  defp instruction(:clustering) do
    "Group the cards below by what they are about. Suggest a short label " <>
      "for each group and list the card ids in it."
  end

  defp instruction(:action_draft) do
    "Draft one clear, specific action item from the topic and note below. " <>
      "One sentence, starting with a verb."
  end

  defp instruction(:recurring_themes) do
    "Across these past retrospectives, point out the topics that keep " <>
      "coming back, and say which sessions each appeared in."
  end

  defp instruction(:icebreakers) do
    "Suggest five short check-in questions for a team retrospective."
  end

  defp instruction(:translation) do
    "Translate the text below. Keep the meaning and the tone; do not add " <>
      "anything."
  end

  defp format_for(type) when type in [:clustering, :icebreakers], do: "json"
  defp format_for(_type), do: "markdown"

  defp language_name("th"), do: "Thai"
  defp language_name(_other), do: "English"
end
