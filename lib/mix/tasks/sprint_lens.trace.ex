defmodule Mix.Tasks.SprintLens.Trace do
  @moduledoc """
  Checks that every requirement in the spec is covered by at least one test.

  Line coverage alone cannot answer "did we build what was asked for" — code
  can be fully covered and still miss a requirement entirely. This task closes
  that gap: it reads every requirement id out of the spec, reads every `req`
  tag out of the test suites, and fails if any id has no test pointing at it.

  Elixir tests declare coverage with a tag:

      @tag req: ["FR-301", "FR-305"]
      test "a card is limited to 500 characters" do

  Playwright tests declare it in the test title:

      test('[FR-902] one column at a time on narrow screens', ...)

  Requirements that genuinely cannot be tested automatically are listed in
  `priv/traceability_exceptions.exs` with a reason. They are reported, never
  silently skipped.

      mix sprint_lens.trace           # fail if anything is uncovered
      mix sprint_lens.trace --report  # print the gap, do not fail
      mix sprint_lens.trace --write   # also refresh docs/traceability.md

  `--report` is for a half-built app: milestones land in order, so most
  requirements are legitimately uncovered until the one that implements them.
  Every milestone has now landed, so `mix ci` runs the strict form, and that is
  the gate the app has to keep passing.
  """

  @shortdoc "Verifies every spec requirement is covered by a test"

  use Mix.Task

  @spec_file "team-retro-spec-en.md"
  @exceptions_file "priv/traceability_exceptions.exs"
  @report_file "docs/traceability.md"
  @test_paths ["test", "e2e"]

  # FR-001, NFR-102, AI-014 — three digits, never renumbered (§2.2).
  @id_pattern ~r/\b((?:FR|NFR|AI)-\d{3})\b/

  # A requirement is *declared* in bold: `- **FR-001**: The system MUST ...`.
  # Section 2.2 also lists numbering ranges ("FR-001 to FR-099: users and
  # authentication"), and those endpoints are not requirements.
  @declaration_pattern ~r/\*\*((?:FR|NFR|AI)-\d{3})\*\*/

  @impl Mix.Task
  def run(argv) do
    {opts, _argv} = OptionParser.parse!(argv, strict: [write: :boolean, report: :boolean])

    analysis = analyse(spec_ids(), covered_ids(), exceptions())

    if opts[:write], do: write_report(analysis)

    report(analysis, opts[:report])
  end

  @doc """
  Compares what the spec requires against what the tests claim.

  Pure, so the interesting combinations — a stale exception, a test claiming a
  requirement that no longer exists, everything covered — can be exercised
  without arranging files on disk.
  """
  @spec analyse(MapSet.t(String.t()), MapSet.t(String.t()), %{String.t() => String.t()}) :: map()
  def analyse(required, covered, exceptions) do
    %{
      required: required,
      covered: covered,
      exceptions: exceptions,
      tested: required |> MapSet.intersection(covered) |> MapSet.size(),
      missing:
        required
        |> MapSet.difference(covered)
        |> MapSet.difference(MapSet.new(Map.keys(exceptions)))
        |> Enum.sort(),
      # An exception that a test now covers is a lie waiting to be believed.
      stale_exceptions:
        exceptions |> Map.keys() |> Enum.filter(&MapSet.member?(covered, &1)) |> Enum.sort(),
      # A test claiming an id the spec does not declare means either a typo or
      # a requirement that was removed.
      unknown: covered |> MapSet.difference(required) |> Enum.sort()
    }
  end

  @doc """
  Every requirement id declared in the spec.
  """
  @spec spec_ids() :: MapSet.t(String.t())
  def spec_ids do
    @spec_file
    |> File.read!()
    |> scan_declarations()
  end

  @doc """
  Extracts the requirement ids a document *declares*, as opposed to merely
  mentions.
  """
  @spec scan_declarations(String.t()) :: MapSet.t(String.t())
  def scan_declarations(text) do
    @declaration_pattern
    |> Regex.scan(text, capture: :all_but_first)
    |> Enum.map(&hd/1)
    |> MapSet.new()
  end

  @doc """
  Every requirement id claimed by a test, across both suites.
  """
  @spec covered_ids() :: MapSet.t(String.t())
  def covered_ids do
    @test_paths
    |> Enum.flat_map(&test_files/1)
    |> Enum.reduce(MapSet.new(), fn file, acc ->
      MapSet.union(acc, file |> File.read!() |> scan_tagged_ids())
    end)
  end

  @doc """
  Requirements that cannot be covered by an automated test, mapped to the
  reason they cannot.
  """
  @spec exceptions(Path.t()) :: %{String.t() => String.t()}
  def exceptions(path \\ @exceptions_file) do
    if File.exists?(path) do
      {map, _bindings} = Code.eval_file(path)
      map
    else
      %{}
    end
  end

  @doc """
  Extracts requirement ids from arbitrary text.
  """
  @spec scan_ids(String.t()) :: MapSet.t(String.t())
  def scan_ids(text) do
    @id_pattern
    |> Regex.scan(text, capture: :all_but_first)
    |> Enum.map(&hd/1)
    |> MapSet.new()
  end

  @doc """
  Extracts requirement ids that a test file *claims*, rather than merely
  mentions.

  Only ids inside a `req:` tag or a bracketed test-title prefix count. A bare
  mention in a comment does not, otherwise copying a requirement id into a
  TODO would silently satisfy the gate.
  """
  @spec scan_tagged_ids(String.t()) :: MapSet.t(String.t())
  def scan_tagged_ids(source) do
    tag_claims = Regex.scan(~r/req:\s*(\[[^\]]*\]|"[^"]*")/, source, capture: :all_but_first)
    title_claims = Regex.scan(~r/\[((?:FR|NFR|AI)-\d{3})\]/, source, capture: :all_but_first)

    tag_ids =
      tag_claims
      |> Enum.map(&hd/1)
      |> Enum.reduce(MapSet.new(), fn claim, acc -> MapSet.union(acc, scan_ids(claim)) end)

    title_ids = title_claims |> Enum.map(&hd/1) |> MapSet.new()

    MapSet.union(tag_ids, title_ids)
  end

  # This task's own test file is full of example `req:` tags used to exercise
  # the scanner. Counting them would let the scanner's fixtures satisfy the
  # gate they exist to enforce.
  @self_test "test/mix/tasks/sprint_lens_trace_test.exs"

  defp test_files(root) do
    if File.dir?(root) do
      root
      |> Path.join("**/*.{exs,ex,ts,js}")
      |> Path.wildcard()
      |> Enum.reject(&(String.contains?(&1, "node_modules") or &1 == @self_test))
    else
      []
    end
  end

  @doc """
  Prints an analysis and, unless `report_only?`, fails the build when a
  requirement has no test.
  """
  @spec report(map(), boolean() | nil) :: :ok
  def report(analysis, report_only?) do
    Mix.shell().info("""
    Requirement traceability
      spec requirements : #{MapSet.size(analysis.required)}
      covered by tests  : #{analysis.tested}
      documented gaps   : #{map_size(analysis.exceptions)}
      uncovered         : #{length(analysis.missing)}
    """)

    Enum.each(analysis.unknown, fn id ->
      warn("#{id} is claimed by a test but is not declared in the spec")
    end)

    Enum.each(analysis.stale_exceptions, fn id ->
      warn("#{id} now has a test — remove it from #{@exceptions_file}")
    end)

    announce(analysis.missing, report_only?)
  end

  defp announce([], _report_only?) do
    Mix.shell().info([:green, "  every requirement is covered", :reset])
  end

  defp announce(missing, true) do
    Mix.shell().info("  still to build: #{Enum.join(missing, ", ")}")
  end

  defp announce(missing, _report_only?) do
    Enum.each(missing, fn id -> Mix.shell().error("  uncovered: #{id}") end)

    Mix.raise(
      "#{length(missing)} requirement(s) have no test. " <>
        "Add a `req:` tag, or document the gap in #{@exceptions_file}."
    )
  end

  defp warn(message), do: Mix.shell().info([:yellow, "  warning: ", :reset, message])

  @doc """
  Writes the analysis out as a table, one row per requirement.

  Takes the path so the "uncovered" row can be exercised without the finished
  app's report — which, the app being finished, no longer has one.
  """
  @spec write_report(map(), Path.t()) :: :ok
  def write_report(analysis, path \\ @report_file) do
    %{required: required, covered: covered, exceptions: exceptions} = analysis

    rows =
      required
      |> Enum.sort_by(&sort_key/1)
      |> Enum.map(fn id ->
        cond do
          MapSet.member?(covered, id) -> "| #{id} | covered | |"
          Map.has_key?(exceptions, id) -> "| #{id} | documented gap | #{exceptions[id]} |"
          true -> "| #{id} | **uncovered** | |"
        end
      end)

    body = """
    # Requirement traceability

    Generated by `mix sprint_lens.trace --write`. Do not edit by hand.

    A requirement counts as covered when at least one test claims it, either
    with an ExUnit `@tag req: [...]` or a `[FR-nnn]` prefix in a Playwright
    test title.

    | Requirement | Status | Note |
    | --- | --- | --- |
    #{Enum.join(rows, "\n")}
    """

    File.mkdir_p!(Path.dirname(path))
    File.write!(path, body)
    Mix.shell().info("  wrote #{path}")
  end

  # Sorts FR-002 before FR-010 before NFR-101, rather than lexically.
  defp sort_key(id) do
    [prefix, number] = String.split(id, "-")
    {prefix, String.to_integer(number)}
  end
end
