# Plan 05 — move the specification into `docs/specs`

## Why this plan exists

`team-retro-spec-en.md` sits in the project root. It is nine hundred
and fifty three lines and it is the normative specification for the
whole application. The review notes ask for it to move into
`docs/specs`, with everything that points at it corrected.

The move is small. The coupling is not, and it fails loudly rather than
quietly, so it is worth doing carefully and doing early.

## What has to move

- `team-retro-spec-en.md` becomes `docs/specs/team-retro-spec-en.md`.

That is the whole file move. Everything else in this plan is about the
references.

## Everything that points at the file

### The code path

`lib/mix/tasks/sprint_lens.trace.ex` holds the filename in a module
attribute and reads it with a bang function inside `spec_ids/0`. The
path is relative to the working directory, so it only ever works when
mix is run from the project root.

This is the one that breaks the build. `mix ci` runs the trace task
with the write flag, so a stale path fails the entire gate on the very
first step that touches it, with a file not found error.

While editing the task, fix an asymmetry that is already there. The
exceptions file and the report file are both taken as optional
arguments with a default, which is what makes them testable. The
specification path, the one that actually needs it, is not an argument
at all. Making it one is a small change that lets the task's own test
stop depending on the real file on disk.

Consider also reading the path from application configuration with the
attribute as the default, so a future move needs no code change. Record
the decision either way.

### The prose

`AGENTS.md` names the file in its opening paragraph, in the sentence
that establishes the specification as normative. Update it.

The README rewritten by plan 04 will link to the specification, so the
two plans must agree on the final path. If plan 04 lands first, the
link is written against the new location from the start.

### The test

`test/mix/tasks/sprint_lens_trace_test.exs` exercises the task against
the real specification file on disk. It fails the moment the module
attribute goes stale, which is useful: the failure is immediate and
obvious rather than subtle.

If the specification path becomes an argument, this test should be
reworked to pass a fixture path for the behavioural assertions, and
keep exactly one assertion against the real file so that a future move
is still caught.

## A broken link that comes along for the ride

Line six of the specification links to a Thai version of itself. That
file does not exist anywhere in the repository. The link is already
broken; moving the file simply carries the broken link to a new
address, and the documentation site planned in plan 08 will publish it.

Three options. Pick one and record it.

- Remove the line. Cheapest, and honest.
- Point it at the Thai user manual that plan 08 produces. Reasonable,
  but a user manual is not a specification, so the wording has to
  change with it.
- Write the Thai specification. Real work, and it creates a second
  normative document that can drift from the first, which is worse than
  having none.

The first option is recommended.

## The change, step by step

1. Create `docs/specs/` and move the file with `git mv`, so the history
   follows it.
2. Update the module attribute in the trace task, and make the path an
   argument with that attribute as its default.
3. Update the sentence in `AGENTS.md`.
4. Resolve the broken Thai link.
5. Rework the trace task test to use a fixture, keeping one assertion
   against the real file.
6. Run `mix ci` and confirm `docs/traceability.md` regenerates
   unchanged. The report contains no path reference, so its content
   should be byte identical. If it is not, something else moved too.

## Verification of plan 05

- `mix ci` green, and specifically the traceability step green.
- `docs/traceability.md` is unchanged after regeneration.
- Searching the repository for the old path returns nothing outside the
  git history and this plan.
- The specification renders correctly on the documentation site with no
  broken internal links.
