# Plan 07 — brand, logo and favicon

## Why this plan exists

The review notes ask for a logo for the project, to be used inside the
application, as the favicon, and in the README.

## What exists today

Both assets are untouched generator output.

- `priv/static/images/logo.svg` is the Phoenix framework bird, in the
  framework's orange. It is the only image referenced anywhere in the
  application, in the brand link of the navigation bar.
- `priv/static/favicon.ico` is not an icon file at all. Despite the
  extension it is a sixty four pixel PNG, which is what the generator
  ships.

The root layout has no icon or social metadata whatsoever. There is no
icon link, no touch icon, no web manifest, no open graph or card
metadata, no description and no theme colour. The favicon works only
because browsers request `/favicon.ico` implicitly and the static plug
happens to serve it.

So the product currently ships with another project's logo and no
social presence at all.

## Naming and concept

SprintLens: a lens held over a sprint. The product's actual argument,
stated in its own landing page copy, is that retrospectives should
produce actions that get done and then be measured session after
session. So the mark should carry looking closely and carrying forward,
not merely a magnifying glass.

Concepts worth exploring, to be narrowed to one:

- A lens or aperture formed from the columns of a retrospective board.
- A lens whose focal point is a single dot, the one thing the team
  agreed to change.
- A progression of marks resolving into focus, echoing the six phase
  flow.

Constraints that should drive the choice rather than be discovered
late.

- It must read at sixteen pixels. That rules out anything with fine
  detail or more than about three shapes.
- It must work in one colour, because a favicon at small sizes and a
  monochrome context both happen.
- It must work on both the light and the dark theme. Either the mark is
  theme neutral, or two variants ship and the layout picks one.
- It must sit beside Thai and Latin wordmarks without fighting either.
- Its colour must be the same accent chosen for the interface in plan
  02. Today the light theme is orange and the dark theme is indigo,
  which means the product has no colour at all. This plan and plan 02
  must agree on one hue.

The mark is authored by hand as SVG in the repository. No external
tooling and no generated binary asset that cannot be regenerated from
source.

## Deliverables

- A source SVG of the mark alone, on a square canvas, with a documented
  minimum clear space.
- A source SVG of the mark plus wordmark, for the navigation bar and
  the README.
- A monochrome variant.
- A favicon SVG, which modern browsers prefer, plus a genuine multi
  resolution ICO for older ones, at sixteen, thirty two and forty eight
  pixels.
- A touch icon PNG at one hundred and eighty pixels.
- Maskable icons at one hundred and ninety two and five hundred and
  twelve pixels for the web manifest.
- A social preview image at twelve hundred by six hundred and thirty.
- A web manifest naming the application, its colours and its icons.

## Where the mark is used

### In the application

Replace the image in the navigation bar brand link in
`lib/sprint_lens_web/components/layouts.ex`. Keep the empty alternative
text: the wordmark sits next to it as real text, so the image is
decorative and giving it a description would make a screen reader say
the name twice.

If two theme variants ship, select between them with CSS rather than in
the template, so the choice follows the theme attribute the root layout
already stamps and does not need a server round trip.

### In the browser tab and on a home screen

Add to the head of `lib/sprint_lens_web/components/layouts/root.html.heex`
the icon links, the touch icon, the manifest link, the theme colour and
a description. The theme colour needs both a light and a dark variant
keyed on the colour scheme preference, or the browser chrome will
clash with one of the two themes.

### In social previews

Add open graph and card metadata: title, description, image, type and
URL. The title should follow the same suffix pattern the live title
already uses so a shared link reads sensibly.

The canonical URL and image URL must be absolute, which means they need
the configured host rather than a relative path.

### In the documentation

The README header, the documentation site logo, and the site favicon.
Plan 08 consumes these assets, which is why this plan runs before it.

## The static path allowlist trap

The static plug is configured with an explicit allowlist of top level
paths, declared in `lib/sprint_lens_web.ex`. It currently permits the
assets directory, a fonts directory, the images directory, the favicon
and the robots file.

Every new top level file added by this plan, the manifest, the touch
icon and the social image, must be added to that allowlist or it will
return not found in production with no other symptom. This is the
single most likely way for this plan to appear finished and be broken.

Prefer putting everything possible under the images directory, which is
already allowed, and add only what genuinely has to sit at the root
because a browser looks for it there.

## Verification of plan 07

- The favicon renders correctly in a browser tab in both themes, and
  the file is genuinely the format its extension claims.
- Adding the site to a phone home screen produces the right icon and
  name.
- A link to the deployed site produces a correct preview card, verified
  with a validator rather than by eye.
- The mark is legible at sixteen pixels, checked at actual size and not
  zoomed.
- Every new static file is reachable in a production build, which means
  the allowlist was updated.
- No trace of the framework bird remains anywhere in the repository.
