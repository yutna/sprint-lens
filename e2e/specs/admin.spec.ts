import { expect, test, type Page } from '@playwright/test'
import { registerAndSignIn, waitForLiveView } from './support/auth'
import { createTeam } from './support/board'

/**
 * SCR-12, in a browser (FR-801 to FR-807).
 *
 * There is no way to make somebody an Org Admin through the UI — by design,
 * since granting that right is a deployment decision rather than a feature —
 * so these tests check the half that is reachable: the page refuses everybody
 * else, and it refuses them by sending them somewhere rather than by
 * rendering an empty version of itself.
 *
 * The rest of SCR-12 is covered in ExUnit, where an org admin can be created
 * directly.
 */

async function signInAsMember(page: Page) {
  await registerAndSignIn(page)
  await createTeam(page, 'Alpha')
}

test.describe('the administration page', () => {
  test('[FR-801] is not reachable by somebody who is not an Org Admin', async ({ page }) => {
    await signInAsMember(page)

    await page.goto('/admin')
    await waitForLiveView(page)

    // Sent home with a reason, rather than shown a page with nothing on it.
    await expect(page).toHaveURL(/\/home$/)
    await expect(page.locator('#flash-error')).toBeVisible()
    await expect(page.locator('#admin-users')).toHaveCount(0)
  })

  test('[FR-801] and its API refuses rather than pretending not to exist', async ({ page }) => {
    await signInAsMember(page)

    // 403, not 404: an administration endpoint is not a secret the way
    // another team's board is.
    const response = await page.request.get('/api/v1/admin/users', {
      headers: { accept: 'application/json' },
    })

    expect([401, 403]).toContain(response.status())
  })
})
