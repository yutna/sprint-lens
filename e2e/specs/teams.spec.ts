import { expect, test, type Page } from '@playwright/test'
import { fillSettled, registerAndSignIn, waitForLiveView } from './support/auth'

/**
 * Teams, membership and templates driven through a real browser.
 *
 * The ExUnit suite already asserts these rules against the context and the
 * LiveView. What only a browser can show is that the whole stack agrees: the
 * form posts what the server expects, the live navigation lands where it
 * should, and the page a person actually sees reflects the change.
 *
 * Everything runs in Thai, the default the spec asks for (FR-906), and every
 * selector is an id or a field name rather than copy — so retranslating a
 * string does not break the suite.
 */

async function createTeam(page: Page, name: string): Promise<void> {
  await page.goto('/teams')
  await waitForLiveView(page)
  await page.locator('#team_form input[name="team[name]"]').fill(name)
  await page.locator('#team_form button').click()
  await expect(page.getByRole('heading', { name })).toBeVisible()
}

test.describe('teams', () => {
  test('[FR-101] anyone can create a team and becomes its lead', async ({ page }) => {
    await registerAndSignIn(page)
    await createTeam(page, 'Platform')

    // Only a lead sees the settings form, so its presence is the assertion
    // that the creator got the lead role (FR-101).
    await expect(page.locator('#team_settings_form')).toBeVisible()
    await expect(page.locator('#members li')).toHaveCount(1)
  })

  test('[FR-103] a team you do not belong to is not reachable', async ({ page, context }) => {
    await registerAndSignIn(page)
    await createTeam(page, 'Private')
    const teamUrl = page.url()

    const other = await context.browser()!.newPage()
    await registerAndSignIn(other)
    await other.goto(teamUrl)

    await expect(other).toHaveURL(/\/teams$/)
    await expect(other.locator('body')).not.toContainText('Private')
    await other.close()
  })

  test('[FR-102] a lead adds a member by email and can remove them', async ({ page, context }) => {
    const teammate = await context.browser()!.newPage()
    const { email } = await registerAndSignIn(teammate)
    await teammate.close()

    await registerAndSignIn(page)
    await createTeam(page, 'Alpha')

    await page.locator('#add_member_form input[name="membership[email]"]').fill(email)
    await page.locator('#add_member_form button').click()
    await expect(page.locator('#members li')).toHaveCount(2)

    await page.locator('#members button[phx-click="remove_member"]').first().click()
    await expect(page.locator('#members li')).toHaveCount(1)
  })

  test('[FR-105] a lead changes the vote budget and the AI opt-in', async ({ page }) => {
    await registerAndSignIn(page)
    await createTeam(page, 'Settings')

    const form = page.locator('#team_settings_form')
    await form.locator('input[name="team[default_vote_budget]"]').fill('8')
    await form.locator('input[type="checkbox"][name="team[ai_opt_in]"]').check()
    await form.locator('button').click()

    await page.reload()
    await expect(form.locator('input[name="team[default_vote_budget]"]')).toHaveValue('8')
    await expect(form.locator('input[type="checkbox"][name="team[ai_opt_in]"]')).toBeChecked()
  })

  test('[FR-106] archiving makes a team read-only', async ({ page }) => {
    await registerAndSignIn(page)
    await createTeam(page, 'Retired')

    page.once('dialog', (dialog) => dialog.accept())
    await page.locator('#archive-team').click()

    await expect(page.locator('#restore-team')).toBeVisible()
    await expect(page.locator('#add_member_form')).toHaveCount(0)
    await expect(page.locator('#team_settings_form')).toHaveCount(0)
  })

  test('[FR-201] the five built-in templates are available to a new team', async ({ page }) => {
    await registerAndSignIn(page)
    await createTeam(page, 'Templates')
    await page.goto(`${page.url()}/templates`)
    await waitForLiveView(page)

    // In Thai, because this suite runs in Thai and the built-in templates are
    // the product's own words rather than a team's (FR-906, FR-909). They used
    // to be seeded in English and rendered straight out of the database, which
    // is what this assertion was quietly encoding. "4Ls" and "KPT" are shipped
    // untranslated on purpose — they are the names these formats are known by.
    const list = page.locator('#templates')
    for (const name of ['เริ่ม-หยุด-ทำต่อ', 'โกรธ-เศร้า-ดีใจ', '4Ls', 'KPT', 'เรือใบ']) {
      await expect(list).toContainText(name)
    }

    // And a column heading with it, since the board is where this is seen.
    await expect(list).toContainText('เริ่มทำ')
  })

  test('[FR-202] a custom template is saved with its columns', async ({ page }) => {
    await registerAndSignIn(page)
    await createTeam(page, 'Custom')
    await page.goto(`${page.url()}/templates`)
    await waitForLiveView(page)

    // The form validates on change, so each box waits for its own round trip
    // before the next one is typed into (see `fillSettled`).
    const form = page.locator('#template_form')
    const box = (name: string) => form.locator(`input[name="template${name}"]`)

    await fillSettled(page, box('[name]'), 'Our own')
    await fillSettled(page, box('[columns][0][name]'), 'Kept')
    await fillSettled(page, box('[columns][0][hint]'), 'Worth keeping?')
    await fillSettled(page, box('[columns][1][name]'), 'Dropped')
    await form.locator('button').click()

    const list = page.locator('#templates')
    await expect(list).toContainText('Our own')
    await expect(list).toContainText('Kept')
    await expect(list).toContainText('Dropped')
  })

  test('[FR-202] a single column is refused and nothing is saved', async ({ page }) => {
    await registerAndSignIn(page)
    await createTeam(page, 'Bounds')
    await page.goto(`${page.url()}/templates`)
    await waitForLiveView(page)

    const form = page.locator('#template_form')

    await fillSettled(page, form.locator('input[name="template[name]"]'), 'Too few')
    await fillSettled(page, form.locator('input[name="template[columns][0][name]"]'), 'Only')
    await form.locator('button').click()

    await expect(form.locator('.text-error')).toBeVisible()
    await expect(page.locator('#templates')).not.toContainText('Too few')
  })
})
