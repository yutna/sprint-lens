import { expect, type Page } from '@playwright/test'

/**
 * Helpers for driving the app as a signed-in person.
 *
 * The e2e database is shared by the whole run, so every account gets a unique
 * address rather than a fixed one — otherwise the second test to register
 * would collide with the first.
 */

export type Account = { email: string; displayName: string }

/**
 * Waits until the LiveView socket is connected.
 *
 * A form whose only handler is `phx-submit` does nothing at all until the
 * socket is up, so clicking too early is a silent no-op rather than an error.
 * Chromium happened to be fast enough to hide this; WebKit was not.
 */
export async function waitForLiveView(page: Page): Promise<void> {
  await page.waitForFunction(() => {
    const socket = (window as unknown as { liveSocket?: { isConnected(): boolean } }).liveSocket
    return Boolean(socket && socket.isConnected())
  })
}

let counter = 0

function unique(prefix: string): string {
  counter += 1
  return `${prefix}-${process.pid}-${Date.now()}-${counter}`
}

/**
 * Registers a new account and signs in via the emailed link.
 *
 * The app deliberately has no "register with a password" flow — the account
 * is confirmed by a link and the password is set from inside the session
 * afterwards — so the local mailbox is where the link comes from.
 */
export async function registerAndSignIn(page: Page): Promise<Account> {
  const email = `${unique('e2e')}@example.com`
  const displayName = unique('Person')

  await page.goto('/users/register')
  await waitForLiveView(page)
  await page.locator('#registration_form input[name="user[display_name]"]').fill(displayName)
  await page.locator('#registration_form input[name="user[email]"]').fill(email)
  await page.locator('#registration_form button').click()

  await expect(page).toHaveURL(/\/users\/log-in$/)

  await page.goto('/users/log-in')
  await waitForLiveView(page)
  await page.locator('#login_form_magic input[name="user[email]"]').fill(email)
  await page.locator('#login_form_magic button').click()

  const link = await magicLinkFor(page, email)
  await page.goto(link)
  await waitForLiveView(page)
  await page.locator('#confirmation_form button, #login_form button').first().click()

  await expect(page).toHaveURL(/\/home$/)

  // The session has to survive a plain navigation, not only the redirect
  // chain that created it — a cookie that works once is not a session.
  await page.goto('/home')
  await expect(page).toHaveURL(/\/home$/)

  return { email, displayName }
}

/**
 * Reads the most recent sign-in link for `email` out of the local mailbox
 * that the `:e2e` environment delivers to.
 */
async function magicLinkFor(page: Page, email: string): Promise<string> {
  const response = await page.request.get('/dev/mailbox')
  const html = await response.text()

  const ids = [...html.matchAll(/\/dev\/mailbox\/([^"']+)/g)].map((match) => match[1])

  for (const id of ids.reverse()) {
    const mail = await (await page.request.get(`/dev/mailbox/${id}`)).text()

    if (mail.includes(email)) {
      const match = mail.match(/https?:\/\/[^\s"'<]+\/users\/log-in\/[^\s"'<]+/)
      if (match) return match[0]
    }
  }

  throw new Error(`no sign-in link found for ${email}`)
}
