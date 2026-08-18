import { expect, test, type Page } from '@playwright/test'
import { brainstormWithTwoPeople, columnIds, writeCard } from './support/board'

/**
 * Acceptance scenario 10.3, in two real browsers.
 *
 * The claim is about a boundary between two people: each spends their own
 * budget, sees their own remaining votes, and nobody — the facilitator
 * included — sees a total until the reveal. A single-client test cannot tell
 * "hidden from everyone" apart from "not rendered yet", which is why this one
 * has a second browser watching throughout.
 */

/** Merges the first two cards into a cluster and moves on to the vote phase. */
async function clusterAndVote(page: Page, columnId: string, label: string) {
  await page.locator('#phase-group').click()
  await expect(page.locator('#group_form')).toBeVisible()

  const ids = await page
    .locator(`#cards-${columnId} li`)
    .evaluateAll((nodes) => nodes.map((node) => node.id.replace('card-', '')))

  for (const id of ids.slice(0, 2)) {
    await page.locator(`#select-card-${id}`).check()
  }

  await page.locator('#group_form input[name="group[label]"]').fill(label)
  await page.locator('#group_form button').click()

  await expect(page.locator('#groups li')).toHaveCount(1)

  const groupId = (await page.locator('#groups li').first().getAttribute('id'))!.replace(
    'group-',
    '',
  )

  await page.locator('#phase-vote').click()
  await expect(page.locator('#topics-panel')).toBeVisible()

  return { groupId, looseId: ids[2] }
}

test.describe('grouping, budgeted voting and the reveal', () => {
  test('[FR-401][FR-403][FR-404] @spec-10.3 clustering and budgeted voting', async ({
    page,
    context,
  }) => {
    const { participant } = await brainstormWithTwoPeople(page, context)
    const [first] = await columnIds(page)

    await writeCard(page, first, 'Deploys are slow')
    await writeCard(page, first, 'Deploys break things')
    await writeCard(page, first, 'Good pairing')

    const { groupId, looseId } = await clusterAndVote(page, first, 'Deploys')

    // The cluster and the loose card are the two topics; the merged cards are
    // named inside the cluster rather than beside it, so the direct children
    // of the list are two and its descendants are more (FR-405).
    await expect(participant.locator('#topics > li')).toHaveCount(2)
    await expect(participant.locator(`#topic-group-${groupId}`)).toContainText('Deploys')

    // Each person's budget is their own (FR-403).
    await expect(participant.locator('#vote-remaining')).toContainText('5')
    await participant.locator(`#vote-up-group-${groupId}`).click()
    await expect(participant.locator('#vote-remaining')).toContainText('4')
    await expect(page.locator('#vote-remaining')).toContainText('5')

    await page.locator(`#vote-up-card-${looseId}`).click()

    // Nobody has a total yet — not the participant, and not the facilitator
    // who holds the reveal (FR-404).
    for (const view of [page, participant]) {
      await expect(view.locator('#votes-hidden')).toBeVisible()
      await expect(view.locator(`#topic-total-group-${groupId}`)).toHaveCount(0)
      await expect(view.locator(`#topic-total-card-${looseId}`)).toHaveCount(0)
    }

    await expect(participant.locator('#reveal-votes')).toHaveCount(0)
    await page.locator('#reveal-votes').click()

    // And now everyone does, without asking for it.
    for (const view of [page, participant]) {
      await expect(view.locator(`#topic-total-group-${groupId}`)).toBeVisible()
      await expect(view.locator(`#topic-total-card-${looseId}`)).toBeVisible()
      await expect(view.locator('#votes-hidden')).toHaveCount(0)
    }

    await participant.close()
  })

  test('[FR-402] a second vote on one topic is refused', async ({ page, context }) => {
    const { participant } = await brainstormWithTwoPeople(page, context)
    const [first] = await columnIds(page)

    await writeCard(page, first, 'Deploys are slow')
    await writeCard(page, first, 'Deploys break things')
    await writeCard(page, first, 'Good pairing')

    const { looseId } = await clusterAndVote(page, first, 'Deploys')

    await participant.locator(`#vote-up-card-${looseId}`).click()
    await expect(participant.locator('#vote-remaining')).toContainText('4')

    await participant.locator(`#vote-up-card-${looseId}`).click()

    await expect(participant.locator('#flash-error')).toBeVisible()
    await expect(participant.locator('#vote-remaining')).toContainText('4')

    await participant.close()
  })

  test('[FR-403] a vote can be taken back and returns to the budget', async ({ page, context }) => {
    const { participant } = await brainstormWithTwoPeople(page, context)
    const [first] = await columnIds(page)

    await writeCard(page, first, 'Deploys are slow')
    await writeCard(page, first, 'Deploys break things')
    await writeCard(page, first, 'Good pairing')

    const { looseId } = await clusterAndVote(page, first, 'Deploys')

    await participant.locator(`#vote-up-card-${looseId}`).click()
    await expect(participant.locator('#vote-remaining')).toContainText('4')

    await participant.locator(`#vote-down-card-${looseId}`).click()

    await expect(participant.locator('#vote-remaining')).toContainText('5')
    await expect(participant.locator(`#vote-down-card-${looseId}`)).toHaveCount(0)

    await participant.close()
  })

  test('[FR-405][FR-406][FR-407] @spec-10.4 focused discussion with a note', async ({
    page,
    context,
  }) => {
    const { participant } = await brainstormWithTwoPeople(page, context)
    const [first] = await columnIds(page)

    await writeCard(page, first, 'Deploys are slow')
    await writeCard(page, first, 'Deploys break things')
    await writeCard(page, first, 'Good pairing')

    const { groupId, looseId } = await clusterAndVote(page, first, 'Deploys')

    await participant.locator(`#vote-up-card-${looseId}`).click()
    await page.locator('#reveal-votes').click()
    await page.locator('#phase-discuss').click()

    // Topics sorted by votes, highest first (FR-405).
    await expect(participant.locator('#topics > li').first()).toHaveAttribute(
      'id',
      `topic-card-${looseId}`,
    )

    // Every screen follows the facilitator's focus (FR-406).
    await page.locator(`#focus-group-${groupId}`).click()
    await expect(participant.locator(`#topic-group-${groupId}`)).toHaveAttribute(
      'aria-current',
      'true',
    )

    // And the record of the conversation reaches them too (FR-407).
    await page.locator(`#note-group-${groupId}`).click()
    await page.locator(`#note-body-group-${groupId}`).fill('Fix the build first')
    await page.locator(`#save-note-group-${groupId}`).click()

    await expect(participant.locator(`#topic-note-group-${groupId}`)).toContainText(
      'Fix the build first',
    )

    await participant.close()
  })
})
