## What changed

<!-- One or two sentences. What is different after this, from the point of
view of someone using the application? -->

## Why

<!-- The problem this solves. If it is a defect, how to reproduce it. -->

## Requirements touched

<!-- The identifiers from docs/specs/team-retro-spec-en.md that this change
covers or affects, e.g. FR-902, NFR-102. New user-visible behaviour needs a
new identifier appended to the specification — identifiers are never
renumbered. Write "none" if this is a pure refactor. -->

## Checklist

- [ ] `mix ci` is green locally
- [ ] `mix verify` is green, or the end-to-end suite is untouched by this change
- [ ] Every new test that covers a requirement declares it: `@tag req: ["FR-301"]`
      in ExUnit, or an `[FR-301]` prefix in a Playwright title
- [ ] `docs/traceability.md` is regenerated and committed if it changed
- [ ] Nothing that could hold card text, personal data or a secret is logged
      without going through `SprintLens.Redact.payload/1`
- [ ] New user-visible strings are wrapped for translation, and user content
      is not (FR-909)
