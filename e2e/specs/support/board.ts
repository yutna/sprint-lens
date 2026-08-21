import { expect, type BrowserContext, type Page } from '@playwright/test'
import { registerAndSignIn, waitForLiveView } from './auth'

/**
 * Getting two real people onto one real board.
 *
 * Every board scenario in section 10 is a claim about what one person sees of
 * another person's work, so the fixture is two browser contexts rather than
 * two tabs: separate cookie jars, separate sockets, nothing shared but the
 * server.
 */

export type BoardOptions = {
  blind?: boolean
  anonymous?: boolean
  template?: string
}

export async function createTeam(page: Page, name: string): Promise<void> {
  await page.goto('/teams')
  await waitForLiveView(page)
  await page.locator('#team_form input[name="team[name]"]').fill(name)
  await page.locator('#team_form button').click()
  await expect(page.getByRole('heading', { name })).toBeVisible()
}

export async function inviteTeammate(page: Page, email: string): Promise<void> {
  await expect(page.locator('#members li').first()).toBeVisible()
  const before = await page.locator('#members li').count()

  await page.locator('#add_member_form input[name="membership[email]"]').fill(email)
  await page.locator('#add_member_form button').click()
  await expect(page.locator('#members li')).toHaveCount(before + 1)
}

/**
 * A started session, its facilitator, and a second member already on the
 * board, brought to the brainstorm phase.
 */
export async function brainstormWithTwoPeople(
  page: Page,
  context: BrowserContext,
  options: BoardOptions = {},
) {
  const participant = await context.browser()!.newPage()
  const account = await registerAndSignIn(participant)

  await registerAndSignIn(page)
  await createTeam(page, 'Board')
  await inviteTeammate(page, account.email)

  await page.getByRole('link', { name: /Retrospective/i }).click()
  await waitForLiveView(page)

  await page.locator('#session_form input[name="session[title]"]').fill('Sprint 12')
  await page.locator('#session_form select[name="session[template_id]"]').selectOption({
    label: options.template ?? 'เริ่ม-หยุด-ทำต่อ',
  })

  // A checkbox `.input` renders a hidden field of the same name alongside it,
  // so the type has to be part of the selector or the locator is ambiguous.
  if (options.blind) {
    await page.locator('#session_form input[type="checkbox"][name="session[is_blind]"]').check()
  }

  if (options.anonymous) {
    await page.locator('#session_form input[type="checkbox"][name="session[is_anonymous]"]').check()
  }

  await page.locator('#session_form button').click()
  await expect(page.getByRole('heading', { name: 'Sprint 12' })).toBeVisible()

  await page.locator('#start-session').click()
  await expect(page.locator('#close-session')).toBeVisible()

  const boardUrl = page.url()
  await participant.goto(boardUrl)
  await waitForLiveView(participant)

  // Cards can only be written in the brainstorm phase (FR-205).
  await page.locator('#phase-brainstorm').click()
  await expect(page.locator('#board section[role="tabpanel"]').first()).toBeVisible()

  return { participant, account, boardUrl }
}

/**
 * One person, one board, already brainstorming.
 *
 * The mobile scenarios are about one phone rather than about two people
 * agreeing, so a second browser context would only slow them down.
 */
export async function soloBrainstorm(page: Page, options: BoardOptions = {}) {
  await registerAndSignIn(page)
  await createTeam(page, 'Phone')

  await page.getByRole('link', { name: /Retrospective/i }).click()
  await waitForLiveView(page)

  await page.locator('#session_form input[name="session[title]"]').fill('Sprint 12')
  await page.locator('#session_form select[name="session[template_id]"]').selectOption({
    label: options.template ?? 'เริ่ม-หยุด-ทำต่อ',
  })
  await page.locator('#session_form button').click()
  await expect(page.getByRole('heading', { name: 'Sprint 12' })).toBeVisible()

  await page.locator('#start-session').click()
  await expect(page.locator('#close-session')).toBeVisible()

  const boardUrl = page.url()
  const joinCode = (await page.locator('#join-code').innerText()).trim()

  await page.locator('#phase-brainstorm').click()

  return { boardUrl, joinCode }
}

/**
 * Whether the document is wider than the window — the thing FR-905 forbids.
 */
export async function scrollsSideways(page: Page): Promise<boolean> {
  return page.evaluate(() => {
    const root = document.documentElement
    // A single pixel of rounding is not a horizontal scrollbar.
    return root.scrollWidth - root.clientWidth > 1
  })
}

/** The ids of the board's columns, in board order. */
export async function columnIds(page: Page): Promise<string[]> {
  const ids = await page
    .locator('#board section[role="tabpanel"]')
    .evaluateAll((nodes) => nodes.map((node) => node.id.replace('column-', '')))

  expect(ids.length).toBeGreaterThan(1)

  return ids
}

/** Writes a card into a column and waits for it to appear. */
export async function writeCard(page: Page, columnId: string, text: string): Promise<void> {
  const before = await page.locator(`#cards-${columnId} li`).count()

  await page.locator(`#card-text-${columnId}`).fill(text)
  await page.locator(`#add-card-${columnId}`).click()

  await expect(page.locator(`#cards-${columnId} li`)).toHaveCount(before + 1)
}
