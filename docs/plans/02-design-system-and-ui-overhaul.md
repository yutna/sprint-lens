# Plan 02 — design system and UI overhaul

## Why this plan exists

The review notes say the arrangement of the interface is confusing, ask
for a full overhaul with an easy to follow step by step flow, and ask
for something modern and pleasant to use. This plan turns that into
concrete work.

It is worth being precise about what is actually wrong, because the
application is not badly built. It is under designed. There is no
sidebar, no breadcrumb, no account menu and no footer. Navigation is
five flat buttons in the navigation bar plus whatever buttons each page
happens to put in its own header. One page alone,
`lib/sprint_lens_web/live/team_live/show.ex`, puts six navigation
buttons in its header slot. There is no font declared anywhere in the
project, so every screen renders in the browser's default stack. The
retrospective itself, the reason the product exists, is a single very
dense page.

## Scope and blast radius

This is a rewrite of the presentation layer, not a restyle. Seventeen
LiveViews render inline templates in their own `render/1`. There are no
LiveComponents at all, and the only separate template files in the
project are the root layout and the landing page.

The surfaces in scope:

- `lib/sprint_lens_web/components/core_components.ex`, which is still
  essentially the Phoenix generator output, one comment aside;
- `lib/sprint_lens_web/components/layouts.ex`, the application shell;
- `lib/sprint_lens_web/components/board_components.ex`, the retro board;
- `lib/sprint_lens_web/components/action_components.ex`;
- `lib/sprint_lens_web/components/ai_components.ex`;
- `assets/css/app.css`;
- all seventeen LiveViews and the landing page template.

Roughly three hundred element lookups across seventeen ExUnit test
files, plus fifty four Playwright tests, depend on the markup this plan
changes. The section on the test contract below is not optional
reading.

## Decision — replace daisyUI with an owned design system

`AGENTS.md` states that components should be written by hand rather
than taken from daisyUI. The code does the opposite: the whole
interface is built from daisyUI classes, and daisyUI is a pinned git
dependency. That contradiction has to be resolved before any styling
work begins, and the decision taken is to follow `AGENTS.md` and remove
daisyUI.

### What daisyUI provides today

Removing it means replacing four things, not one.

- The class vocabulary: buttons, badges, cards, the navigation bar,
  tabs, alerts, toasts, lists, tables, selects, inputs, textareas,
  checkboxes, fieldsets, dividers and joined button groups.
- The theme mechanism. `assets/css/app.css` defines two hand tuned
  theme blocks, light and dark, in OKLCH.
- The semantic colour names those themes export, such as the base
  surfaces, their content colours, and the status colours, which the
  templates reference throughout.
- The size classes that the coarse pointer rule in the same file
  targets to guarantee forty four pixel touch targets.

### What replaces it

- A token layer: CSS custom properties for colour, spacing, radius,
  border width, shadow and type scale, defined once for light and
  redefined for dark, keyed on the same `data-theme` attribute the root
  layout already stamps.
- A component layer written as Phoenix function components in Elixir,
  styled with Tailwind utility classes. No `@apply`, as `AGENTS.md`
  requires.
- The existing Tailwind v4 import syntax in `assets/css/app.css` stays
  exactly as it is.

Two constraints on the token layer that are easy to miss.

- `test/sprint_lens_web/contrast_test.exs` reads `assets/css/app.css`
  with a regular expression, requires exactly two themes named `light`
  and `dark`, and asserts a contrast ratio of at least 4.5 to 1 for
  every content colour against its surface. The comment in the CSS
  records that the generated palette failed twelve of sixteen pairs and
  that the lightness values were retuned by hand to fix it. Either keep
  a shape that test can still parse, or move the test with the tokens
  in the same change. Do not lose the assertion.
- The coarse pointer block that forces forty four pixel minimum touch
  targets currently targets daisyUI's small size classes. When those
  classes disappear the rule silently stops applying, and the touch
  target assertions in the Playwright suite start failing. Carry the
  rule over to the new component classes deliberately.

### Migration sequence for the CSS

Doing this in one commit is not realistic. Sequence it.

1. Introduce the token layer alongside daisyUI, mapping the new tokens
   to the existing theme values so nothing changes visually.
2. Build the new foundation components and migrate one screen at a
   time, starting with the smallest, `SessionLive.Join`.
3. Migrate the board last, because it carries the most test weight.
4. Remove the daisyUI plugin from `assets/css/app.css` and the
   dependency from `mix.exs` only when no class from it remains.
5. Move or rewrite the contrast test in the same commit as step four.

## The design language

### Colour

Keep the current semantic naming, because the templates and the
contrast test both depend on the concept, and keep OKLCH, because the
existing values were already tuned for accessible contrast and are a
sound starting point. What changes is ownership: the values become the
project's own tokens rather than a plugin's theme object.

Choose a single accent that carries the brand, coordinated with plan
07 so the logo and the interface agree. Note that the light theme's
primary is currently orange while the dark theme's primary is indigo,
which means the product has no recognisable colour. Pick one hue family
and derive both themes from it.

### Typography

There is no font in the project today. This is the single change with
the largest effect on how modern the interface feels.

Choose a pair that covers Thai and Latin with matching weights and
metrics, since the interface is Thai first. `AGENTS.md` forbids
referencing an external stylesheet or script from the layouts, so the
files must be vendored into the repository and served locally. Any new
top level static file must also be added to the static path allowlist
in `lib/sprint_lens_web.ex`, or it will simply return not found.

Define a type scale as tokens and use it everywhere. Thai script needs
more line height than Latin at the same size; set that deliberately
rather than accepting the Tailwind default.

### Space, radius and elevation

The current radius tokens are close to square, at a quarter of a rem
for controls. Choose deliberately and apply consistently. Define a
spacing scale and a small elevation scale as tokens, and forbid
one off values in templates.

### Motion

`AGENTS.md` asks for subtle micro interactions and smooth transitions.
Define a small set of duration and easing tokens and use only those.
Every animation must be wrapped so that it is disabled under a reduced
motion preference; plan 03 covers the requirement, but the tokens
belong here.

## Information architecture

### What is wrong today

Navigation is flat. Every screen is reached from the same five global
buttons, and everything below the team level is reached from buttons
that individual pages add to their own headers. Nothing tells you where
you are, and nothing keeps the team you are working in visible as you
move between its retrospectives, actions, insights and history.

### The target navigation model

- A persistent shell with the product mark, the current team, an
  account menu, and the language and theme controls moved out of the
  primary navigation into that menu, where preferences belong.
- A team scope: once inside a team, its sub sections are a stable set
  of navigation targets rather than buttons that appear on one page.
- Breadcrumbs, so the position in the hierarchy is always readable.
- A `/home` reorganised around what the person has to do next rather
  than around the entities the system stores.
- Designed empty states everywhere, which requirement FR-917 already
  asks for.

## The retrospective flow as a real stepper

The step by step flow the review notes ask for already exists in the
domain. A session moves through six phases: check in, brainstorm,
group, vote, discuss and wrap up. The problem is entirely in the
presentation. The phases render as a flat row of small badges at the
top of `lib/sprint_lens_web/live/session_live/show.ex`, a file of
roughly nine hundred lines, and every panel for the active phase stacks
into one long scrolling column.

The redesign:

- a real progress indicator that shows the six phases, which one is
  active, which are done and which are ahead;
- a short statement of the goal of the current phase, so a participant
  who has never run a retrospective knows what to do now;
- a clear primary action per phase for the facilitator, with the
  secondary controls demoted;
- panels laid out for the phase they belong to rather than stacked;
- the timer and the participant readiness list kept persistently
  visible, because they are what the room is watching.

Splitting `session_live/show.ex` into per phase function components is
strongly recommended while the markup is being rewritten anyway. Keep
the LiveView itself as the single event boundary.

## Component library

### Foundation components

Replace the generator defaults with an owned set: button in its
variants and sizes, link, input, textarea, select, checkbox, radio,
switch, field wrapper with label, hint and error, card, panel, badge,
tag, avatar, tooltip, menu, dialog, tabs, table, list, breadcrumb,
pagination, toast, banner, empty state, skeleton and spinner.

The dialog and the skeleton do not exist today at all. Requirement
FR-918 asks for skeletons and spinners, and FR-916 asks for focus
management in dialogs, which is impossible to satisfy while there are
no dialogs; destructive actions currently use the browser confirmation
attribute instead.

### Domain components

Rebuild the board card, the board column, the column tab strip, the
group affordance, the topic and vote row, the mood scale, the action
row and form, the phase stepper, the timer, the presence list and the
AI suggestion slot on top of the foundation.

Keep two behaviours exactly as they are, because they are correct and
hard won: the optimistic card write with rollback, implemented as
colocated hooks in `board_components.ex`, and the per column move
buttons that give a keyboard and touch equivalent to dragging, which
requirement FR-903 requires and for which there is no drag
implementation to fall back on.

## The test contract that must not break

### Element identifiers

Both suites address the interface almost entirely through element
identifiers. They must survive the rewrite unchanged. The full list is
long; the categories are the session controls, the phase bar and its
six items, the per column and per card identifiers, the voting and
discussion identifiers, the action, recap, insight, admin and webhook
identifiers, and the flash and connection error identifiers.

The practical rule: treat every `id` attribute currently in the markup
as a public interface. If one has to change, change the tests in the
same commit and say so in the commit message.

Form identifiers and input `name` attributes are equally load bearing,
because the Playwright suite fills forms by name.

### Structural selectors

These encode the current markup rather than an identifier, so they are
the fragile ones.

- The board's columns are addressed as sections with a tab panel role,
  and one spec asserts there are exactly three of them. The shared
  Playwright board fixture uses the same selector, so changing the
  board away from a tab panel pattern breaks every board test at once.
- The active phase is found by its current attribute, and the specs
  take the first such element in the document. The active phase marker
  must stay first in document order.
- The main landmark must continue to exist: two specs assert that
  certain private text does not appear anywhere inside it.
- The recap page must contain zero forms. A spec asserts the count.
- One spec asserts a specific error text class on a validation message.

### Test titles are part of CI

`mix sprint_lens.trace` extracts requirement identifiers from test
titles and tags. Renaming a Playwright test drops its requirement
claim, and `mix ci` then fails on an uncovered requirement. When tests
are reorganised, carry the bracketed identifiers across.

## A landmine to fix while here

`lib/sprint_lens_web/live/session_live/show.ex` builds a grid class by
string interpolation, choosing the column count from the number of
board columns. Tailwind v4 cannot see interpolated class names. It only
works today because the same classes happen to appear literally
elsewhere in the codebase. The moment those literal occurrences are
removed during this overhaul, the board grid silently collapses to one
column with no error anywhere.

Replace the interpolation with a static lookup from column count to a
literal class string, as part of this plan rather than after it.

## Sequencing the work

1. Tokens and typography, mapped to current values, no visual change.
2. Foundation components, with their own tests.
3. Application shell, navigation and breadcrumbs.
4. Authentication screens, the smallest and safest migration.
5. Home, teams and team detail.
6. Sessions, actions, insights, search, templates and admin.
7. The retrospective board and the phase stepper.
8. The recap screen.
9. Remove daisyUI, move the contrast test, delete dead CSS.

Each step ends with `mix ci` green. The board step also has to end with
`mix verify` green before moving on.

## Verification of plan 02

- `mix ci` and `mix verify` green at every step, not only at the end.
- The contrast test still asserts the same minimum ratios against the
  new tokens.
- The Playwright narrow and mobile projects still pass, including the
  touch target and horizontal scroll assertions.
- A walkthrough of a complete retrospective, from creating a team to
  reading the recap, done by someone who has not seen the app, without
  guidance.

## Requirement traceability for plan 02

Section 8 of the specification is the governing set, in particular
FR-901 through FR-905 for layout, FR-917 for empty states, FR-918 for
loading states, FR-919 for human readable errors and FR-920 for
optimistic rendering with rollback. No requirement identifier may lose
its test during the rewrite.
