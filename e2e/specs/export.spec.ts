import { readFileSync } from 'node:fs'
import { expect, test, type Page } from '@playwright/test'
import { brainstormWithTwoPeople, columnIds, writeCard } from './support/board'
import { waitForLiveView } from './support/auth'

/**
 * Taking a retrospective out of the app, and telling another system about it
 * (FR-701 to FR-706).
 *
 * The export tests download the real bytes rather than checking that a link
 * exists: a `content-disposition` header and a body that parses are the whole
 * feature, and neither is visible on the page.
 */

async function goToTeam(page: Page) {
  await page.goto('/teams')
  await waitForLiveView(page)
  await page.locator('#teams li a').first().click()
  await waitForLiveView(page)
}

/** Writes one card, then closes the session and opens its recap. */
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

/** Clicks a download link and returns what landed on disk. */
async function downloadText(page: Page, selector: string): Promise<string> {
  const [download] = await Promise.all([
    page.waitForEvent('download'),
    page.locator(selector).click(),
  ])

  return readFileSync(await download.path(), 'utf8')
}

test.describe('exporting and notifying', () => {
  test('[FR-701][FR-702][FR-703] a recap downloads in all three formats', async ({
    page,
    context,
  }) => {
    const { participant } = await brainstormWithTwoPeople(page, context)

    await closeAndOpenRecap(page, 'Deploys are slow')

    const cases = [
      { id: '#export-markdown', extension: '.md' },
      { id: '#export-csv-cards', extension: '.cards.csv' },
      { id: '#export-csv-actions', extension: '.actions.csv' },
      { id: '#export-json', extension: '.json' },
    ]

    for (const { id, extension } of cases) {
      const [download] = await Promise.all([
        page.waitForEvent('download'),
        page.locator(id).click(),
      ])

      expect(download.suggestedFilename()).toContain(extension)
    }

    await participant.close()
  })

  test('[FR-701][FR-703] and the downloaded bytes are the session', async ({ page, context }) => {
    const { participant } = await brainstormWithTwoPeople(page, context)

    await closeAndOpenRecap(page, 'Deploys are slow')

    // Reading the saved file rather than re-requesting the URL: what the
    // button actually produced is the thing under test.
    const markdown = await downloadText(page, '#export-markdown')

    expect(markdown).toContain('# Sprint 12')
    expect(markdown).toContain('- Deploys are slow')

    const json = JSON.parse(await downloadText(page, '#export-json'))

    expect(json.session.title).toBe('Sprint 12')
    expect(json.session.participant_count).toBe(1)
    expect(json.cards.map((card: { text: string }) => card.text)).toContain('Deploys are slow')

    const csv = await downloadText(page, '#export-csv-cards')

    expect(csv.split('\r\n')[0]).toBe('id,column,text,author,created_at')
    expect(csv).toContain('Deploys are slow')

    await participant.close()
  })

  test('[FR-704][FR-706] a lead configures a webhook and reads its log', async ({
    page,
    context,
  }) => {
    const { participant } = await brainstormWithTwoPeople(page, context)

    await goToTeam(page)

    await expect(page.locator('#webhook_form')).toBeVisible()
    await expect(page.locator('#deliveries-empty')).toBeVisible()

    await page.locator('#webhook_form input[name="webhook[url]"]').fill(
      'https://hooks.example.invalid/sprintlens',
    )
    await page
      .locator('#webhook_form input[name="webhook[secret]"]')
      .fill('a-secret-long-enough-to-use')
    await page.locator('#webhook-event-session\\.closed').check()
    await page.locator('#save-webhook').click()

    // The remove button only exists once there is a webhook to remove.
    await expect(page.locator('#delete-webhook')).toBeVisible()

    // The secret is never rendered back, on this page load or any other.
    await page.reload()
    await waitForLiveView(page)
    await expect(page.locator('main')).not.toContainText('a-secret-long-enough-to-use')
    await expect(page.locator('#webhook_form input[name="webhook[url]"]')).toHaveValue(
      'https://hooks.example.invalid/sprintlens',
    )

    page.once('dialog', (dialog) => dialog.accept())
    await page.locator('#delete-webhook').click()
    await expect(page.locator('#delete-webhook')).toHaveCount(0)

    await participant.close()
  })
})
