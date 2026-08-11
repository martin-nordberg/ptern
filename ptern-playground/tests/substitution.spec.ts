// Covers documentation/ideas/playground.md §7.7 (Substitution mode): a
// success case pulled from the shared fixture corpus, and an error case
// (missing capture).

import { test, expect } from '@playwright/test'
import { apiFixture } from './fixtures'
import { sourceEditor, labeledValue } from './helpers'

test.beforeEach(async ({ page }) => {
  await page.goto('/')
  await expect(page.getByText('Ptern Playground')).toBeVisible()
})

function captureValuesInSubstitutionMode(page: import('@playwright/test').Page) {
  // Substitution mode has a single textarea (no separate input string).
  return page.locator('textarea').nth(1)
}

test('Substitution tab is disabled for a non-substitutable pattern', async ({ page }) => {
  const { pattern } = apiFixture('digit4_year') // no !substitutable annotation
  await sourceEditor(page).fill(pattern)
  await expect(page.getByText('Successful Compilation')).toBeVisible()
  await expect(page.getByRole('button', { name: 'Substitution' })).toBeDisabled()
})

test('substitute assembles a string from capture values, from a shared fixture', async ({ page }) => {
  const { pattern, cases } = apiFixture('substitute_date')
  const { captures, expect: expected } = cases.find(c => c.op === 'substitute')!

  await sourceEditor(page).fill(pattern)
  await expect(page.getByText('Successful Compilation')).toBeVisible()
  await expect(page.getByRole('button', { name: 'Substitution' })).toBeEnabled()

  await page.getByRole('button', { name: 'Substitution' }).click()
  await captureValuesInSubstitutionMode(page).fill(JSON.stringify(captures))
  await page.getByRole('button', { name: 'Test' }).click()

  await expect(labeledValue(page, 'Result')).toHaveText(expected as string)
})

test('a missing capture shows a "Missing capture" error', async ({ page }) => {
  const { pattern } = apiFixture('substitute_date')
  await sourceEditor(page).fill(pattern)
  await page.getByRole('button', { name: 'Substitution' }).click()
  await captureValuesInSubstitutionMode(page).fill('{"year": "2024"}') // month/day omitted
  await page.getByRole('button', { name: 'Test' }).click()

  await expect(labeledValue(page, 'Result')).toContainText('Missing capture:')
})

test('switching modes resets the tested state', async ({ page }) => {
  const { pattern, cases } = apiFixture('substitute_date')
  const { captures } = cases.find(c => c.op === 'substitute')!

  await sourceEditor(page).fill(pattern)
  await page.getByRole('button', { name: 'Substitution' }).click()
  await captureValuesInSubstitutionMode(page).fill(JSON.stringify(captures))
  await page.getByRole('button', { name: 'Test' }).click()
  await expect(page.getByText('Click Test to see results.')).not.toBeVisible()

  await page.getByRole('button', { name: 'Match / Replace' }).click()
  await expect(page.getByText('Click Test to see results.')).toBeVisible()
})
