defmodule SprintLens.ErrorReporterTest do
  @moduledoc """
  The seam a deployment hooks its error tracker into (NFR-504).

  NFR-504 asks for "a thin integration point; none is mandated", so what is
  under test is the seam: a module named in configuration gets called, with
  the crash and with nothing anybody wrote.
  """

  use SprintLens.UnitCase, async: false

  import ExUnit.CaptureLog

  alias SprintLens.ErrorReporter

  defmodule TestReporter do
    @moduledoc false

    @behaviour SprintLens.ErrorReporter

    @impl SprintLens.ErrorReporter
    def report(source, error, stacktrace, context) do
      send(self(), {:reported, source, error, stacktrace, context})

      :ok
    end
  end

  setup do
    Application.put_env(:sprint_lens, :error_reporter, TestReporter)
    on_exit(fn -> Application.delete_env(:sprint_lens, :error_reporter) end)

    :ok
  end

  describe "the integration point (NFR-504)" do
    @tag req: ["NFR-504"]
    test "a deployment names its reporter in configuration" do
      assert ErrorReporter.current() == TestReporter

      Application.delete_env(:sprint_lens, :error_reporter)

      # And one that names nothing still has somewhere for a crash to go.
      assert ErrorReporter.current() == ErrorReporter.Log
    end

    @tag req: ["NFR-504"]
    test "and it receives the crash" do
      error = %RuntimeError{message: "boom"}

      :ok = ErrorReporter.report(:oban_job, error, [], %{worker: "Something"})

      assert_received {:reported, :oban_job, ^error, [], context}
      assert context.worker == "Something"
    end

    @tag req: ["NFR-502", "NFR-504"]
    test "with the context redacted, so a crash is not a leak" do
      :ok =
        ErrorReporter.report(:live_view, %RuntimeError{message: "boom"}, [], %{
          email: "ploy@example.com",
          secret: "hunter2",
          session_id: 7
        })

      assert_received {:reported, _source, _error, _stacktrace, context}

      refute context.email == "ploy@example.com"
      refute context.secret == "hunter2"
      assert context.session_id == 7
    end
  end

  describe "what it listens to (NFR-504)" do
    @tag req: ["NFR-504"]
    test "the crash events the frameworks already emit" do
      :ok = ErrorReporter.attach()
      on_exit(fn -> :telemetry.detach("sprint-lens-error-reporter") end)

      :telemetry.execute(
        [:oban, :job, :exception],
        %{duration: System.convert_time_unit(12, :millisecond, :native)},
        %{reason: %RuntimeError{message: "job blew up"}, stacktrace: [], kind: :error}
      )

      assert_received {:reported, :oban_job, %RuntimeError{message: "job blew up"}, [], context}
      assert context.event == "oban.job.exception"
      assert context.duration_ms == 12
    end

    @tag req: ["NFR-504"]
    test "and knows which part of the app each came from" do
      sources = [
        {[:oban, :job, :exception], :oban_job},
        {[:phoenix, :live_view, :handle_event, :exception], :live_view},
        {[:phoenix, :live_view, :mount, :exception], :live_view},
        {[:phoenix, :router_dispatch, :exception], :request},
        # Nothing emits this one; the clause exists so a framework that adds
        # an event tomorrow is still reported rather than silently dropped.
        {[:something, :else], :other}
      ]

      for {event, expected} <- sources do
        ErrorReporter.handle_event(event, %{}, %{error: :nope}, nil)

        assert_received {:reported, ^expected, :nope, [], _context}
      end
    end
  end

  describe "the default reporter" do
    @tag req: ["NFR-504", "NFR-502"]
    test "writes the crash down and sends it nowhere" do
      Application.delete_env(:sprint_lens, :error_reporter)

      log =
        capture_log(fn ->
          ErrorReporter.report(
            :request,
            %RuntimeError{message: "boom"},
            [{Foo, :bar, 1, [file: ~c"foo.ex", line: 1]}],
            %{path: "/teams"}
          )
        end)

      assert log =~ "unhandled error"
    end

    @tag req: ["NFR-504"]
    test "and copes with something that is not an exception" do
      Application.delete_env(:sprint_lens, :error_reporter)

      log =
        capture_log(fn ->
          ErrorReporter.report(:oban_job, {:exit, :killed}, :no_stacktrace, %{})
        end)

      assert log =~ "unhandled error"
    end
  end
end
