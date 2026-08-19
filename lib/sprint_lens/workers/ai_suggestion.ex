defmodule SprintLens.Workers.AiSuggestion do
  @moduledoc """
  Runs one AI job (AI-005, AI-006, AI-017).

  ## The concurrency cap is the queue

  AI-006 asks for "a timeout and a concurrency cap". The cap is the `:ai`
  queue's own limit, configured with the rest of Oban rather than invented
  here — two jobs at a time, so a team that asks for six suggestions at once
  does not become six subprocesses on the server.

  ## Failure is a state, not a crash

  A job that fails writes `failed` on the suggestion and returns `:ok`.
  Returning an error would make Oban retry it, and AI-006 asks for the
  opposite: "the core flow continues and the suggestion slot shows a retry
  option" — a retry a person chooses, not one the queue takes on their
  behalf while they wonder why nothing is happening.
  """

  use Oban.Worker, queue: :ai, max_attempts: 1

  require Logger

  alias SprintLens.Admin
  alias SprintLens.AI
  alias SprintLens.AI.Adapter
  alias SprintLens.AI.Scope
  alias SprintLens.AI.Suggestion
  alias SprintLens.Repo
  alias SprintLens.Retro
  alias SprintLens.Retro.Session
  alias SprintLens.Teams.Team

  # AI-006's timeout. Long enough for a model to think, short enough that a
  # facilitator does not sit looking at a spinner through a retrospective.
  @timeout_ms 60_000

  @doc """
  How long a job is allowed to take (AI-006).
  """
  @spec timeout_ms() :: pos_integer()
  def timeout_ms, do: @timeout_ms

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"suggestion_id" => id} = args}) do
    case Repo.get(Suggestion, id) do
      nil -> {:cancel, :suggestion_gone}
      suggestion -> run(suggestion, args["context"] || %{})
    end
  end

  defp run(suggestion, context) do
    # Checked again here: a switch flipped while this sat in the queue has to
    # stop it too (FR-806, AI-003).
    if Admin.ai_enabled?() do
      generate(suggestion, context)
    else
      AI.store_failure(suggestion, :ai_disabled, 0)

      {:cancel, :ai_disabled}
    end
  end

  defp generate(suggestion, context) do
    {:ok, _running} = AI.mark_running(suggestion)

    type = Suggestion.type(suggestion)
    started = System.monotonic_time(:millisecond)

    case build(suggestion, type, context) do
      {:ok, input, scope} ->
        %{
          type: type,
          language: context["language"] || Admin.settings().default_language,
          scope: scope,
          input: input
        }
        |> call_adapter()
        |> finish(suggestion, type, started)

      {:error, reason} ->
        finish({:error, reason}, suggestion, type, started)
    end
  end

  defp call_adapter(request) do
    Adapter.current().generate(request, @timeout_ms)
  rescue
    exception -> {:error, Exception.message(exception)}
  end

  defp finish({:ok, response}, suggestion, type, started) do
    duration = System.monotonic_time(:millisecond) - started
    {:ok, stored} = AI.store_result(suggestion, response, duration)

    log(type, :ok, duration, suggestion)

    {:ok, stored.id}
  end

  defp finish({:error, reason}, suggestion, type, started) do
    duration = System.monotonic_time(:millisecond) - started
    {:ok, _stored} = AI.store_failure(suggestion, reason, duration)

    log(type, :error, duration, suggestion)

    # `:ok`, not an error: the retry belongs to the person, not the queue.
    :ok
  end

  # AI-017: type, timing, size and outcome. Not the prompt and not the
  # answer — an operations log is for knowing whether the thing works, and
  # the content of a retrospective is nobody's operational concern.
  defp log(type, outcome, duration_ms, suggestion) do
    Logger.info("ai job finished",
      ai_type: to_string(type),
      ai_outcome: to_string(outcome),
      ai_duration_ms: duration_ms,
      ai_input_bytes: suggestion.input_bytes,
      suggestion_id: suggestion.id
    )

    :telemetry.execute(
      [:sprint_lens, :ai, :job],
      %{duration: duration_ms, input_bytes: suggestion.input_bytes || 0},
      %{type: to_string(type), outcome: to_string(outcome)}
    )
  end

  # The content is rebuilt from the database rather than carried in the job,
  # so nothing sensitive ever sits in a queue row (AI-015).
  defp build(suggestion, type, context) do
    with {:ok, base} <- context_for(suggestion) do
      Scope.build(type, Map.merge(base, atomise(context)))
    end
  end

  # `get!` rather than a nil branch: both references cascade, so a suggestion
  # whose team or session had vanished would have vanished with it (AI-018).
  defp context_for(%Suggestion{session_id: nil} = suggestion) do
    {:ok, %{team: Repo.get!(Team, suggestion.team_id)}}
  end

  defp context_for(%Suggestion{} = suggestion) do
    session = Session |> Repo.get!(suggestion.session_id) |> Retro.preload()

    {:ok, %{session: session, team: Repo.get!(Team, suggestion.team_id)}}
  end

  defp atomise(context) do
    Map.new(context, fn {key, value} -> {String.to_existing_atom(key), value} end)
  end
end
