# Plan 01 — internationalisation and locale fixes

## Why this plan exists

Two defects were reported: the language cannot be changed on the first
page the server hands you, and parts of the interface remain English
while the locale is Thai. Both were investigated and both are now
diagnosed. Neither is caused by missing translations.

The catalogues are in good shape and are not the problem. Both
`priv/gettext/th/LC_MESSAGES/default.po` and its English counterpart
carry 372 message ids with a single empty entry each, the header. There
are no fuzzy entries anywhere. The sixteen empty entries in
`priv/gettext/en/LC_MESSAGES/errors.po` are correct: Ecto's built in
messages have English ids, so an empty translation falls back to the
id, and `test/sprint_lens_web/translations_test.exs` already whitelists
exactly that case.

## Bug A — the language switcher does nothing on the landing page

### What happens

Start the server, open the root page, click the language buttons in the
navigation bar. Nothing happens. The theme toggle sitting right next to
it appears to work, but the choice is never saved.

### Why it happens

`language_switcher/1` in
`lib/sprint_lens_web/components/layouts.ex` fires
`phx-click={JS.push("set_language", value: %{language: language})}`.
`JS.push` is a LiveView construct: it needs a live process on the other
end of the socket to receive the event.

The root page has no such process. `lib/sprint_lens_web/router.ex`
routes `get "/"` to `SprintLensWeb.PageController`, an ordinary
controller. Its template wraps itself in `Layouts.app`, so the switcher
renders, and it even shows the correct active state, because the locale
comes from the assign written by `SprintLensWeb.Plugs.Locale`. But the
click has nowhere to go, and fails silently.

The theme toggle is the control experiment. It combines
`JS.dispatch("phx:set-theme")` with `JS.push("set_theme", ...)`. The
dispatch half is handled by the inline script in
`lib/sprint_lens_web/components/layouts/root.html.heex`, which listens
on `window` and repaints immediately. The push half dies exactly like
the language switcher. Whatever is pure client side works; whatever
needs a live process does not. That asymmetry is the fingerprint.

The same failure applies to every page that is not a LiveView: the
`/dev` routes, and the rendered error pages.

### The fix

The server side already exists and is already correct.
`SprintLensWeb.LocaleController` writes the choice into the session for
a visitor with no profile to store it in, and it already refuses an off
site redirect target. `SprintLensWeb.Hooks.Preferences` redirects to it
for signed out visitors. The only missing piece is that nothing on a
server rendered page ever links to it.

Render the switcher as real navigation rather than as a pushed event:
a `<.link href={~p"/locale/#{language}?return_to=..."}>` per language,
carrying the current path so the visitor lands back where they were.

Two decisions the implementation must make explicitly.

- Whether to use the link form everywhere, or only when there is no
  live process. Prefer everywhere. It works on both kinds of page, it
  degrades without JavaScript, and it removes a whole class of bug
  rather than papering over one instance. The cost is a full page load
  when switching language inside a LiveView, which is acceptable for an
  action taken once per session.
- Whether the same treatment is owed to the theme toggle. It is. The
  theme repaints on a server rendered page but is never persisted, so a
  visitor who sets a theme before signing in loses it. Fix it in the
  same change or state plainly that it is deferred.

### Files touched by bug A

- `lib/sprint_lens_web/components/layouts.ex` — the switcher, and the
  theme toggle if it is included.
- `lib/sprint_lens_web/hooks/preferences.ex` — the redirect path can be
  simplified once the switcher navigates on its own.
- `lib/sprint_lens_web/controllers/locale_controller.ex` — unchanged in
  behaviour; confirm the `return_to` guard still covers the new callers.

## Bug B — English text appears while the locale is Thai

Four separate causes, ranked by how often a user meets them.

### Cause 1 — built-in template content is English in the database

This is the largest and the most visible, because it lands on the retro
board, the screen the product exists for.

`priv/repo/migrations/20260818135801_seed_builtin_templates.exs` seeds
the five built-in templates. Each one carries a name, three or four
column names, and a hint per column: roughly forty five user facing
strings. The migration's own documentation comment states that the
English text is translated at render time. It is not. The render sites
interpolate the stored string directly, in
`lib/sprint_lens_web/components/board_components.ex` and
`lib/sprint_lens_web/live/template_live/index.ex`, and no message id
exists for any of that text in either catalogue.
`lib/sprint_lens/retro.ex` has the same problem in its fallback column
list.

The fix is not simply to wrap the values in `gettext`. Templates are
also user data: a team can create its own, and requirement FR-909 says
user content is never translated. So the plan must separate the two.

- Built in templates already carry an `is_builtin` flag. Use it as the
  gate: translate only when the record is built in.
- Put the built in strings in their own gettext domain, so they are
  extracted and reviewed separately from interface chrome.
- Extract the strings at their source, so `mix gettext.extract` sees
  them. A migration is not scanned for translations, so the canonical
  list of built in template text has to live in a module that is.
- Custom templates render verbatim, unchanged.

Decide and record whether the stored English values remain the message
ids, which keeps the migration untouched and the English rendering
identical, or whether the seeds move to symbolic keys, which is cleaner
but needs a data migration. The first option is recommended.

### Cause 2 — the Gettext backend has no default locale

There is no `config :sprint_lens, SprintLensWeb.Gettext, ...` anywhere
in `config/`, so Gettext falls back to its own global default, English.
Meanwhile `lib/sprint_lens/cldr.ex` declares `default_locale: "th"`.

The two subsystems therefore disagree. In any process that never calls
`SprintLensWeb.Locale.put/1` you get Thai dates next to English words,
which is precisely the confusing half translated state that was
reported. The affected paths are the ones that run outside a browser
request:

- the four account emails in
  `lib/sprint_lens/accounts/user_notifier.ex`, subjects and bodies;
- the Oban workers under `lib/sprint_lens/workers/`;
- `lib/sprint_lens_web/controllers/error_json.ex`, which renders
  `SprintLensWeb.ApiError` messages after a raise has already escaped
  the pipeline.

The configuration change is one line. Note separately that
`lib/sprint_lens_web/controllers/error_html.ex` returns
`Phoenix.Controller.status_message_from_template/1`, which is English
by construction and ignores Gettext entirely, so the HTML error pages
need their own small fix.

Emails deserve a design note rather than only a configuration change. A
notification is generated for a specific recipient, so it should be
rendered in that recipient's stored language, not in whatever locale
the sending process happens to hold. Plan to set the locale explicitly
from the user record before building the message.

### Cause 3 — the JSON API pipelines never set a locale

`lib/sprint_lens_web/router.ex` adds `SprintLensWeb.Plugs.Locale` to
the `:browser` pipeline only. The `:api` and `:api_public` pipelines do
not have it. Every message in `lib/sprint_lens_web/api_error.ex` is
correctly wrapped and fully translated, and every one of them is
emitted in English.

The plug reads the session, which an API request does not have, so it
needs a source that suits a token authenticated client: the
authenticated user's stored language first, then the `accept-language`
header. `SprintLensWeb.Plugs.Locale` already tolerates a request with
no session, so the change is mostly about ordering it after
authentication in the `:api` pipeline, and adding a header only path
for `:api_public`.

### Cause 4 — the dead render and the connected render disagree

`lib/sprint_lens_web/hooks/preferences.ex` re-resolves the locale when
the socket connects, and passes `nil` where the plug passes the
browser's `accept-language` header. The comment above it claims the two
resolve from the same inputs. They do not.

The visible consequence: a signed out visitor whose browser asks for
English gets an English first paint, which then flips to Thai, the
organisation default, the moment the socket connects. On the sign in
and registration pages that is a real, reproducible flicker between two
languages.

The header is not part of the LiveView session, so the fix is to put it
there, either through the session itself or through the `session`
option on the `live_session`, and then pass it through so both paths
resolve identically.

## Two loose ends found along the way

Both were found while investigating. Decide in the implementation
whether they are in scope; recommend including the first and doing the
second as its own small change.

- `lib/sprint_lens_web/user_auth.ex` contains the only two unwrapped
  user facing strings in the whole web layer, the same sign in prompt
  written twice. Wrapping them is trivial.
- `SprintLens.Admin.OrgSettings` has a real `default_language` column.
  It is editable through the admin API and its changes are audited. No
  code ever reads it: `SprintLens.Accounts.default_language/0` returns
  the application environment value instead, and nothing ever writes
  the database value into that environment. An organisation admin can
  therefore change the default language and observe no effect, which
  leaves FR-802 only half implemented.

## Test gaps

The current suite could not have caught bug A, and it is worth writing
that down so the replacement tests are the right ones.

`test/sprint_lens_web/plugs/locale_test.exs` renders the root page and
asserts that the output is Thai. That passes, and it always would have:
it tests the plug, not the switcher. Every test that exercises the
switcher itself, in
`test/sprint_lens_web/live/user_live/preferences_test.exs`, reaches the
page through `live/2`, so a live process exists by construction and
`render_click` works. A click on a controller rendered page cannot be
expressed in `Phoenix.LiveViewTest` at all, which is why the gap was
invisible.

None of the fourteen Playwright specs touches language at all.

Plan three additions.

- A `ConnCase` test that fetches the root page and asserts the switcher
  renders a real link to `/locale/en` carrying the current path.
- A `ConnCase` test that follows that link and asserts the next render
  is English, which covers the controller end to end.
- A Playwright spec that loads the root page, clicks the English
  button, and asserts the page is English, then reloads and asserts the
  choice survived. This is the test that would have caught the original
  defect.

Add regression tests for the other four causes too: an email rendered
for a Thai user, an API error returned in Thai, and a sign in page
whose first paint and connected render agree.

## Verification of plan 01

- `mix ci` green, including the 100 percent coverage gate.
- `mix verify` green, including the new locale spec.
- Manual: start the server, open the root page signed out, switch to
  English, confirm the page changes and the choice survives a reload
  and a sign in.
- Manual: open a retro board in Thai and confirm the column headings of
  a built in template are Thai, while a team created template still
  shows exactly the text the team typed.

## Requirement traceability

This plan touches FR-906 through FR-909 and FR-802. The tests it adds
must carry those tags, and `mix sprint_lens.trace --write` must be
re-run so `docs/traceability.md` reflects the new coverage.
