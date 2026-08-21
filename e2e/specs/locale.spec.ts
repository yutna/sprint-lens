import { expect, test } from '@playwright/test'
import { registerAndSignIn, waitForLiveView } from './support/auth'

/**
 * Switching language, on a page that has no live process behind it.
 *
 * This is the spec the suite did not have. Every existing test that touched
 * the switcher reached its page through a LiveView, so a live process existed
 * by construction and the pushed event always had somewhere to go. The
 * landing page is a plain controller, the click went nowhere, and nothing
 * failed anywhere.
 */
test.describe('the language switcher', () => {
  test('[FR-907] changes the language on the very first page, and the choice survives a reload', async ({
    page,
  }) => {
    await page.goto('/')

    // Thai first (FR-906), before anyone has chosen anything.
    await expect(page.locator('html')).toHaveAttribute('lang', 'th')

    await page.getByRole('link', { name: 'EN', exact: true }).click()

    await expect(page.locator('html')).toHaveAttribute('lang', 'en')
    // Scoped to the page body: the navigation bar offers "Log in" as well.
    await expect(page.getByRole('main').getByRole('link', { name: 'Log in' })).toBeVisible()

    await page.reload()

    await expect(page.locator('html')).toHaveAttribute('lang', 'en')
  })

  test('[FR-907] brings the visitor back to the page they were on', async ({ page }) => {
    await page.goto('/users/log-in')

    await page.getByRole('link', { name: 'EN', exact: true }).click()

    await expect(page).toHaveURL(/\/users\/log-in$/)
    await expect(page.locator('html')).toHaveAttribute('lang', 'en')
  })

  test('[FR-907] follows a signed-in person into their profile', async ({ page }) => {
    await registerAndSignIn(page)
    await waitForLiveView(page)

    await page.getByRole('link', { name: 'EN', exact: true }).click()

    await expect(page.locator('html')).toHaveAttribute('lang', 'en')

    // Not the session cookie this time: it is on the account, so it is still
    // English after a full reload of a different page.
    await page.goto('/teams')

    await expect(page.locator('html')).toHaveAttribute('lang', 'en')
  })
})

test.describe('the theme toggle', () => {
  /**
   * The half that used to be lost. The client repainted immediately, nothing
   * was stored, and the next request handed back the operating system's
   * preference — so a visitor who chose a theme before signing in lost it.
   */
  test('[FR-911] keeps a signed-out visitor’s choice across a reload', async ({ page }) => {
    await page.goto('/')

    // The page is Thai at this point, so the control is addressed by its
    // Thai label — which is the point of the suite running in Thai.
    await page.getByRole('link', { name: 'ธีมมืด' }).click()

    await expect(page.locator('html')).toHaveAttribute('data-theme', 'dark')
    await expect(page.locator('html')).toHaveAttribute('data-theme-source', 'user')

    await page.reload()

    await expect(page.locator('html')).toHaveAttribute('data-theme', 'dark')
  })
})
