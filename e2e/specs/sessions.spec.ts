import { expect, test, type Page } from '@playwright/test'
import { registerAndSignIn, waitForLiveView } from './support/auth'

/**
 * The live board, driven through real browsers.
 *
 * Scenario 10.1 is a claim about two people at once: the facilitator changes
 * something and "every joining member sees the same phase and timer state".
 * The ExUnit suite mounts two LiveViews to assert that; here it is two actual
 * browser contexts, which is the only place the socket, the diff and the DOM
 * are all in play.
 */

async function createTeam(page: Page, name: string): Promise<void> {
  await page.goto('/teams')
  await waitForLiveView(page)
  await page.locator('#team_form input[name="team[name]"]').fill(name)
  await page.locator('#team_form button').click()
  await expect(page.getByRole('heading', { name })).toBeVisible()
}

async function inviteTeammate(page: Page, email: string): Promise<void> {
  // Counted relative to what is already there: this helper is used more than
  // once on the same team. Waiting for the list to have rendered first, or
  // the count is read as zero and every later assertion is off by however
  // many members were already there.
  await expect(page.locator('#members li').first()).toBeVisible()
  const before = await page.locator('#members li').count()

  await page.locator('#add_member_form input[name="membership[email]"]').fill(email)
  await page.locator('#add_member_form button').click()
  await expect(page.locator('#members li')).toHaveCount(before + 1)
}

// The built-in templates read in Thai, because this suite runs in Thai and
// their wording is the product's own rather than a team's (FR-906).
async function createSession(page: Page, title: string, template = 'เริ่ม-หยุด-ทำต่อ') {
  await page.locator('#session_form input[name="session[title]"]').fill(title)
  // The select has no empty option, so it always submits something; choosing
  // explicitly is what scenario 10.1 describes anyway.
  await page.locator('#session_form select[name="session[template_id]"]').selectOption({
    label: template,
  })
  await page.locator('#session_form button').click()
  await expect(page.getByRole('heading', { name: title })).toBeVisible()
}

/** The facilitator's board, plus a second signed-in participant on it. */
async function twoPeopleOnABoard(page: Page, context: import('@playwright/test').BrowserContext) {
  const participant = await context.browser()!.newPage()
  const { email } = await registerAndSignIn(participant)

  await registerAndSignIn(page)
  await createTeam(page, 'Realtime')
  await inviteTeammate(page, email)

  await page.getByRole('link', { name: /Retrospective/i }).click()
  await waitForLiveView(page)
  await createSession(page, 'Sprint 12')

  await page.locator('#start-session').click()
  await expect(page.locator('#close-session')).toBeVisible()

  const boardUrl = page.url()
  await participant.goto(boardUrl)
  await waitForLiveView(participant)

  return { participant, boardUrl }
}

test.describe('the lobby', () => {
  /**
   * The clipboard is the one thing here a LiveView test cannot reach: the
   * hook runs in the browser, `navigator.clipboard` is a browser API, and a
   * hook that silently fails looks exactly like a hook that works.
   */
  test('[FR-204] the code is on the screen and the link is one tap away', async ({
    page,
    context,
    browserName,
  }) => {
    await registerAndSignIn(page)
    await createTeam(page, 'Lobby')
    await page.getByRole('link', { name: /Retrospective/i }).click()
    await waitForLiveView(page)
    await createSession(page, 'Sprint 20')

    // Not started, so this is the room rather than the board.
    await expect(page.locator('#lobby')).toBeVisible()
    await expect(page.locator('#phase-bar')).toHaveCount(0)

    const code = (await page.locator('#join-code').innerText()).trim()
    expect(code).toMatch(/^[A-Z0-9]+$/)
    await expect(page.locator('#join-link')).toContainText(`/join/${code}`)

    // Only Chromium grants the clipboard without a user gesture prompt. The
    // other engines take the hook's fallback path, which is a selection
    // rather than a copy and has nothing to assert.
    test.skip(browserName !== 'chromium', 'clipboard permissions are Chromium-only here')
    await context.grantPermissions(['clipboard-read', 'clipboard-write'])

    await page.locator('#copy-join-link').click()

    await expect(page.locator('#copy-join-link')).toContainText('คัดลอกแล้ว')
    const copied = await page.evaluate(() => navigator.clipboard.readText())
    expect(copied).toContain(`/join/${code}`)
  })

  test('[FR-213] the room fills up, and starting it moves everyone on', async ({
    page,
    context,
  }) => {
    const participant = await context.browser()!.newPage()
    const { email } = await registerAndSignIn(participant)

    await registerAndSignIn(page)
    await createTeam(page, 'Filling')
    await inviteTeammate(page, email)
    await page.getByRole('link', { name: /Retrospective/i }).click()
    await waitForLiveView(page)
    await createSession(page, 'Sprint 21')

    const lobbyUrl = page.url()
    await expect(page.locator('#lobby-waiting')).toBeVisible()

    await participant.goto(lobbyUrl)
    await waitForLiveView(participant)

    // The room visibly fills: the facilitator's page changes without a reload.
    await expect(page.locator('#lobby-waiting')).toHaveCount(0)
    await expect(page.locator('#lobby-room')).toContainText('0 จาก 2')

    await participant.locator('#toggle-ready').click()
    await expect(page.locator('#lobby-room')).toContainText('1 จาก 2')

    await page.locator('#start-session').click()

    // Both of them are on the board now, not only the one who pressed it.
    await expect(page.locator('#phase-bar')).toBeVisible()
    await expect(participant.locator('#phase-bar')).toBeVisible()
    await expect(participant.locator('#lobby')).toHaveCount(0)

    await participant.close()
  })
})

test.describe('the live board', () => {
  test('[FR-201] a member starts a retro and lands on its board', async ({ page }) => {
    await registerAndSignIn(page)
    await createTeam(page, 'Alpha')

    await page.getByRole('link', { name: /Retrospective/i }).click()
    await waitForLiveView(page)
    await createSession(page, 'Sprint 1')

    // It has to be started first. This used to assert the board without
    // pressing anything, which passed because a session that had not begun
    // rendered the whole board anyway — the thing the lobby exists to fix.
    await page.locator('#start-session').click()

    // เริ่ม-หยุด-ทำต่อ's three columns, and the six phases of section 4.3.
    await expect(page.locator('#board section[role="tabpanel"]')).toHaveCount(3)
    await expect(page.locator('#phase-bar li')).toHaveCount(6)
    await expect(page.locator('#join-code')).toBeVisible()
  })

  test('[FR-206] @spec-10.1 the participant follows the phase the facilitator sets', async ({
    page,
    context,
  }) => {
    const { participant } = await twoPeopleOnABoard(page, context)

    await expect(participant.locator('[aria-current="true"]').first()).toHaveText(/เช็กอิน/)

    await page.locator('#advance-phase').click()

    await expect(participant.locator('[aria-current="true"]').first()).toHaveText(/ระดมความคิด/)

    await page.locator('#phase-vote').click()
    await expect(participant.locator('[aria-current="true"]').first()).toHaveText(/โหวต/)

    await participant.close()
  })

  test('[FR-208] @spec-10.1 the participant sees the timer the facilitator started', async ({
    page,
    context,
  }) => {
    const { participant } = await twoPeopleOnABoard(page, context)

    await expect(participant.locator('#timer-remaining')).toContainText('—')

    await page.locator('#timer-300').click()
    await expect(participant.locator('#timer-remaining')).toContainText(/[45]:\d\d/)

    await page.locator('#reset-timer').click()
    await expect(participant.locator('#timer-remaining')).toContainText('—')

    await participant.close()
  })

  test('[FR-213] the ready count the facilitator sees is live', async ({ page, context }) => {
    const { participant } = await twoPeopleOnABoard(page, context)

    await expect(page.locator('#ready-count')).toContainText('0')

    await participant.locator('#toggle-ready').click()

    await expect(page.locator('#ready-count')).toContainText('1')

    await participant.close()
  })

  test('[FR-207] the facilitator hands the role over and the controls move', async ({
    page,
    context,
  }) => {
    const { participant } = await twoPeopleOnABoard(page, context)

    // The participant has no facilitator controls until the role arrives.
    await expect(participant.locator('#advance-phase')).toHaveCount(0)

    await page.locator('[id^="hand-over-"]').first().click()

    await expect(participant.locator('#advance-phase')).toBeVisible()
    await expect(page.locator('#advance-phase')).toHaveCount(0)

    await participant.close()
  })

  test('[FR-204] a member joins by code', async ({ page, context }) => {
    const { participant, boardUrl } = await twoPeopleOnABoard(page, context)

    const code = (await page.locator('#join-code').innerText()).trim()

    await participant.goto('/join')
    await waitForLiveView(participant)
    await participant.locator('#join_form input[name="join[code]"]').fill(code.toLowerCase())
    await participant.locator('#join_form button').click()

    await expect(participant).toHaveURL(boardUrl)

    await participant.close()
  })

  test('[FR-309] someone arriving late sees the board as it is now', async ({ page, context }) => {
    const { participant, boardUrl } = await twoPeopleOnABoard(page, context)
    await participant.close()

    // Changes made while nobody else is watching.
    await page.locator('#phase-vote').click()
    await page.locator('#timer-600').click()

    const latecomer = await context.browser()!.newPage()
    const { email } = await registerAndSignIn(latecomer)
    await page.goto(boardUrl.replace(/\/sessions\/\d+$/, ''))

    // Bring them into the team, then onto the board.
    await page.goto('/teams')
    await waitForLiveView(page)
    await page.locator('#teams li a').first().click()
    await waitForLiveView(page)
    await inviteTeammate(page, email)

    await latecomer.goto(boardUrl)
    await waitForLiveView(latecomer)

    await expect(latecomer.locator('[aria-current="true"]').first()).toHaveText(/โหวต/)
    await expect(latecomer.locator('#timer-remaining')).toContainText(/(9|10):\d\d/)

    await latecomer.close()
  })

  test('[FR-205] closing makes the board read-only for everyone', async ({ page, context }) => {
    const { participant } = await twoPeopleOnABoard(page, context)

    page.once('dialog', (dialog) => dialog.accept())
    await page.locator('#close-session').click()

    await expect(page.locator('#advance-phase')).toHaveCount(0)
    await expect(participant.locator('#toggle-ready')).toHaveCount(0)

    await participant.close()
  })
})
