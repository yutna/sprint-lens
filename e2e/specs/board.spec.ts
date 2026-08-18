import { expect, test } from '@playwright/test'
import { brainstormWithTwoPeople, columnIds, writeCard } from './support/board'

/**
 * Acceptance scenario 10.2, plus the card behaviour it rests on.
 *
 * Blind and anonymous modes are promises the product makes to the people in
 * the room, and a promise that only holds in a unit test is not one you can
 * make. So these run in two real browsers: what the facilitator's DOM
 * actually contains is the whole question.
 */

test.describe('brainstorm with blind and anonymous modes', () => {
  test('[FR-209][FR-210] @spec-10.2 hidden drafting without authorship', async ({
    page,
    context,
  }) => {
    const { participant, account } = await brainstormWithTwoPeople(page, context, {
      blind: true,
      anonymous: true,
    })

    const [first] = await columnIds(page)

    await writeCard(page, first, 'We shipped on Tuesday')
    await writeCard(participant, first, 'Standups ran long')

    // Each sees their own and nothing else — not even the facilitator, who
    // has every other power on this board.
    await expect(page.locator(`#cards-${first} li`)).toHaveCount(1)
    await expect(page.locator('#board')).toContainText('We shipped on Tuesday')
    await expect(page.locator('#board')).not.toContainText('Standups ran long')

    await expect(participant.locator(`#cards-${first} li`)).toHaveCount(1)
    await expect(participant.locator('#board')).toContainText('Standups ran long')
    await expect(participant.locator('#board')).not.toContainText('We shipped on Tuesday')

    await expect(page.locator('#blind-notice')).toBeVisible()
    await expect(participant.locator('#reveal-cards')).toHaveCount(0)

    await page.locator('#reveal-cards').click()

    // After the reveal everyone has everything, and nobody has a name.
    for (const view of [page, participant]) {
      await expect(view.locator(`#cards-${first} li`)).toHaveCount(2)
      await expect(view.locator('#board')).toContainText('We shipped on Tuesday')
      await expect(view.locator('#board')).toContainText('Standups ran long')
      await expect(view.locator('#board')).not.toContainText(account.displayName)
      await expect(view.locator('#board li[id^="card-"]').first()).toContainText('ไม่ระบุตัวตน')
    }

    await participant.close()
  })

  test('[FR-306] a card written by one person reaches the other', async ({ page, context }) => {
    const { participant } = await brainstormWithTwoPeople(page, context)
    const [first] = await columnIds(page)

    await writeCard(page, first, 'Deploys got faster')

    await expect(participant.locator(`#cards-${first} li`)).toHaveCount(1)
    await expect(participant.locator('#board')).toContainText('Deploys got faster')

    await participant.close()
  })

  test('[FR-301] the author edits their own card and everyone sees it', async ({
    page,
    context,
  }) => {
    const { participant } = await brainstormWithTwoPeople(page, context)
    const [first] = await columnIds(page)

    await writeCard(participant, first, 'Frist draft')

    const card = participant.locator(`#cards-${first} li`).first()
    const cardId = (await card.getAttribute('id'))!.replace('card-', '')

    await participant.locator(`#edit-card-button-${cardId}`).click()
    await participant.locator(`#edit-card-${cardId} textarea`).fill('First draft')
    await participant.locator(`#save-card-${cardId}`).click()

    await expect(page.locator('#board')).toContainText('First draft')

    // The facilitator may remove someone else's card but never rewrite it
    // (FR-301 against FR-302).
    await expect(page.locator(`#edit-card-button-${cardId}`)).toHaveCount(0)

    await participant.close()
  })

  test('[FR-302] the facilitator removes someone else’s card', async ({ page, context }) => {
    const { participant } = await brainstormWithTwoPeople(page, context)
    const [first] = await columnIds(page)

    await writeCard(participant, first, 'Off topic')
    await expect(page.locator(`#cards-${first} li`)).toHaveCount(1)

    const cardId = (await page.locator(`#cards-${first} li`).first().getAttribute('id'))!.replace(
      'card-',
      '',
    )

    page.once('dialog', (dialog) => dialog.accept())
    await page.locator(`#delete-card-${cardId}`).click()

    await expect(participant.locator(`#cards-${first} li`)).toHaveCount(0)

    await participant.close()
  })

  test('[FR-303][FR-305] a tapped move puts the card in the same place for everyone', async ({
    page,
    context,
  }) => {
    const { participant } = await brainstormWithTwoPeople(page, context)
    const [first, second] = await columnIds(page)

    await writeCard(page, first, 'Belongs in stop')

    const cardId = (await page.locator(`#cards-${first} li`).first().getAttribute('id'))!.replace(
      'card-',
      '',
    )

    await page.locator(`#move-card-${cardId}-to-${second}`).click()

    for (const view of [page, participant]) {
      await expect(view.locator(`#cards-${first} li`)).toHaveCount(0)
      await expect(view.locator(`#cards-${second} li`)).toHaveCount(1)
    }

    await participant.close()
  })

  test('[FR-914] a card can be written and moved without a mouse', async ({ page, context }) => {
    const { participant } = await brainstormWithTwoPeople(page, context)
    const [first, second] = await columnIds(page)

    // Typed and submitted from the keyboard alone. The Add control is
    // pressed rather than tabbed to: whether Tab reaches a button is a
    // browser setting (Safari's is off by default), while whether the button
    // responds to Enter is what FR-914 is actually about.
    await page.locator(`#card-text-${first}`).focus()
    await page.keyboard.type('Typed, not clicked')
    await page.locator(`#add-card-${first}`).press('Enter')

    await expect(page.locator(`#cards-${first} li`)).toHaveCount(1)

    const cardId = (await page.locator(`#cards-${first} li`).first().getAttribute('id'))!.replace(
      'card-',
      '',
    )

    // The move control is a real button, so it takes focus and Enter — which
    // is the whole point of rendering it as one rather than as a drag handle.
    const move = page.locator(`#move-card-${cardId}-to-${second}`)
    await move.focus()
    await expect(move).toBeFocused()
    await move.press('Enter')

    await expect(participant.locator(`#cards-${second} li`)).toHaveCount(1)

    await participant.close()
  })

  test('[FR-306] the writing box counts down from five hundred', async ({ page, context }) => {
    const { participant } = await brainstormWithTwoPeople(page, context)
    const [first] = await columnIds(page)

    await expect(page.locator(`#card-counter-${first}`)).toHaveText('0/500')

    await page.locator(`#card-text-${first}`).fill('x'.repeat(12))
    await expect(page.locator(`#card-counter-${first}`)).toHaveText('12/500')

    // The browser stops at the limit rather than letting the server say no.
    await page.locator(`#card-text-${first}`).fill('y'.repeat(600))
    await expect(page.locator(`#card-text-${first}`)).toHaveValue('y'.repeat(500))

    await participant.close()
  })
})
