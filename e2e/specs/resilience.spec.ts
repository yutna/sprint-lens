import { expect, test } from '@playwright/test'
import { brainstormWithTwoPeople, columnIds, writeCard } from './support/board'
import { registerAndSignIn, waitForLiveView } from './support/auth'

/**
 * What the board does when things go wrong or slowly (FR-918, FR-920,
 * NFR-101).
 *
 * These are the states a person meets on a bad day: the network drops, the
 * server refuses a card, the page is opened for the first time. All three are
 * visible only in a real browser — a LiveView test has no network to lose and
 * no paint to time.
 */

test.describe('when the day goes badly', () => {
  test('[FR-918] losing the network shows a banner that stays until it is back', async ({
    page,
    context,
  }) => {
    const { participant } = await brainstormWithTwoPeople(page, context)

    await expect(page.locator('#client-error')).toBeHidden()

    // Dropping the socket rather than the whole context: it is what a lost
    // connection does to the client, and it is the event the banner listens
    // for.
    await page.evaluate(() => window.liveSocket.disconnect())

    // Persistent, not a toast that fades: the connection is still down and
    // saying so once would be worse than not saying it (FR-918).
    await expect(page.locator('#client-error')).toBeVisible({ timeout: 15_000 })
    await expect(page.locator('#client-error')).toContainText(/reconnect|เชื่อมต่อ/i)

    // And it does not push the page sideways at any width (FR-905).
    const scrolls = await page.evaluate(() => {
      const root = document.documentElement
      return root.scrollWidth - root.clientWidth > 1
    })
    expect(scrolls).toBe(false)

    await page.evaluate(() => window.liveSocket.connect())

    await expect(page.locator('#client-error')).toBeHidden({ timeout: 15_000 })

    await participant.close()
  })

  test('[FR-920] a card the server refuses comes back to its box', async ({ page, context }) => {
    const { participant } = await brainstormWithTwoPeople(page, context)
    const [first] = await columnIds(page)

    // Longer than the server will take. Set past `maxlength` on purpose:
    // the browser stops an honest typist, and this is the path where the
    // server is the one saying no (FR-306, FR-920).
    const tooLong = 'x'.repeat(501)

    await page.locator(`#card-text-${first}`).evaluate((box, text) => {
      ;(box as HTMLTextAreaElement).value = text
      box.dispatchEvent(new Event('input', { bubbles: true }))
    }, tooLong)

    await page.locator(`#add-card-${first}`).click()

    // The notice arrives, and so do the words — back in the box they left.
    await expect(page.locator('#flash-error')).toBeVisible()
    await expect(page.locator(`#card-text-${first}`)).toHaveValue(tooLong)
    await expect(page.locator(`#cards-${first} li`)).toHaveCount(0)

    await participant.close()
  })

  test('[NFR-101] the board is on screen quickly on a fresh visit', async ({ page, context }) => {
    const { participant, boardUrl } = await brainstormWithTwoPeople(page, context)

    // A cold navigation, measured with the browser's own timing. The bound is
    // generous because this is localhost rather than NFR-101's mid-range
    // phone on 4G — what it catches is a regression that makes the first
    // paint wait on something it should not.
    await page.goto('about:blank')
    await page.goto(boardUrl)
    await waitForLiveView(page)

    const paint = await page.evaluate(() => {
      const entry = performance.getEntriesByType('paint').find((e) => e.name === 'first-contentful-paint')
      return entry ? entry.startTime : performance.now()
    })

    expect(paint).toBeLessThan(3000)
    await expect(page.locator('#board')).toBeVisible()

    await participant.close()
  })

  test('[NFR-104] typing echoes locally, without waiting for the server', async ({
    page,
    context,
  }) => {
    const { participant } = await brainstormWithTwoPeople(page, context)
    const [first] = await columnIds(page)

    // The counter is a colocated hook reading the box it is next to, so the
    // feedback never crosses the network (NFR-104).
    const started = Date.now()
    await page.locator(`#card-text-${first}`).fill('x'.repeat(40))
    await expect(page.locator(`#card-counter-${first}`)).toHaveText('40/500')

    expect(Date.now() - started).toBeLessThan(1000)

    await participant.close()
  })
})
