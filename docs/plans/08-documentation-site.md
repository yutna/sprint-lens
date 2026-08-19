# Plan 08 — documentation site

## Why this plan exists

The review notes ask for repository documentation published as a GitHub
site: a detailed manual for both developers and users, with
illustrations in the user manual. They also ask an open question, which
this plan answers first because it decides the tool.

## Answering the question about generated documentation

The question was whether documentation comments in the code can be
generated into developer documentation directly.

Yes. Elixir has this built in. Module and function documentation
attributes are compiled into the build artefacts, and ExDoc turns them
into a browsable reference with source links, type specifications and
grouping. Nothing has to be written twice.

This codebase is an unusually good fit. Its modules are documented
thoroughly and, more valuably, they explain reasoning rather than
restating signatures: why board mutations have a single write path, why
search uses a pattern match instead of full text search because Thai
has no word boundaries, why database tests are synchronous. That is
material a generated reference will surface immediately.

ExDoc also renders hand written markdown files as extra pages in the
same site, under their own groups. So one tool produces both the
generated developer reference and the hand written manuals, which is
why it is the choice here. It is not currently a dependency and has to
be added.

The user manual still has to be written by hand. Generated
documentation describes the code, and a user does not read code.

## The tool

Add ExDoc as a development only dependency and configure it in
`mix.exs`.

```elixir
docs: [
  main: "readme",
  logo: "priv/static/images/logo-mark.svg",
  extras: [...],
  groups_for_extras: [...],
  groups_for_modules: [...],
  source_url: "https://github.com/yutna/sprint-lens"
]
```

The module groups should mirror the architecture rather than the
directory layout: accounts and authorisation, retrospective domain,
insights and search, administration and retention, integrations meaning
webhooks and exports, the AI module, the web layer, and infrastructure.
A reader who does not know the codebase learns its shape from that
grouping alone.

## Site structure

### The user guide

Written for someone who has been invited to a retrospective and has
never used the product. It is the part that does not exist in any form
today.

The manual is written in the voice defined by plan 02, so the tone of
the documentation and the tone of the product agree. The same two rules
apply: nothing that mocks or minimises, and plain language wherever
something has gone wrong.

Pages, in the order a person meets them:

- What a retrospective is and what this tool does with it.
- Signing in, which is by emailed link rather than a password.
- Joining a session with a code.
- The six phases, one section each: what the phase is for, what a
  participant does, what the facilitator does. This is the heart of the
  manual and it is what makes the step by step flow legible.
- Cards, grouping and revealing.
- Voting and choosing what to discuss.
- Agreeing actions, and how actions carry over into the next session.
- Reading the recap and exporting it.
- Insights: what the trends mean and what they do not mean.
- Preferences: language, theme, display name, and sound, which ships
  switched off and is explained here rather than discovered.
- For facilitators: running the session, the timer, handing over.
- For organisation administrators: settings, people, retention and
  erasure.

### The developer guide

Hand written pages that the generated reference cannot produce.

- Architecture and the context boundaries.
- The permission model, and why every surface authorises through one
  module.
- The board write path and the event broadcast that follows it.
- Realtime: the per session process, presence, and what happens when a
  facilitator disconnects.
- The requirement traceability system and how to add a covered test.
- Testing: the three case templates, why database tests are
  synchronous, the factories, the coverage gate.
- The end to end suite: how it boots, its device projects, how it reads
  sign in links.
- Internationalisation: how a locale is resolved, how to add a string,
  what must never be translated.
- The AI module and its adapter boundary.
- Configuration and environments.
- Deployment, which links to plan 10 rather than duplicating it.

### The API reference

Generated from the code, no separate authoring.

Two pieces of hand written material belong beside it: a page on the
public JSON API under version one, covering authentication with a
bearer token, the resource routes, error shapes and rate limits, since
that is a contract for external callers rather than internal code; and
a page on the webhook payloads.

### The specification and traceability

Include both as extra pages, from their real locations, so the
published site always matches the repository. The specification moves
in plan 05, so these two plans have to agree on the path. The
traceability report is generated and must be included as generated
output rather than copied.

## Screenshots for the user guide

The manual needs illustrations, and the honest problem with screenshots
is that they rot. Plan for that from the start.

The Playwright suite already runs five device projects, drives the
whole application, and takes screenshots on failure. Extend it with a
documentation project whose only job is to walk the product and capture
images at chosen moments, into a fixed directory the site references.

That gives three properties worth having: the images always match the
real interface, they can be regenerated with one command after plan 02
changes everything, and they are captured at consistent viewport sizes.

Details to settle.

- Capture in Thai and in English, since the manual is bilingual, and in
  the light theme only unless a page is specifically about themes.
- Capture at a desktop width and a phone width for the pages where the
  narrow layout differs meaningfully, which is mostly the board.
- The data must be stable, so the documentation run seeds its own
  fixture rather than reusing whatever the other specs left behind.
- Never capture anything that looks like real personal data. Use
  obviously fictional names.
- Every image needs alternative text written by a person. A screenshot
  with no description is not documentation.
- Decide whether the images are committed or built. Recommendation:
  commit them, so the site can be built without a browser, and refresh
  them deliberately.

This is why plan 08 runs after plan 02. Capturing the interface that is
about to be replaced would waste the work.

## Publishing

A workflow builds the documentation and deploys it to GitHub Pages on
pushes to the default branch. The output needs an empty file that
disables the default site processor, or paths beginning with an
underscore are dropped.

Enable Pages with the Actions source rather than a branch, so nothing
generated is ever committed.

## Bilingual content

The interface is Thai first, so a Thai user manual is not optional. The
developer guide and the generated reference can be English only, which
matches the code and the specification.

The practical arrangement: extras in both languages, grouped so the
reader picks a language and stays in it, with an obvious switch between
the two. Write the Thai manual as an original rather than translating
sentence by sentence; a translated manual reads like a translated
manual.

State plainly in the plan that keeping two manuals in step is ongoing
work, and that if only one can be maintained it should be the Thai one,
because that is what the users read.

## Documentation quality gates

- The documentation build runs in the change gate and fails on a
  warning, so a broken link or a missing extra is caught at the source.
- A link checker runs over the built site. Note that the specification
  currently contains a link to a Thai version that does not exist; plan
  05 resolves it, and this gate is what stops the next one appearing.
- Markdown in `docs/` is linted with the same default rules these plans
  are held to.

On the filename `docs/improvments.md`: it is misspelled. Leave it. It
is the author's own note file, it is referenced by the coverage list in
the plans index, and renaming it gains nothing. Do not publish it to
the documentation site.

## Verification of plan 08

- The site builds with no warnings and publishes on a push to the
  default branch.
- Every module has a description in the generated reference, and none
  is empty.
- The screenshot run can be executed from a clean checkout and produces
  images identical in framing to the committed ones.
- Someone who has never used the product can run a retrospective
  following only the user manual.
- The link checker passes.
