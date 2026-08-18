import { expect, test, type Page } from '@playwright/test'
import { registerAndSignIn, waitForLiveView } from './support/auth'

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

    const list = page.locator('#templates')
    for (const name of ['Start-Stop-Continue', 'Mad-Sad-Glad', '4Ls', 'KPT', 'Sailboat']) {
      await expect(list).toContainText(name)
    }
  })

  test('[FR-202] a custom template is saved with its columns', async ({ page }) => {
    await registerAndSignIn(page)
    await createTeam(page, 'Custom')
    await page.goto(`${page.url()}/templates`)
    await waitForLiveView(page)

    const form = page.locator('#template_form')
    await form.locator('input[name="template[name]"]').fill('Our own')
    await form.locator('input[name="template[columns][0][name]"]').fill('Kept')
    await form.locator('input[name="template[columns][0][hint]"]').fill('Worth keeping?')
    await form.locator('input[name="template[columns][1][name]"]').fill('Dropped')
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
    await form.locator('input[name="template[name]"]').fill('Too few')
    await form.locator('input[name="template[columns][0][name]"]').fill('Only')
    await form.locator('button').click()

    await expect(form.locator('.text-error')).toBeVisible()
    await expect(page.locator('#templates')).not.toContainText('Too few')
  })
})
