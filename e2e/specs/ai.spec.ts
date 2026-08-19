import { expect, test, type Page } from '@playwright/test'
import { brainstormWithTwoPeople, columnIds, writeCard } from './support/board'
import { waitForLiveView } from './support/auth'

/**
 * Acceptance scenario 10.6, both halves.
 *
 * The e2e environment runs against `SprintLens.AI.FakeAdapter`, so the whole
 * flow — asking, waiting, reading, accepting — happens for real without a
 * model or a network. That substitution is itself the test of AI-004: nothing
 * in the browser knows which provider answered.
 *
 * The second half is reached through the team's own opt-in rather than the
 * organisation's kill switch, because there is deliberately no way to make
 * somebody an Org Admin through the UI. The kill-switch variant is covered in
 * ExUnit, where an org admin is one insert away.
 */

async function goToTeam(page: Page) {
  await page.goto('/teams')
  await waitForLiveView(page)
  await page.locator('#teams li a').first().click()
  await waitForLiveView(page)
}

/** Turns the team's AI opt-in on (FR-105, AI-003). */
async function optIn(page: Page) {
  await goToTeam(page)
  await page.locator('#team_settings_form input[type="checkbox"][name="team[ai_opt_in]"]').check()
  await page.locator('#team_settings_form button').first().click()
  await expect(page.locator('#flash-info')).toBeVisible()
}

/** Closes the session and opens its recap. */
async function closeAndOpenRecap(page: Page, text: string) {
  const [first] = await columnIds(page)
  await writeCard(page, first, text)

  page.once('dialog', (dialog) => dialog.accept())
  await page.locator('#close-session').click()
  await expect(page.locator('#close-session')).toHaveCount(0)

  await goToTeam(page)
  await page.getByRole('link', { name: /Retrospective/i }).click()
  await waitForLiveView(page)
  await page.locator('#archive li a').first().click()
  await waitForLiveView(page)
}

test.describe('AI suggestions', () => {
  test('[AI-002][AI-005][AI-009] @spec-10.6 a suggested recap needs a human yes', async ({
    page,
    context,
  }) => {
    const { participant, boardUrl } = await brainstormWithTwoPeople(page, context)

    await optIn(page)

    // Back to the board the fixture left running, then close it.
    await page.goto(boardUrl)
    await waitForLiveView(page)

    await closeAndOpenRecap(page, 'Deploys are slow')

    // The slot is there because the team opted in (AI-003).
    await expect(page.locator('#ai-summary')).toBeVisible()
    await expect(page.locator('#recap-summary-text')).toHaveCount(0)

    await page.locator('#ai-summary-request').click()

    // The job runs in the background and the page is told when it is ready
    // (AI-005) — no reload, no polling loop in the test.
    await expect(page.locator('#ai-summary-draft')).toContainText('## Summary', {
      timeout: 15_000,
    })

    // AI-002: still nothing attached. The draft is a question, not an answer.
    await expect(page.locator('#recap-summary-text')).toHaveCount(0)

    await page.locator('#ai-summary-accept').click()

    await expect(page.locator('#recap-summary-text')).toContainText('## Summary')
    await expect(page.locator('#ai-summary-accepted')).toBeVisible()

    await participant.close()
  })

  test('[AI-001][AI-003] @spec-10.6 with AI off, nothing appears and nothing breaks', async ({
    page,
    context,
  }) => {
    // The team's opt-in is off by default (FR-105), which is the state this
    // half of 10.6 describes from the user's side.
    const { participant } = await brainstormWithTwoPeople(page, context)

    await closeAndOpenRecap(page, 'Deploys are slow')

    // Absent, not disabled: nobody wonders what they are missing.
    await expect(page.locator('#ai-summary')).toHaveCount(0)

    // And every flow completes normally (AI-001): the recap reads, the
    // export downloads, the archive lists it.
    await expect(page.locator('#recap-board')).toContainText('Deploys are slow')
    await expect(page.locator('#recap-participants')).toBeVisible()

    const [download] = await Promise.all([
      page.waitForEvent('download'),
      page.locator('#export-markdown').click(),
    ])

    expect(download.suggestedFilename()).toContain('.md')

    await participant.close()
  })
})
