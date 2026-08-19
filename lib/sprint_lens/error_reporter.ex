defmodule SprintLens.ErrorReporter do
  @moduledoc """
  Where crashes go (NFR-504).

  NFR-504 asks for "a thin integration point; none is mandated", which is an
  unusual requirement in that it asks for a *seam* rather than a feature. So
  this is a behaviour with a default that writes a log line, attached to the
  telemetry events Phoenix and Oban already emit when something raises. A
  deployment that wants Sentry, AppSignal or anything else configures a
  module here and changes nothing else.

  ## What a report may contain

  The same rule as everywhere else: what went wrong, where, and nothing
  anybody wrote. The payload goes through `SprintLens.Redact.payload/1`, so a
  crash inside a card mutation does not put the card's text into somebody
  else's error tracker (NFR-502, AI-017).
  """

  require Logger

  alias SprintLens.Redact

  @typedoc """
  Where the crash happened. Enough for a tracker to group by, not so much
  that grouping becomes useless.
  """
  @type source :: :oban_job | :live_view | :request | :other

  @doc """
  Reports one crash. Whatever a deployment configures here is called with the
  exception, the stacktrace and a context map that has already been redacted.
  """
  @callback report(source(), Exception.t() | term(), Exception.stacktrace(), map()) :: :ok

  @doc """
  Hands a crash to whatever this deployment reports to.
  """
  @spec report(source(), term(), Exception.stacktrace(), map()) :: :ok
  def report(source, error, stacktrace, context \\ %{}) do
    current().report(source, error, stacktrace, Redact.payload(context))
  end

  @doc """
  The reporter this deployment uses (NFR-504).
  """
  @spec current() :: module()
  def current, do: Application.get_env(:sprint_lens, :error_reporter, __MODULE__.Log)

  @doc """
  Subscribes to the crash events Phoenix and Oban already emit.

  Attaching here rather than sprinkling `rescue` clauses through the app: the
  frameworks already know when something raised, and a reporter that only
  hears about the crashes somebody remembered to wrap is worse than none.
  """
  @spec attach() :: :ok
  def attach do
    events = [
      [:oban, :job, :exception],
      [:phoenix, :live_view, :handle_event, :exception],
      [:phoenix, :live_view, :mount, :exception],
      [:phoenix, :router_dispatch, :exception]
    ]

    :telemetry.attach_many(
      "sprint-lens-error-reporter",
      events,
      &__MODULE__.handle_event/4,
      nil
    )

    :ok
  end

  @doc false
  def handle_event(event, measurements, metadata, _config) do
    report(source(event), metadata[:reason] || metadata[:error], metadata[:stacktrace] || [], %{
      event: Enum.join(event, "."),
      duration_ms: System.convert_time_unit(measurements[:duration] || 0, :native, :millisecond),
      kind: metadata[:kind]
    })
  end

  defp source([:oban | _rest]), do: :oban_job
  defp source([:phoenix, :live_view | _rest]), do: :live_view
  defp source([:phoenix, :router_dispatch | _rest]), do: :request
  defp source(_event), do: :other

  defmodule Log do
    @moduledoc """
    The default reporter: a log line, and nothing leaves the machine
    (NFR-504).

    A deployment that has an error tracker replaces this with one line of
    configuration. A deployment that has not still gets the crash written
    down in the structured format `SprintLens.LogFormatter` produces
    (NFR-502).
    """

    @behaviour SprintLens.ErrorReporter

    require Logger

    @impl SprintLens.ErrorReporter
    def report(source, error, stacktrace, context) do
      Logger.error("unhandled error",
        error_source: to_string(source),
        error_message: message(error),
        error_context: inspect(context),
        error_stacktrace: format(stacktrace)
      )

      :ok
    end

    defp message(%{__exception__: true} = exception), do: Exception.message(exception)
    defp message(other), do: inspect(other)

    # The first few frames: enough to find the code, short enough to read.
    defp format(stacktrace) when is_list(stacktrace) do
      stacktrace |> Enum.take(5) |> Exception.format_stacktrace()
    end

    defp format(other), do: inspect(other)
  end
end
