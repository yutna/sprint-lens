# Plan 06 — GitHub Actions

## Why this plan exists

There is no `.github` directory in the repository at all. No workflows,
no issue templates, no pull request template, no dependency updates, no
code owners. Every gate is currently run by hand.

The repository already has a well defined pipeline in the form of two
mix aliases, so this plan is mostly about running what exists in the
right places, with the right caching, and about the handful of traps
this particular project sets.

## What already anticipates CI

Worth knowing before designing the workflows, because some of the work
is done.

- `mix ci` and `mix verify` are complete pipeline definitions.
- The Playwright configuration already branches on the continuous
  integration environment variable: it forbids focused tests, retries
  once, and switches to the GitHub reporter. The target was clearly
  intended to be GitHub Actions.
- The test configuration already supports a partition variable, so
  splitting the ExUnit suite across parallel jobs needs no code change.
- The coverage tasks for the hosted service are already registered with
  their preferred environment, so publishing coverage is one secret
  away.

## The workflows

### Workflow one — the change gate

Runs on every push and every pull request.

Steps: check out, set up Erlang and Elixir with a pinned version,
restore the dependency and build caches, restore the dialyzer cache,
fetch dependencies, then run `mix ci`.

Do not decompose `mix ci` into separate steps. It is the definition of
the gate, it is what a developer runs locally, and the two must not
drift apart. A failure inside it is already legible from the log.

After plan 09 lands, this job runs as a matrix over both database
adapters.

### Workflow two — the end to end suite

Runs on pull requests and on pushes to the default branch. Kept
separate from the change gate because it is slower and needs browsers.

Steps: check out, set up Erlang, Elixir and Node, restore the mix
caches, restore the Playwright browser cache, install browsers with
their system dependencies, then run `mix e2e`. Upload the report and
any failure traces as artefacts, since the suite is configured to keep
traces, screenshots and video on failure and they are the only way to
debug a remote failure.

### Workflow three — the documentation site

Owned by plan 08 but listed here so the CI picture is complete. Builds
the documentation and publishes it to GitHub Pages on pushes to the
default branch.

### Workflow four — scheduled maintenance

A weekly run of the full acceptance gate against the default branch.
This catches decay that no pull request touches: an upstream browser
update, a dependency advisory, a flaky test that only appears over
time.

## Traps specific to this repository

### The traceability report is rewritten by the gate

`mix ci` ends with the trace task in write mode, which rewrites
`docs/traceability.md`, a tracked file. In a workflow that means the
working tree is dirty after a successful run.

Two options.

- Fail on drift. Add a check that the tree is clean after `mix ci` and
  fail with a message telling the author to run `mix ci` locally and
  commit the regenerated report. Recommended: the report becomes part
  of the reviewable diff, which is the point of tracking it.
- Commit the regenerated report from the workflow. Rejected: it means
  the workflow writes to branches, and the report silently changes
  under the author.

### Dialyzer needs a cached PLT

The build tables are configured to live under `priv/plts`, which is
ignored by git. Without a cache, every run rebuilds them, and the job
becomes too slow to be useful. Cache them keyed on the Erlang and
Elixir versions and the dependency lock file, and restore with a prefix
fallback so a lock file change reuses most of the previous table.

### The end to end suite owns its own server

The Playwright configuration starts the application itself, waits on
the health endpoint, and reuses an existing server only when not in
continuous integration. Do not start the server in a separate workflow
step; it will conflict.

The health endpoint is also the readiness probe, so a failure to start
shows up as a timeout waiting on that URL rather than as a compile
error. Pipe the server output into the job log so the real cause is
visible.

### The e2e TypeScript is unlinted

The formatter configuration covers Elixir and HEEx only. Nothing checks
the TypeScript under `e2e/` at all. Decide whether to add a formatter
and a linter for it and enforce them in the change gate. Recommended,
since that directory is now two thousand lines and growing.

## Caching

Four caches, in order of value.

- The dialyzer tables, keyed on toolchain plus lock file.
- `deps` and `_build`, keyed on the lock file and the environment.
- The Playwright browsers, keyed on the Playwright version.
- The `e2e/node_modules` directory, keyed on its lock file.

## Repository hygiene

While creating `.github`, add the rest of it.

- A pull request template that asks for the requirement identifiers
  touched and confirms `mix ci` was run.
- Issue templates for a defect and for a proposal.
- A code owners file.
- Automated dependency updates, grouped so that Elixir dependencies,
  GitHub Actions and the end to end Node dependencies arrive
  separately.
- A version manager file pinning Erlang, Elixir and Node, so the
  workflow and a developer machine agree. None exists today.

Consider requiring the change gate to pass before merging, once it has
been observed to be stable.

## Verification of plan 06

- The change gate passes on a branch that is known good, and fails on a
  branch with a deliberately broken test.
- The drift check fails when the traceability report is stale, with a
  message that says what to do.
- The end to end workflow passes and, when made to fail on purpose,
  uploads a usable trace.
- A second run of each workflow is materially faster than the first,
  which proves the caches are being hit.
- Total wall clock for the change gate stays within a few minutes.
