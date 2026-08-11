// Covers documentation/ideas/playground.md §7.3-7.6 (Match / Replace mode):
// boolean badges, occurrence results, and replacement results, including
// an invalid replacement value and array replacement inside a repetition.
//
// Replacement *errors* and array replacement aren't in the shared
// test-fixtures/ corpus (they're TypeScript-only scenarios — see
// ptern-typescript/test/driver.test.ts's own inline, non-fixture tests for
// the same reason) so those two cases are hand-written here rather than
// pulled from a fixture, matching how the engine's own suite tests them.

import { test, expect } from '@playwright/test'
import { apiFixture } from './fixtures'
import { sourceEditor, labeledValue } from './helpers'

test.beforeEach(async ({ page }) => {
  await page.goto('/')
  await expect(page.getByText('Ptern Playground')).toBeVisible()
})

function inputString(page: import('@playwright/test').Page) {
  return page.locator('textarea').nth(1)
}

function captureValues(page: import('@playwright/test').Page) {
  return page.locator('textarea').nth(2)
}

test('boolean badges and occurrence results, from a shared fixture', async ({ page }) => {
  const { pattern } = apiFixture('digit4_year')
  const matchFirstIn = apiFixture('digit4_year').cases.find(c => c.op === 'matchFirstIn')!
  const input = matchFirstIn.input as string
  const expected = matchFirstIn.expect as { index: number; length: number; captures: Record<string, string> }
  const matchedText = input.slice(expected.index, expected.index + expected.length)

  await sourceEditor(page).fill(pattern)
  await inputString(page).fill(input)
  await page.getByRole('button', { name: 'Test' }).click()

  await expect(labeledValue(page, 'Matches all')).toContainText('No')
  await expect(labeledValue(page, 'Matches in')).toContainText('Yes')

  const firstMatch = labeledValue(page, 'First match')
  await expect(firstMatch).toContainText(JSON.stringify(matchedText))
  for (const [name, value] of Object.entries(expected.captures)) {
    await expect(firstMatch).toContainText(`"${name}":"${value}"`)
  }
})

test('replace (first) applies the given capture value', async ({ page }) => {
  const { pattern } = apiFixture('digit4_year')
  await sourceEditor(page).fill(pattern)
  await inputString(page).fill('year 2024 end')
  await captureValues(page).fill('{"year": "2099"}')
  await page.getByRole('button', { name: 'Test' }).click()

  await expect(labeledValue(page, 'Replace (first)')).toHaveText('year 2099 end')
})

test('an invalid replacement value shows InvalidReplacementValue', async ({ page }) => {
  const { pattern } = apiFixture('digit4_year')
  await sourceEditor(page).fill(pattern)
  await inputString(page).fill('2024')
  await captureValues(page).fill('{"year": "abc"}')
  await page.getByRole('button', { name: 'Test' }).click()

  await expect(labeledValue(page, 'Replace (all)')).toContainText('InvalidReplacementValue')
})

test('array replacement fills each iteration of a repeated capture', async ({ page }) => {
  await sourceEditor(page).fill(
    "!replacements-ignore-matching = true\n" +
    "%Any excluding ',' * 1..100 as col (',' %Any excluding ',' * 1..100 as col) * 0..20",
  )
  await expect(page.getByText('Successful Compilation')).toBeVisible()
  await inputString(page).fill('alice,bob,carol')
  await captureValues(page).fill('{"col": ["ALICE", "BOB", "CAROL"]}')
  await page.getByRole('button', { name: 'Test' }).click()

  await expect(labeledValue(page, 'Replace (first)')).toHaveText('ALICE,BOB,CAROL')
})

test('editing the input after Test marks results as stale', async ({ page }) => {
  const { pattern } = apiFixture('digit4_year')
  await sourceEditor(page).fill(pattern)
  await inputString(page).fill('year 2024 end')
  await page.getByRole('button', { name: 'Test' }).click()
  await expect(page.getByText('Click Test to see results.')).not.toBeVisible()

  await inputString(page).fill('year 2025 end')
  // Stale results are muted (opacity-50 on a wrapping div), not hidden —
  // the previous "2024" result stays visible but dimmed until Test runs again.
  await expect(page.locator('.opacity-50')).toBeVisible()
})
