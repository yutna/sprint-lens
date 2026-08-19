# Plan 09 — PostgreSQL support

## Why this plan exists

The review notes ask that the deployed application support PostgreSQL,
and note that this may require surveying and changing code. It does. A
survey has been done and this plan records what it found.

The application is built on SQLite, and not incidentally: the choice is
reasoned about in comments throughout the codebase, it shapes the test
strategy, and it is cited as the justification for at least one
concurrency decision. Moving to PostgreSQL is therefore not a
configuration change. Several things break loudly, one thing crashes,
one thing changes behaviour silently, and one thing stops being correct
without anything failing at all.

## The chosen shape — dual adapter

SQLite remains the development and test database. PostgreSQL becomes
the supported production database. The application must run correctly
on either.

Why this shape: a developer keeps a zero setup environment, and the
test suite keeps the properties it was built around. The cost is that
two dialects have to be kept working and the change gate has to run
twice.

Two rules follow from the choice and should be written into
`AGENTS.md`.

- No adapter specific SQL in a context without a documented branch. If
  a query needs different SQL per adapter, the branch is explicit and
  commented, and both branches are tested.
- The production adapter is the one that decides correctness. Where
  SQLite's behaviour is more forgiving, the code must be written for
  PostgreSQL and merely happen to work on SQLite.

## Hard blockers in the migrations

Each of these raises on PostgreSQL. They are listed with the file that
contains them.

- The users and authentication migration declares the email column with
  a case insensitive collation that exists only in SQLite. PostgreSQL
  has no collation by that name. Replace it with either the case
  insensitive text extension or, preferably, a unique index on the
  lower cased column, which needs no extension and is portable. Note
  that the schema and every lookup by email must agree with whichever
  is chosen.
- The teams and templates migration creates a partial unique index
  whose condition compares the built in flag against the integer one.
  On SQLite the column is an integer. On PostgreSQL it is a real
  boolean and the comparison is a type error. The condition should name
  the column alone.
- The built in template seed migration inserts rows directly with the
  built in flag set to the integer one. PostgreSQL will not coerce it.
- The administration migration breaks twice: it inserts boolean columns
  as integers, and it builds its timestamps by converting to a naive
  value before inserting them into columns declared with a time zone.
- The authentication migration declares a token column as binary with a
  size modifier. PostgreSQL maps binary to a variable length type where
  the modifier has no meaning. Verify against the adapter rather than
  assuming it is harmless.

The background job migration delegates to the library's own migration,
which dispatches on the adapter, so it should work. But the resulting
schema differs between the two engines, so an existing SQLite job table
cannot be carried across. A PostgreSQL deployment starts with a fresh
job table.

## Runtime code that breaks or changes

### A crash — averages come back as decimals

The insights context rounds a mood average with a float rounding
function, and a comment explains that SQLite's average returns a float
and never a nil. PostgreSQL returns a decimal for an average over an
integer column. The rounding call has no clause for it and raises.

This is the single most likely first failure on a naive port, and it is
in a screen a user reaches, not in a background job.

Fix it by normalising at the boundary: convert whatever the database
returns into a float once, in one place, and keep the rest of the
calculation unchanged.

### A silent change — case sensitive matching

Search is implemented with a pattern match fragment against card text,
discussion notes, action titles and descriptions. SQLite's pattern
match is case insensitive for ASCII. PostgreSQL's is case sensitive.

Nothing raises. English searches simply stop finding results that
differ in case, and the failure looks like missing data rather than a
bug. This is the most dangerous item in this plan precisely because it
is quiet.

Fix it with the case insensitive operator on PostgreSQL, behind an
explicit adapter branch, and add a test that searches with the wrong
case and expects a hit. Preserve the reasoning in the existing module
comment while doing so: the pattern match was chosen over full text
search because Thai has no word boundaries, and that reasoning is
independent of the adapter.

### A correctness regression — the vote budget

The board module checks the remaining vote budget and then writes,
inside a transaction, and a comment states that this is as strong as a
constraint because SQLite takes one writer at a time.

On PostgreSQL that reasoning does not hold. Two transactions can both
read the same remaining budget and both write, and a participant
exceeds their budget. Nothing fails; the data is simply wrong.

Fix it properly rather than by tightening the isolation level alone:
lock the row being counted against, or express the budget as a
constraint the database enforces. Add a test that runs two concurrent
votes and asserts only one succeeds. That test cannot run under SQLite,
so it is tagged for the PostgreSQL matrix entry only.

### Foreign key errors become reportable

Two places work around SQLite reporting a violated foreign key without
naming the constraint: the retrospective column schema omits the
constraint declaration, and the teams context does an existence check
before writing instead of relying on the constraint.

On PostgreSQL, named constraints are reportable and both could become
proper changeset errors. This is an improvement, not a blocker, and it
should be recorded as optional follow up rather than done in the same
change.

## The background job engine is pinned in three places

Not one, which is the trap.

- The shared configuration selects the lightweight engine and a process
  group notifier, because SQLite has no notification channel.
- The database case template hardcodes the same engine and notifier.
- The connection case template hardcodes them again.

PostgreSQL needs the standard engine, and can use the database's own
notifier. If the two test templates are not made adapter aware, they
will silently exercise the wrong engine while the application uses the
right one, and the tests will prove nothing.

Derive the engine from the configured adapter in one place and have all
three read it.

## Configuration work

- `config/runtime.exs` currently requires a database file path and
  raises without it. There is no handling of a database URL anywhere in
  the repository. Add it, and make the file path branch apply only when
  the adapter is SQLite.
- Add the PostgreSQL driver as a dependency and select the adapter from
  configuration rather than declaring it in the repository module.
- The shared configuration sets seven SQLite only pragma options for
  every environment. Those must become conditional, or PostgreSQL will
  reject them.
- Add the options a production PostgreSQL connection needs and SQLite
  never did: TLS settings, and socket options for hosts that resolve to
  IPv6.
- Provide a local PostgreSQL for developers who want to reproduce
  production, as a compose file, and document it in the README.

## Tests that assume SQLite

- The application test asserts the write ahead journal mode and the
  foreign key pragma. It is tagged against a durability requirement and
  it hard fails under PostgreSQL. Split it so each adapter asserts its
  own durability configuration.
- One AI test reaches into the job arguments with a SQLite JSON
  function. PostgreSQL needs its own JSON operator. Either branch it or,
  better, assert through the library's own testing helpers instead of
  raw SQL.
- The case templates raise on asynchronous database tests, and the
  Playwright configuration runs with a single worker, both because of
  SQLite's single writer. Under PostgreSQL neither restriction is
  needed. Do not relax them in this plan. Making the suite concurrent
  is a large change with its own risk, and it would mean the two matrix
  entries no longer run the same tests. Record it as possible future
  work and leave a comment saying why the restriction remains.

## Traceability consequences

`priv/traceability_exceptions.exs` excuses a recovery requirement on
the grounds that the application is a single SQLite file with no exotic
state. Under PostgreSQL that reason is false.

The trace task checks that an exception exists, not that its reason is
still true, so nothing will flag this. Rewrite the reason, or replace
the exception with a real test, as part of this plan.

Review the other six documented gaps for the same problem while there.
At least the transport security and the backup ageing entries are in
the same territory and are touched by plan 10.

## The migration path for an existing deployment

Write it down even though there may be no such deployment yet, because
the question will be asked.

There is no schema dump in the repository; the schema is defined only
by migrations, which makes a fresh PostgreSQL database easy to create.
Moving existing data is a separate exercise: create the schema by
migrating, then copy rows table by table with the boolean and timestamp
conversions applied, then reset the sequences. The job table is not
copied.

## Sequencing the work

1. Add the driver and make the adapter configurable, with SQLite still
   the default everywhere. Nothing changes yet.
2. Make the configuration adapter aware: pragmas, job engine, database
   URL.
3. Fix the migrations so a fresh PostgreSQL database can be created.
4. Fix the crash and the case sensitivity, with tests.
5. Fix the vote budget, with a concurrency test that runs only on
   PostgreSQL.
6. Split the adapter specific tests.
7. Add the second entry to the change gate matrix.
8. Update the traceability exception, `AGENTS.md` and the README.

## Verification of plan 09

- `mix ci` green on both adapters.
- A fresh PostgreSQL database can be created from migrations alone,
  with no manual intervention.
- Search finds a card whose text differs in case from the query, on
  both adapters.
- The insights screen renders on PostgreSQL, which proves the average
  crash is gone.
- The concurrent vote test fails against the current code and passes
  after the fix.
- The end to end suite passes against PostgreSQL at least once,
  manually if not in the gate.
