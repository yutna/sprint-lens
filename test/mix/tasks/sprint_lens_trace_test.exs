defmodule Mix.Tasks.SprintLens.TraceTest do
  use SprintLens.UnitCase, async: true

  alias Mix.Tasks.SprintLens.Trace

  describe "scan_ids/1" do
    @tag req: ["NFR-501"]
    test "finds every requirement prefix the spec uses" do
      ids = Trace.scan_ids("FR-001 and NFR-102 and AI-014 all matter")

      assert MapSet.equal?(ids, MapSet.new(["FR-001", "NFR-102", "AI-014"]))
    end

    @tag req: ["NFR-501"]
    test "requires exactly three digits, per the spec's numbering rule" do
      ids = Trace.scan_ids("FR-1 FR-01 FR-001 FR-0001")

      assert MapSet.member?(ids, "FR-001")
      refute MapSet.member?(ids, "FR-1")
      refute MapSet.member?(ids, "FR-01")
    end

    @tag req: ["NFR-501"]
    test "deduplicates repeated mentions" do
      assert MapSet.size(Trace.scan_ids("FR-301 FR-301 FR-301")) == 1
    end

    @tag req: ["NFR-501"]
    test "finds nothing in text with no requirements" do
      assert MapSet.size(Trace.scan_ids("just prose")) == 0
    end
  end

  describe "scan_tagged_ids/1" do
    @tag req: ["NFR-501"]
    test "counts ids claimed by an ExUnit req tag" do
      source = ~S|
        @tag req: ["FR-301", "FR-305"]
        test "cards are limited to 500 characters" do
      |

      assert MapSet.equal?(Trace.scan_tagged_ids(source), MapSet.new(["FR-301", "FR-305"]))
    end

    @tag req: ["NFR-501"]
    test "counts a single-string req tag" do
      assert MapSet.equal?(
               Trace.scan_tagged_ids(~S|@tag req: "NFR-102"|),
               MapSet.new(["NFR-102"])
             )
    end

    @tag req: ["NFR-501"]
    test "counts ids claimed by a bracketed Playwright test title" do
      source = ~S|test('[FR-902] one column at a time on narrow screens', async () => {})|

      assert MapSet.equal?(Trace.scan_tagged_ids(source), MapSet.new(["FR-902"]))
    end

    @tag req: ["NFR-501"]
    test "ignores a bare mention, so a TODO cannot satisfy the gate" do
      source = ~S|
        # TODO: FR-706 webhook retries are not implemented yet
        test "something unrelated" do
      |

      assert MapSet.size(Trace.scan_tagged_ids(source)) == 0
    end

    @tag req: ["NFR-501"]
    test "finds several claims in one file" do
      source = ~S|
        @tag req: ["FR-001"]
        test "a" do
        @tag req: ["FR-002", "NFR-206"]
        test "b" do
      |

      assert MapSet.equal?(
               Trace.scan_tagged_ids(source),
               MapSet.new(["FR-001", "FR-002", "NFR-206"])
             )
    end
  end

  describe "spec_ids/0" do
    @tag req: ["NFR-501"]
    test "reads the requirements out of the spec file" do
      ids = Trace.spec_ids()

      assert MapSet.member?(ids, "FR-001")
      assert MapSet.member?(ids, "FR-920")
      assert MapSet.member?(ids, "NFR-102")
      assert MapSet.member?(ids, "AI-018")
    end

    @tag req: ["NFR-501"]
    test "the spec really does define around 150 requirements" do
      assert MapSet.size(Trace.spec_ids()) > 100
    end
  end

  describe "covered_ids/0" do
    @tag req: ["NFR-501"]
    test "collects claims from both the Elixir and the Playwright suites" do
      covered = Trace.covered_ids()

      # Claimed by an ExUnit tag in this repository.
      assert MapSet.member?(covered, "NFR-502")
      # Claimed by a Playwright test title in e2e/specs/health.spec.ts.
      assert MapSet.member?(covered, "NFR-501")
    end
  end

  describe "exceptions/0" do
    @tag req: ["NFR-501"]
    test "documents why each untestable requirement is untestable" do
      exceptions = Trace.exceptions()

      assert Map.has_key?(exceptions, "NFR-204")

      for {id, reason} <- exceptions do
        assert is_binary(reason) and String.length(reason) > 20,
               "#{id} needs a real reason, not a placeholder"
      end
    end

    @tag req: ["NFR-501"]
    test "never lists a requirement that a test already covers" do
      covered = Trace.covered_ids()

      for {id, _reason} <- Trace.exceptions() do
        refute MapSet.member?(covered, id),
               "#{id} is listed as untestable but a test claims it"
      end
    end
  end

  describe "scan_declarations/1" do
    @tag req: ["NFR-501"]
    test "counts a bold requirement declaration" do
      text = "- **FR-301**: During brainstorm, participants MUST be able to create cards."

      assert MapSet.equal?(Trace.scan_declarations(text), MapSet.new(["FR-301"]))
    end

    @tag req: ["NFR-501"]
    test "ignores the numbering ranges in section 2.2, which are not requirements" do
      text = "- FR-001 to FR-099: users and authentication (section 4.1)."

      assert MapSet.size(Trace.scan_declarations(text)) == 0
    end

    @tag req: ["NFR-501"]
    test "ignores a cross-reference to another requirement" do
      text = "- **FR-105**: Team settings MUST include the AI opt-in toggle (see AI-003)."

      assert MapSet.equal?(Trace.scan_declarations(text), MapSet.new(["FR-105"]))
    end
  end

  describe "run/1" do
    @tag req: ["NFR-501"]
    test "counts what the spec asks for against what the tests claim" do
      output = run_task(["--report"])

      assert output =~ "Requirement traceability"
      assert output =~ "spec requirements"
    end

    @tag req: ["NFR-501"]
    test "strict mode passes: every requirement in the spec has a test" do
      # The acceptance criterion itself, run as a test. It fails the moment a
      # requirement loses its last test, or the spec gains one nothing covers.
      output = run_task([])

      assert output =~ "every requirement is covered"
      assert output =~ "uncovered         : 0"
    end

    @tag req: ["NFR-501"]
    test "--write refreshes the report file with a row per requirement" do
      run_task(["--write"])

      report = File.read!("docs/traceability.md")

      assert report =~ "# Requirement traceability"
      assert report =~ "| FR-001 | covered |"
      assert report =~ "| NFR-204 | documented gap |"
      refute report =~ "**uncovered**"
    end

    @tag req: ["NFR-501"]
    test "groups the report by prefix and orders each group by number" do
      run_task(["--write"])

      report = File.read!("docs/traceability.md")

      assert index_of(report, "| AI-001 |") < index_of(report, "| FR-001 |")
      assert index_of(report, "| FR-001 |") < index_of(report, "| NFR-101 |")
      assert index_of(report, "| FR-005 |") < index_of(report, "| FR-101 |")
      assert index_of(report, "| FR-101 |") < index_of(report, "| FR-920 |")
    end
  end

  describe "analyse/3" do
    @tag req: ["NFR-501"]
    test "separates covered, uncovered, documented and unknown" do
      analysis =
        Trace.analyse(
          MapSet.new(["FR-001", "FR-002", "NFR-204"]),
          MapSet.new(["FR-001", "FR-999"]),
          %{"NFR-204" => "deployment concern"}
        )

      assert analysis.tested == 1
      assert analysis.missing == ["FR-002"]
      assert analysis.unknown == ["FR-999"]
      assert analysis.stale_exceptions == []
    end

    @tag req: ["NFR-501"]
    test "flags an exception that a test has started covering" do
      analysis =
        Trace.analyse(
          MapSet.new(["NFR-204"]),
          MapSet.new(["NFR-204"]),
          %{"NFR-204" => "deployment concern"}
        )

      assert analysis.stale_exceptions == ["NFR-204"]
      assert analysis.missing == []
    end

    @tag req: ["NFR-501"]
    test "a documented gap does not count as uncovered" do
      analysis =
        Trace.analyse(MapSet.new(["NFR-204"]), MapSet.new([]), %{"NFR-204" => "reason"})

      assert analysis.missing == []
      assert analysis.tested == 0
    end
  end

  describe "report/2" do
    @tag req: ["NFR-501"]
    test "says so plainly when everything is covered" do
      analysis = Trace.analyse(MapSet.new(["FR-001"]), MapSet.new(["FR-001"]), %{})

      assert capture(fn -> Trace.report(analysis, false) end) =~ "every requirement is covered"
    end

    @tag req: ["NFR-501"]
    test "warns about a test claiming a requirement the spec does not declare" do
      analysis = Trace.analyse(MapSet.new(["FR-001"]), MapSet.new(["FR-001", "FR-777"]), %{})

      output = capture(fn -> Trace.report(analysis, false) end)

      assert output =~ "FR-777"
      assert output =~ "not declared in the spec"
    end

    @tag req: ["NFR-501"]
    test "warns about an exception that is no longer needed" do
      analysis =
        Trace.analyse(MapSet.new(["NFR-204"]), MapSet.new(["NFR-204"]), %{"NFR-204" => "reason"})

      assert capture(fn -> Trace.report(analysis, false) end) =~ "now has a test"
    end

    # The half-built case. The app has passed it, but the task has to keep
    # working for a spec that grows a requirement tomorrow.
    @tag req: ["NFR-501"]
    test "lists what is still to build without failing the build" do
      analysis = Trace.analyse(MapSet.new(["FR-001", "FR-002"]), MapSet.new(["FR-001"]), %{})

      output = capture(fn -> Trace.report(analysis, true) end)

      assert output =~ "still to build: FR-002"
      assert output =~ "uncovered         : 1"
    end

    @tag req: ["NFR-501"]
    test "and fails it in strict mode, naming each requirement with no test" do
      analysis = Trace.analyse(MapSet.new(["FR-001", "FR-002"]), MapSet.new([]), %{})

      # Each uncovered id goes to stderr, where a CI log highlights it.
      errors =
        ExUnit.CaptureIO.capture_io(:stderr, fn ->
          capture(fn ->
            assert_raise Mix.Error, ~r/2 requirement\(s\) have no test/, fn ->
              Trace.report(analysis, false)
            end
          end)
        end)

      assert errors =~ "uncovered: FR-001"
      assert errors =~ "uncovered: FR-002"
    end
  end

  describe "write_report/2" do
    @tag req: ["NFR-501"]
    @tag :tmp_dir
    test "gives each requirement a row saying which of the three it is", ctx do
      path = Path.join(ctx.tmp_dir, "traceability.md")

      analysis =
        Trace.analyse(
          MapSet.new(["FR-001", "FR-002", "NFR-204"]),
          MapSet.new(["FR-001"]),
          %{"NFR-204" => "deployment concern"}
        )

      capture(fn -> Trace.write_report(analysis, path) end)

      report = File.read!(path)

      assert report =~ "| FR-001 | covered | |"
      assert report =~ "| FR-002 | **uncovered** | |"
      assert report =~ "| NFR-204 | documented gap | deployment concern |"
    end
  end

  describe "exceptions/1" do
    @tag req: ["NFR-501"]
    test "treats a missing file as no documented gaps" do
      assert Trace.exceptions("priv/does_not_exist.exs") == %{}
    end
  end

  defp run_task(argv) do
    capture(fn -> Trace.run(argv) end)
  end

  defp capture(fun), do: ExUnit.CaptureIO.capture_io(fun)

  defp index_of(haystack, needle) do
    {index, _length} = :binary.match(haystack, needle)
    index
  end
end
