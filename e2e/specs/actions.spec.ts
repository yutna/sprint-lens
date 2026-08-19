import { expect, test, type Page } from '@playwright/test'
import { brainstormWithTwoPeople, columnIds, writeCard } from './support/board'
import { waitForLiveView } from './support/auth'

/**
 * Acceptance scenarios 10.4 (the action half) and 10.5.
 *
 * 10.5 is unusual among the scenarios: it is a claim about two *sessions*
 * rather than two people. What last week's retro left open has to be the
 * first thing this week's check-in shows, and an item carried forward has to
 * keep the link to where it came from. So these tests close a session and
 * start another, which nothing else in the suite does.
 */

/** Walks a started session to the discuss phase with one card on the board. */
async function discussWithCard(page: Page, text: string) {
  const [first] = await columnIds(page)
  await writeCard(page, first, text)

  await page.locator('#phase-discuss').click()
  await expect(page.locator('#actions-panel')).toBeVisible()
}

async function addAction(page: Page, title: string, owner?: string) {
  await page.locator('#action-form input[name="action[title]"]').fill(title)

  if (owner) {
    await page.locator('#action-form select[name="action[assignee_id]"]').selectOption({
      label: owner,
    })
  }

  await page.locator('#action-form button').click()
  await expect(page.locator('#action-list li').filter({ hasText: title })).toBeVisible()
}

/** Closes the session and starts the team's next one, landing on check-in. */
async function startNextSession(page: Page) {
  page.once('dialog', (dialog) => dialog.accept())
  await page.locator('#close-session').click()
  await expect(page.locator('#close-session')).toHaveCount(0)

  await goToTeam(page)
  await page.getByRole('link', { name: /Retrospective/i }).click()
  await waitForLiveView(page)

  await page.locator('#session_form input[name="session[title]"]').fill('Sprint 13')
  await page.locator('#session_form button').click()
  await expect(page.getByRole('heading', { name: 'Sprint 13' })).toBeVisible()

  await page.locator('#start-session').click()
  await expect(page.locator('#close-session')).toBeVisible()
}

/** The team detail page, reached the way a person would reach it. */
async function goToTeam(page: Page) {
  await page.goto('/teams')
  await waitForLiveView(page)
  await page.locator('#teams li a').first().click()
  await waitForLiveView(page)
}

/** SCR-10, reached from the team page. */
async function goToActions(page: Page) {
  await goToTeam(page)
  await page.locator('#team-actions-link').click()
  await waitForLiveView(page)
}

test.describe('action items and carry-over', () => {
  test('[FR-501][FR-502][FR-504] @spec-10.4 an action lands in the team list', async ({
    page,
    context,
  }) => {
    const { participant } = await brainstormWithTwoPeople(page, context)

    await discussWithCard(page, 'Deploys are slow')

    // The participant writes it — 10.4's "a participant adds an action item".
    // Their screen follows the facilitator's phase without being told twice.
    await expect(participant.locator('#action-form')).toBeVisible()

    await participant.locator('#action-form input[name="action[title]"]').fill('Cache the layers')
    await participant.locator('#action-form input[name="action[due_date]"]').fill('2026-12-31')
    await participant.locator('#action-form button').click()

    // It reaches the other screen (FR-306) and the team's list (FR-504).
    await expect(page.locator('#action-list')).toContainText('Cache the layers')

    await goToActions(page)

    await expect(page.locator('#actions')).toContainText('Cache the layers')
    await expect(page.locator('#stat-open')).toContainText('1')

    await participant.close()
  })

  test('[FR-505] @spec-10.5 the last retro’s open actions come back first', async ({
    page,
    context,
  }) => {
    const { participant } = await brainstormWithTwoPeople(page, context)

    await discussWithCard(page, 'Deploys are slow')
    await addAction(page, 'Write the runbook')
    await addAction(page, 'Fix the flaky test')

    await startNextSession(page)

    // Check-in opens with both, for a quick status update.
    await expect(page.locator('#carry-over-review')).toBeVisible()
    await expect(page.locator('#carry-over-list li')).toHaveCount(2)

    const rows = page.locator('#carry-over-list li')
    const doneId = (await rows.first().getAttribute('id'))!.replace('action-', '')
    const carryId = (await rows.nth(1).getAttribute('id'))!.replace('action-', '')

    // One marked done leaves the open list...
    await page.locator(`#action-status-${doneId}`).selectOption('done')
    await expect(page.locator(`#action-${doneId}`)).toHaveCount(0)

    // ...and one carried over keeps a link to where it came from.
    await page.locator(`#carry-over-${carryId}`).click()

    await expect(page.locator('#carry-over-list li')).toHaveCount(1)
    await expect(page.locator('#carry-over-list li [id^="action-carried-"]')).toBeVisible()
    await expect(page.locator(`#action-${carryId}`)).toHaveCount(0)

    await participant.close()
  })

  test('[FR-503] an action can still be changed after the session closes', async ({
    page,
    context,
  }) => {
    const { participant } = await brainstormWithTwoPeople(page, context)

    await discussWithCard(page, 'Deploys are slow')
    await addAction(page, 'Write the runbook')

    page.once('dialog', (dialog) => dialog.accept())
    await page.locator('#close-session').click()
    await expect(page.locator('#close-session')).toHaveCount(0)

    await goToActions(page)

    const row = page.locator('#actions li').first()
    const id = (await row.getAttribute('id'))!.replace('action-', '')

    await page.locator(`#action-status-${id}`).selectOption('in_progress')
    await expect(page.locator('#stat-open')).toContainText('1')

    await page.reload()
    await waitForLiveView(page)
    await expect(page.locator(`#action-status-${id}`)).toHaveValue('in_progress')

    await participant.close()
  })
})
