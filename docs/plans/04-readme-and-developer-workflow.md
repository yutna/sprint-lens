# Plan 04 — README and developer workflow

## Why this plan exists

`README.md` is eighteen lines of unmodified `mix phx.new` boilerplate.
It mentions nothing about this project: not the database, not the
specification, not the quality gates, not the end to end suite, not the
Thai first interface, not the AI module. The review notes ask for
something closer to what a Rails project gives a new developer: how to
reset the database, how to run the tests, how to seed data.

Nothing in the current file is worth preserving.

## What the README must contain

### Header and identity

The logo produced by plan 07, a one sentence description, the badges
for the workflows produced by plan 06, and a link to the documentation
site produced by plan 08. A screenshot of the board, because a
retrospective tool is easier to understand from a picture than from a
paragraph.

### Getting started

Prerequisites with the versions actually used: Elixir, Erlang and Node,
the last of which is needed only for the end to end suite. There is no
version manager file in the repository today, so plan 06 should add one
and this section should point at it.

```bash
mix setup
mix phx.server
```

State what `mix setup` does, since it is an alias and not obvious: it
fetches dependencies, creates and migrates the database, runs the
seeds, installs the asset tooling and builds the assets.

Then the first run: the application listens on port four thousand, the
interface is Thai by default, and there is no account yet. Explain how
to create one, and that sign in uses a link delivered by email which in
development is captured at the local mailbox route rather than sent.

### Everyday commands

```bash
mix phx.server           # start the server
iex -S mix phx.server    # start it with a shell attached
mix format               # format the code
mix precommit            # compile, unlock, format, test
```

### The database

The development database is a SQLite file in the project root.

```bash
mix ecto.create
mix ecto.migrate
mix ecto.rollback
mix ecto.reset           # drop, create, migrate, seed
mix ecto.gen.migration add_something
```

Explain the point that surprises people: `priv/repo/seeds.exs` is
deliberately empty. The built in retrospective templates and the
singleton organisation settings row are seeded from migrations instead,
because seeds do not run on a fresh deployment and do not run for the
throwaway database the end to end suite builds. Anyone adding data that
must exist everywhere should follow that pattern rather than adding to
the seeds file.

After plan 09 lands, this section also documents how to run against
PostgreSQL locally.

### Tests

```bash
mix test
mix test test/sprint_lens/retro_test.exs
mix test test/sprint_lens/retro_test.exs:42
mix test --failed
mix coveralls.html
```

Explain the rules that will otherwise cost a new contributor an
afternoon.

- Database tests are synchronous, and the case templates raise if you
  try to make them asynchronous. SQLite takes one writer at a time and
  the sandbox opens deferred transactions, so parallel database tests
  fail with a busy error instead of waiting. The measurement recorded
  in the code is ninety five failures out of a hundred.
- Tests that need no database use the unit case template, which is
  asynchronous. That is where the suite's parallelism comes from.
- Coverage is gated at one hundred percent. Write the test with the
  code. If a branch cannot be reached from a test, that is a signal to
  restructure the code, and there is a worked example of doing so in
  the health module.
- Factories build the minimum valid record. State anything the test
  cares about in the overrides.

### Quality gates

```bash
mix ci        # the per change gate
mix verify    # the acceptance gate: ci plus the end to end suite
mix trace     # the requirement traceability report alone
mix e2e       # the Playwright suite alone
```

Spell out what `mix ci` runs and why each step is there, and note that
it rewrites `docs/traceability.md`, so a dirty working tree after a CI
run is expected rather than alarming.

Explain the traceability contract, because it is unusual and it is
enforced: the specification declares requirement identifiers, every
test that covers one declares it with a tag or a bracketed title
prefix, and requirements that genuinely cannot be tested are listed
with a written reason in `priv/traceability_exceptions.exs`.

### Assets

```bash
mix assets.build
mix assets.deploy
```

Note that there is no `package.json` and no `node_modules` for the
application itself. Tailwind and esbuild are downloaded binaries driven
by mix, and the icon set arrives as a sparse git dependency. Node is
needed only under `e2e/`.

### Environments

There are four, one more than a stock Phoenix project.

- Development: SQLite file in the project root, development routes and
  the mailbox preview enabled.
- Test: its own database file, the sandbox pool, rate limiting off,
  background jobs in manual mode, the fake AI adapter, and the server
  not started.
- End to end: its own database file, no sandbox, a real server on its
  own port, background jobs actually running, development routes on so
  the suite can read sign in links out of the mailbox.
- Production: configuration read from the environment at boot.

### Project layout

A short map: the business contexts under `lib/sprint_lens`, the web
layer under `lib/sprint_lens_web`, the two custom mix tasks, the end to
end suite, and where the specification lives after plan 05 moves it.

Include the architecture rules that a contributor must follow, in a few
lines rather than by reference: contexts are the only source of truth,
the policy module is the single implementation of the permission
tables, the board module is the single write path for board mutations,
and nothing that could contain card text or personal data is ever
logged without going through the redaction helper.

### Where to go next

Links to the documentation site, the specification, the traceability
report, the plans in this directory, and `AGENTS.md`.

## Seed and demo data

The review notes ask how to seed data. Today the honest answer is that
there is nothing to seed beyond what the migrations already insert, and
no way to get a populated application for a demonstration or for
manual interface work.

Plan a new mix task that creates a realistic organisation: several
users, a couple of teams, a few finished retrospectives with cards,
votes, discussion notes and actions in various states, and one session
in progress. It should be safe to run repeatedly and refuse to run
outside development.

Two constraints. It is code under `lib/`, so it needs tests and it
counts towards the coverage gate. And it must build its data through
the contexts rather than by inserting rows directly, so that the demo
data obeys the same rules as real data.

## Things the README must state that are not obvious

Collected here so they are not lost in the outline above.

- The interface is Thai first. English is available, and the test
  helpers can pin a module to English with a module tag.
- Sign in is by emailed link. In development the mail is captured
  locally, not sent.
- The AI module is optional and is behind an adapter. Development uses
  a real adapter, tests and the end to end suite use a fake one.
- The specification is normative and its requirement identifiers are
  never renumbered.

## Verification of plan 04

- A developer who has never seen the repository can go from a clone to
  a running application with data in it, following only the README, and
  can then run `mix ci` successfully.
- Every command printed in the README has been executed and works.
- The demo task runs twice in a row without error and the resulting
  application is usable for a walkthrough.
