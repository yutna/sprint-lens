# Plan 03 — responsive layout and accessibility

## Why this plan exists

The review notes list responsiveness and web accessibility as their own
items, and the specification already commits to both: requirements
FR-901 through FR-905 for layout, and FR-913 through FR-920 for
accessibility, including conformance with WCAG 2.1 level AA.

This plan runs immediately after plan 02, because it hardens what that
plan produces. Splitting them is deliberate: the design work and the
conformance work have different acceptance criteria and different
evidence.

## Where responsiveness stands today

There are twenty five responsive utility classes in the entire web
layer. Twenty three are the small breakpoint, two are the large
breakpoint, and there are none at the medium, extra large or double
extra large breakpoints. Most of them are grid column counts.

Exactly two mechanisms adapt to a phone.

- The board renders one column at a time below the small breakpoint,
  with a tab strip to switch between them. That is a real
  implementation of FR-902 and it works.
- A coarse pointer media query in `assets/css/app.css` forces a forty
  four pixel minimum height and width on the small size classes, which
  is what makes the touch target assertions in the Playwright suite
  pass.

Everything else is a desktop layout that happens to reflow.

## The responsive plan

### Breakpoint scale

Adopt an explicit scale and write it into the design tokens rather than
leaving it implicit in scattered utility classes. At minimum: a phone
range, a tablet range, a laptop range and a wide range. The Playwright
suite already exercises three hundred and sixty by six hundred and
forty and three hundred and seventy five by six hundred and sixty
seven, so the narrow end has test coverage from the start.

### Per screen behaviour

Write down, per screen, what changes at each breakpoint. This is the
deliverable that does not exist today and its absence is why the
current layout only has grid column counts.

- Shell: navigation collapses to a menu on phones; the account menu
  stays reachable in one tap; breadcrumbs truncate from the left.
- Home: single column on phones, two on tablets, three on laptops.
- Team detail: sub navigation becomes a horizontally scrollable strip
  on phones rather than wrapping into several rows.
- Session board: keep the one column plus tab strip pattern below the
  small breakpoint. Above it, the number of visible columns follows the
  template. The timer and readiness panel moves from a side column to a
  sticky bar on phones, since it is what the room watches.
- Recap, insights and admin: tables become stacked records on phones
  rather than scrolling sideways.
- Forms: full width fields on phones, two column layouts only where
  the fields are genuinely short.

### Invariants to keep

- The page must never scroll horizontally. This is FR-905 and it is
  already asserted in the Playwright suite by comparing the document
  scroll width against the client width. Wide content scrolls inside
  its own container, never the page.
- Touch targets stay at forty four pixels minimum. When the daisyUI
  size classes are removed in plan 02, the coarse pointer rule has to
  be rewritten against the new component classes or this silently
  regresses.
- Both portrait and landscape are in scope, which FR-901 states
  explicitly and which is easy to forget on a phone sized board.

## Where accessibility stands today

### What is already good

The application is better than most on the parts that are usually
worst, and this should be preserved rather than rediscovered.

- Every control that mutates something is a real button or a real
  select. There is not a single clickable division in the codebase.
  This was an explicit decision recorded against FR-914.
- ARIA is used with intent, not sprayed: labelled regions throughout,
  live regions on the phase bar, the timer, the flash group and the
  card character counter, pressed state on the mood, language and theme
  controls, and a correct tab list, tab and tab panel relationship on
  the board columns.
- Destructive actions all require confirmation.
- The colour palette was retuned by hand to meet contrast requirements
  and a test enforces it.

### What is missing

- No skip link anywhere, so a keyboard user traverses the whole
  navigation on every page.
- Only two screen reader only labels in the entire application.
- No focus visible styling of the project's own. It currently inherits
  whatever daisyUI provides, which means it disappears when daisyUI
  does.
- No reduced motion handling, apart from one spinner.
- Heading order breaks on the busiest screen: the session board goes
  from a level one heading straight to level three headings in the
  columns and panels, with no level two in between.
- No dialogs exist, so the dialog half of FR-916 cannot be satisfied;
  confirmation is delegated to the browser.
- No automated accessibility checking of any kind. Enforcement is only
  the contrast test and a layout test that asserts a few landmarks and
  live regions exist.

## An honest discrepancy in the traceability report

`docs/traceability.md` marks FR-916, focus management on dialogs and
phase transitions, as covered. Nothing in the application moves focus
on a phase transition. The six mounted focus calls are all on
authentication form fields, and the only other focus call is the
rollback path of the optimistic card hook.

The traceability gate proves that a test claims a requirement
identifier. It cannot prove that the behaviour exists. That is a
limitation worth stating plainly rather than treating the green report
as evidence.

The action: implement focus management for real, and write a test that
would fail without it. While doing so, review the other section 8
requirements for the same pattern, since one instance suggests others.

## The accessibility plan

### Structure and landmarks

Add a skip link as the first focusable element. Keep the main landmark
that already exists, since two Playwright privacy assertions address
it. Give the navigation, the team sub navigation and the board their
own labelled landmarks. Fix the heading order on the session board by
introducing the missing level two headings.

### Focus

Define a visible focus style as a token, so it survives the removal of
daisyUI. Move focus deliberately on three events: a phase transition,
which announces and focuses the new phase region; opening a dialog,
which traps focus and restores it on close; and a navigation that
replaces the main content, which focuses the new heading.

Replace the browser confirmation attribute on destructive actions with
a real dialog component, which is what makes the focus requirement
satisfiable at all.

### Announcements

Requirement FR-915 asks that phase changes, reveals and the timer are
announced. The live regions for the phase bar and the timer already
exist. Verify the reveal path has one, and verify that the announcement
text is a sentence rather than a bare number.

### Motion and preferences

Wrap every transition and animation so it is disabled under a reduced
motion preference. This includes the sliding indicator on the theme
control and any new page transitions introduced by plan 02.

### Forms and errors

Every field needs a programmatically associated label, not a
placeholder standing in for one. Errors must be associated with their
field and announced. Requirement FR-919 asks for human readable errors
with a retry path, so error text is content, not decoration, and it
must be translated.

## What the playful direction must survive

Plan 02 commits the interface to a playful, board-game direction:
tilted cards, a staged reveal, vote tokens, a mascot in the empty
states, and optional sound. None of it is exempt from this plan, and
each piece has a specific obligation.

- Every animation sits behind a reduced motion preference, and the
  reduced variant still communicates the outcome. Turning motion off
  must not mean turning feedback off: someone who asked for less motion
  still needs to know their card landed and that the reveal happened.
- The expressive palette — a colour per board column, avatar colours,
  the mood scale — is held to the same contrast floor the existing
  contrast test enforces, and never carries meaning on its own. A
  column is identified by its heading, not only by its colour.
- The mascot and any decorative illustration carry empty alternative
  text wherever adjacent text already says the same thing, so nothing
  is announced twice.
- Tilt, offset and paper shadows must not reduce a touch target below
  forty four pixels, clip text, or introduce horizontal scroll. All
  three are already asserted in the end to end suite, so a regression
  will be caught, but designing against them is cheaper than fixing
  them afterwards.
- Sound is never the only signal for anything. Every event that makes a
  noise also has a visible change, and the preference that controls it
  is reachable and understandable with sound off, which is its default.
- The staged reveal animates a list that a screen reader is also being
  told about. Announce the reveal once, as a sentence, rather than
  letting each arriving card announce itself.

## Automated checking

Add an accessibility audit to the Playwright suite: run an automated
rule set against each significant screen in both themes and at both the
narrow and desktop viewports, and fail on violations.

Two cautions to record in the plan so the result is not oversold.

- Automated rules catch a minority of real problems. They are a
  regression net, not a conformance claim.
- The audit must run in both themes, because contrast regressions are
  theme specific and the existing contrast test only checks the token
  pairs, not their use in context.

Keep the existing contrast test. It checks something the audit does
not: that the palette itself is sound before any markup uses it.

## Manual checking

Write a short checklist into the developer documentation and run it
before each release.

- Traverse every screen with the keyboard only, and confirm the focus
  indicator is always visible and the order is sensible.
- Run one full retrospective with a screen reader, confirming that
  phase changes, timer updates and card reveals are announced.
- Check both themes at the narrowest supported width in portrait and
  landscape.
- Zoom the browser to two hundred percent and confirm nothing is lost
  and nothing scrolls sideways.

## Verification of plan 03

- `mix ci` and `mix verify` green.
- The new automated accessibility audit passes with no violations.
- The horizontal scroll and touch target assertions still pass after
  daisyUI is removed.
- A test exists that fails if focus is not moved on a phase transition.
- The manual checklist has been run and its result recorded.

## Requirement traceability for plan 03

FR-901 through FR-905 for responsiveness, and FR-913 through FR-920 for
accessibility. FR-916 in particular must gain a test that genuinely
exercises the behaviour rather than only claiming the identifier.
