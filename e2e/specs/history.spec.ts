import { expect, test, type Page } from '@playwright/test'
import { brainstormWithTwoPeople, columnIds, writeCard } from './support/board'
import { waitForLiveView } from './support/auth'

/**
 * The archive, the recap, the dashboard and search (FR-601 to FR-605).
 *
 * Nothing in section 10 covers looking back at a finished retrospective, but
 * the promise that matters most here is one the acceptance scenarios do make
 * repeatedly: a session run anonymously never says who wrote what — and a
 * recap read a week later is the easiest place for that to be quietly
 * forgotten.
 */

/** The team detail page, reached the way a person would reach it. */
async function goToTeam(page: Page) {
  await page.goto('/teams')
  await waitForLiveView(page)
  await page.locator('#teams li a').first().click()
  await waitForLiveView(page)
}

/** Plays a retrospective through to a note, then closes it. */
async function playAndClose(page: Page, card: string, note: string) {
  const [first] = await columnIds(page)
  await writeCard(page, first, card)

  await page.locator('#phase-vote').click()
  await expect(page.locator('#topics-panel')).toBeVisible()

  const cardId = (await page.locator('#topics > li').first().getAttribute('id'))!.replace(
    'topic-card-',
    '',
  )

  await page.locator(`#vote-up-card-${cardId}`).click()
  await page.locator('#reveal-votes').click()

  await page.locator('#phase-discuss').click()
  await page.locator(`#note-card-${cardId}`).click()
  await page.locator(`#note-body-card-${cardId}`).fill(note)
  await page.locator(`#save-note-card-${cardId}`).click()
  await expect(page.locator(`#topic-note-card-${cardId}`)).toContainText(note)

  page.once('dialog', (dialog) => dialog.accept())
  await page.locator('#close-session').click()
  await expect(page.locator('#close-session')).toHaveCount(0)

  return { cardId }
}

test.describe('looking back at a finished retrospective', () => {
  test('[FR-601][FR-602] the archive leads to a read-only recap', async ({ page, context }) => {
    const { participant } = await brainstormWithTwoPeople(page, context)

    // Both people write something, so the archive's participant count is the
    // whole team rather than whoever happened to run the session.
    const [column] = await columnIds(participant)
    await writeCard(participant, column, 'Standups ran long')

    await playAndClose(page, 'Deploys are slow', 'Fix the build first')

    await goToTeam(page)
    await page.getByRole('link', { name: /Retrospective/i }).click()
    await waitForLiveView(page)

    // The archive says what happened without opening anything (FR-601).
    await expect(page.locator('#archive li')).toHaveCount(1)
    const entry = page.locator('#archive li').first()
    await expect(entry).toContainText('Sprint 12')
    await expect(entry).toContainText('2')

    await entry.locator('a').click()
    await waitForLiveView(page)

    // And the recap carries the whole session (FR-602).
    await expect(page.locator('#recap-board')).toContainText('Deploys are slow')
    await expect(page.locator('#recap-topics')).toContainText('Fix the build first')
    await expect(page.locator('#recap-participants')).toContainText('2')

    // Read-only: there is no form on it at all.
    await expect(page.locator('form')).toHaveCount(0)

    await participant.close()
  })

  test('[FR-210][FR-602] an anonymous recap names nobody, days later', async ({
    page,
    context,
  }) => {
    const { participant, account } = await brainstormWithTwoPeople(page, context, {
      anonymous: true,
    })

    const [first] = await columnIds(participant)
    await writeCard(participant, first, 'Standups ran long')

    page.once('dialog', (dialog) => dialog.accept())
    await page.locator('#close-session').click()
    await expect(page.locator('#close-session')).toHaveCount(0)

    await goToTeam(page)
    await page.getByRole('link', { name: /Retrospective/i }).click()
    await waitForLiveView(page)
    await page.locator('#archive li a').first().click()
    await waitForLiveView(page)

    await expect(page.locator('#recap-board')).toContainText('Standups ran long')
    await expect(page.locator('main')).not.toContainText(account.displayName)

    await participant.close()
  })

  test('[FR-603] search finds what a past retrospective said', async ({ page, context }) => {
    const { participant } = await brainstormWithTwoPeople(page, context)

    await playAndClose(page, 'Deploys are slow', 'Fix the build first')

    await goToTeam(page)
    await page.locator('#team-search-link').click()
    await waitForLiveView(page)

    await expect(page.locator('#search-prompt')).toBeVisible()

    await page.locator('#search-form input[name="search[q]"]').fill('deploys')

    await expect(page.locator('#search-cards')).toContainText('Deploys are slow')

    await page.locator('#search-cards li a').first().click()
    await waitForLiveView(page)

    await expect(page.locator('#recap-board')).toContainText('Deploys are slow')

    await participant.close()
  })

  test('[FR-604] the dashboard draws a point per finished retrospective', async ({
    page,
    context,
  }) => {
    const { participant } = await brainstormWithTwoPeople(page, context)

    await playAndClose(page, 'Deploys are slow', 'Fix the build first')

    await goToTeam(page)
    await page.locator('#team-insights-link').click()
    await waitForLiveView(page)

    await expect(page.locator('#cards-trend li')).toHaveCount(1)
    await expect(page.locator('#participation-trend')).toContainText('%')

    // No org-wide section for somebody who is not an Org Admin (FR-605).
    await expect(page.locator('#org-insights')).toHaveCount(0)

    await participant.close()
  })
})
