import { expect, test, type Page } from '@playwright/test'
import { columnIds, scrollsSideways, soloBrainstorm, writeCard } from './support/board'

/**
 * The smallest screen the spec supports: 360 by 640, both ways up
 * (FR-901, FR-904, NFR-602).
 *
 * Scenario 10.7's phone is 375px wide; this is the floor NFR-602 names, and
 * FR-901 adds "portrait and landscape", which is two viewports rather than
 * one. Each flow here runs at both.
 */

const PORTRAIT = { width: 360, height: 640 }
const LANDSCAPE = { width: 640, height: 360 }

/** The smallest side of a control, which is what a finger has to hit. */
async function smallestSide(page: Page, selector: string): Promise<number> {
  const box = await page.locator(selector).first().boundingBox()

  expect(box, `${selector} has no box`).not.toBeNull()

  return Math.min(box!.width, box!.height)
}

test.describe('the narrowest supported screen', () => {
  test('[FR-901][NFR-602] a whole retrospective works at 360px, portrait and landscape', async ({
    page,
  }) => {
    await soloBrainstorm(page)
    const [first, second] = await columnIds(page)

    for (const viewport of [PORTRAIT, LANDSCAPE]) {
      await page.setViewportSize(viewport)

      // Write and move — the board's whole vocabulary, at both orientations.
      await writeCard(page, first, `Card at ${viewport.width}`)

      const cardId = (await page.locator(`#cards-${first} li`).last().getAttribute('id'))!.replace(
        'card-',
        '',
      )

      await page.locator(`#move-card-${cardId}-to-${second}`).click()

      // Turned on its side the screen is 640px wide, which is where the
      // board stops showing one column at a time (FR-902) and shows them
      // all. Both are correct; the tabs only exist in the narrow one.
      if (viewport.width < 640) {
        await page.locator(`#tab-${second}`).click()
      }

      await expect(page.locator(`#column-${second}`)).toContainText(`Card at ${viewport.width}`)

      // FR-905 holds at both, which is the failure mode a rotation finds.
      expect(await scrollsSideways(page), `scrolled sideways at ${viewport.width}px`).toBe(false)

      if (viewport.width < 640) {
        await page.locator(`#tab-${first}`).click()
      }
    }
  })

  test('[FR-904] the board’s controls are big enough for a finger', async ({ page }) => {
    await soloBrainstorm(page)
    const [first, second] = await columnIds(page)

    await writeCard(page, first, 'Deploys are slow')

    const cardId = (await page.locator(`#cards-${first} li`).first().getAttribute('id'))!.replace(
      'card-',
      '',
    )

    // FR-904 is a SHOULD about touch targets, applied where the pointer is
    // coarse. These are the controls a retrospective is actually driven by.
    for (const selector of [
      `#tab-${first}`,
      `#add-card-${first}`,
      `#move-card-${cardId}-to-${second}`,
    ]) {
      const side = await smallestSide(page, selector)

      expect(side, `${selector} is ${side}px`).toBeGreaterThanOrEqual(44)
    }

    // The merge checkbox only exists in the group phase, so it is measured
    // where it lives.
    await page.locator('#phase-group').click()
    await expect(page.locator(`#select-card-${cardId}`)).toBeVisible()

    const checkbox = await smallestSide(page, `#select-card-${cardId}`)
    expect(checkbox, `the merge checkbox is ${checkbox}px`).toBeGreaterThanOrEqual(44)
  })

  test('[FR-905] and every other page stays inside the viewport too', async ({ page }) => {
    const { boardUrl } = await soloBrainstorm(page)
    const teamPath = new URL(page.url()).pathname.replace(/\/sessions\/\d+$/, '')

    const pages = ['/home', '/teams', '/join', '/users/preferences', boardUrl, teamPath]

    for (const viewport of [PORTRAIT, LANDSCAPE]) {
      await page.setViewportSize(viewport)

      for (const path of pages) {
        await page.goto(path)

        expect(
          await scrollsSideways(page),
          `${path} scrolled sideways at ${viewport.width}px`,
        ).toBe(false)
      }
    }
  })
})
