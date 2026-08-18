import { expect, test } from '@playwright/test'
import { waitForLiveView } from './support/auth'
import { columnIds, scrollsSideways, soloBrainstorm, writeCard } from './support/board'

/**
 * The board on a 375 px phone, in the dark, with a touch screen and no mouse.
 *
 * This is the M4 half of acceptance scenario 10.7: joining by code, moving
 * between columns, writing a card and moving it with the tap menu, none of it
 * requiring a drag and none of it scrolling the page sideways. Voting joins
 * the same journey once M5 exists.
 */

test.describe('the board on a phone', () => {
  test('[FR-902] one column at a time, with the active one marked', async ({ page }) => {
    await soloBrainstorm(page)
    const [first, second] = await columnIds(page)

    // Every column is in the DOM; exactly one is on screen.
    await expect(page.locator(`#column-${first}`)).toBeVisible()
    await expect(page.locator(`#column-${second}`)).toBeHidden()

    await expect(page.locator('#column-tabs')).toBeVisible()
    await expect(page.locator(`#tab-${first}`)).toHaveAttribute('aria-selected', 'true')
    await expect(page.locator(`#tab-${second}`)).toHaveAttribute('aria-selected', 'false')

    await page.locator(`#tab-${second}`).tap()

    await expect(page.locator(`#column-${second}`)).toBeVisible()
    await expect(page.locator(`#column-${first}`)).toBeHidden()
    await expect(page.locator(`#tab-${second}`)).toHaveAttribute('aria-selected', 'true')
  })

  test('[FR-903] a card is written and moved by tapping only', async ({ page }) => {
    await soloBrainstorm(page)
    const [first, second] = await columnIds(page)

    await writeCard(page, first, 'Written on a phone')

    const cardId = (await page.locator(`#cards-${first} li`).first().getAttribute('id'))!.replace(
      'card-',
      '',
    )

    // The move menu is on the card itself, so it is reachable without ever
    // holding and dragging (FR-903).
    await page.locator(`#move-card-${cardId}-to-${second}`).tap()

    await expect(page.locator(`#cards-${first} li`)).toHaveCount(0)

    await page.locator(`#tab-${second}`).tap()
    await expect(page.locator(`#cards-${second} li`)).toHaveCount(1)
    await expect(page.locator(`#column-${second}`)).toContainText('Written on a phone')
  })

  test('[FR-905] the board never scrolls sideways', async ({ page }) => {
    await soloBrainstorm(page)
    const [first] = await columnIds(page)

    expect(await scrollsSideways(page)).toBe(false)

    // A long unbroken string is the usual way a card breaks a layout.
    await writeCard(page, first, 'x'.repeat(200))
    await writeCard(page, first, 'https://example.com/a-very-long-link-with-no-spaces-in-it-at-all')

    expect(await scrollsSideways(page)).toBe(false)
  })

  test('[FR-204] @spec-10.7 a member joins by code from a phone', async ({ page }) => {
    const { joinCode, boardUrl } = await soloBrainstorm(page)

    // Typed the way it would be read off a screen in a standup: lower case,
    // no link to follow.
    await page.goto('/join')
    await waitForLiveView(page)
    await page.locator('#join_form input[name="join[code]"]').fill(joinCode.toLowerCase())
    await page.locator('#join_form button').click()

    await expect(page).toHaveURL(boardUrl)
    expect(await scrollsSideways(page)).toBe(false)
  })
})
