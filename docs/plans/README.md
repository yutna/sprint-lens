# SprintLens improvement plans

This directory holds the implementation plans that answer
`docs/improvments.md`, the review notes written after using the running
application.

Each file plans one workstream: what is actually wrong, what the fix
looks like, which files it touches, and how it is verified. Nothing in
here has been executed yet. These are plans, not changelogs.

## The plans

1. [i18n and locale fixes](01-i18n-and-locale-fixes.md)
2. [Design system and UI overhaul](02-design-system-and-ui-overhaul.md)
3. [Responsive and accessibility](03-responsive-and-accessibility.md)
4. [README and developer workflow](04-readme-and-developer-workflow.md)
5. [Specification relocation](05-spec-relocation.md)
6. [GitHub Actions CI](06-github-actions-ci.md)
7. [Brand, logo and favicon](07-brand-logo-and-favicon.md)
8. [Documentation site](08-documentation-site.md)
9. [PostgreSQL support](09-postgresql-support.md)
10. [Deployment guides](10-deployment-guides.md)

## Coverage of the review notes

Every point raised in `docs/improvments.md` maps to exactly one plan.
Line numbers refer to that file. This list is the audit artefact: if a
line is not here, it was not planned.

- Line 3 — language cannot be changed on the first page served at
  `localhost:4000`. Owned by plan 01.
- Line 4 — parts of the interface stay English even when the locale is
  Thai. Owned by plan 01.
- Line 5 — the UX and the arrangement of the interface are confusing.
  Owned by plan 02.
- Line 6 — a full UX and UI overhaul, easy to understand, following a
  step by step flow. Owned by plan 02.
- Line 7 — the interface must be beautiful, modern and inviting. Owned
  by plan 02.
- Line 8 — responsive layout. Owned by plan 03.
- Line 9 — web accessibility. Owned by plan 03.
- Line 10 — a far more detailed `README.md` covering the commands a
  developer needs: resetting the database, running the tests, seeding
  data, in the spirit of a Rails project. Owned by plan 04.
- Line 11 — move `team-retro-spec-en.md` into `docs/specs` and correct
  everything that points at it. Owned by plan 05.
- Line 12 — plan GitHub Actions. Owned by plan 06.
- Line 13 — design a logo for the project, to be used in the app, as
  the favicon, and in `README.md`. Owned by plan 07.
- Line 14 — plan repository documentation published as a GitHub site,
  a detailed manual for both developers and users. Owned by plan 08.
- Line 15 — the open question of whether documentation comments can be
  generated into developer docs, and the separate need for a user
  manual. Answered and owned by plan 08.
- Line 16 — the user manual needs illustrations. Owned by plan 08.
- Line 17 — the deployed application must support PostgreSQL, which
  may require surveying and changing code. Owned by plan 09.
- Line 18 — deployment guides for the cloud services popular with
  Elixir developers. Owned by plan 10.
- Line 19 — whether the app can be deployed on Coolify, and if so how.
  Owned by plan 10.

Lines 20 to 24 are instructions about this planning task itself
(English only, markdownlint clean, plan before acting, audit, commit)
rather than product work, so they have no owning plan.

## Recommended order

The order below is driven by dependencies, not by importance.

1. Plan 06, GitHub Actions. It establishes the gate that every later
   change is measured against, so it comes first.
2. Plan 05, specification relocation. It edits the traceability task
   that CI runs, so it should land while CI is still small.
3. Plan 01, i18n fixes. Small, self contained, and the most visible
   defect a user hits today.
4. Plan 07, logo and favicon. Feeds both the UI overhaul and the docs
   site, so the assets should exist before either.
5. Plan 09, PostgreSQL support. Changes the CI matrix and touches the
   data layer. Better done before the interface churns.
6. Plan 02, design system and UI overhaul. The largest workstream.
7. Plan 03, responsive and accessibility. A hardening pass over what
   plan 02 produces.
8. Plan 04, README. Documents the commands as they finally are.
9. Plan 08, documentation site. Its screenshots need the new interface
   to exist first.
10. Plan 10, deployment guides. Needs the PostgreSQL story from plan 09
    to be real before it can be documented honestly.

## Constraints every plan inherits

These come from `AGENTS.md` and from the tooling already in the repo.
No plan may quietly relax them.

- `mix ci` must stay green. It runs, in order: compile with warnings as
  errors, `format --check-formatted`, `deps.unlock --check-unused`,
  `credo --strict`, create and migrate the database, `coveralls`,
  `dialyzer`, and `sprint_lens.trace --write`.
- Line coverage is gated at **100 percent** by `coveralls.json`. New
  code arrives with its tests, or it does not arrive.
- `mix verify` is the acceptance gate: `mix ci` plus the Playwright
  suite.
- Every test that covers a requirement declares it, with
  `@tag req: ["FR-301"]` in ExUnit or an `[FR-301]` prefix in a
  Playwright test title. Renaming a test title silently drops the
  requirement claim and fails `mix sprint_lens.trace`.
- Database tests are `async: false`, and `SprintLens.DataCase` and
  `SprintLensWeb.ConnCase` raise if you pass `async: true`.
- Contexts are the only source of truth. LiveViews and API controllers
  are thin adapters over them.
- Never log card text, personal data or secrets. Anything about to be
  logged goes through `SprintLens.Redact.payload/1`.
- The specification `team-retro-spec-en.md` is normative. Requirement
  identifiers are stable and are never renumbered.

## Definition of done for a workstream

A plan is complete when all of the following hold.

- `mix ci` is green.
- `mix verify` is green.
- `docs/traceability.md` shows no uncovered requirement, and any
  documented gap in `priv/traceability_exceptions.exs` still states a
  reason that is true.
- The behaviour described in the plan can be demonstrated by running
  the app, not only by reading a passing test.
