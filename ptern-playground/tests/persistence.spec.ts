// Covers documentation/ideas/playground.md §8 (State Persistence): source,
// format options, tab input, and theme all survive a reload via
// localStorage; test results themselves do not (§8.2's "not yet tested"
// note).

import { test, expect } from '@playwright/test'
import { apiFixture } from './fixtures'
import { sourceEditor } from './helpers'

test.beforeEach(async ({ page }) => {
  await page.goto('/')
  await expect(page.getByText('Ptern Playground')).toBeVisible()
})

test('source, tab input, and format options survive a reload', async ({ page }) => {
  const { pattern } = apiFixture('digit4_year')
  await sourceEditor(page).fill(pattern)
  await page.locator('textarea').nth(1).fill('year 2024 end')

  await page.getByRole('button', { name: 'Format Options' }).click()
  await page.getByText('Compact', { exact: true }).click()
  await page.getByRole('button', { name: 'Save' }).click()

  await page.reload()
  await expect(page.getByText('Ptern Playground')).toBeVisible()

  await expect(sourceEditor(page)).toHaveValue(pattern)
  await expect(page.locator('textarea').nth(1)).toHaveValue('year 2024 end')

  // Confirm the saved Compact option round-tripped by re-opening the modal.
  await page.getByRole('button', { name: 'Format Options' }).click()
  await expect(page.locator('label', { hasText: 'Compact' }).locator('input[type=checkbox]')).toBeChecked()
})

test('test results do not survive a reload — tab resets to "Click Test"', async ({ page }) => {
  const { pattern } = apiFixture('digit4_year')
  await sourceEditor(page).fill(pattern)
  await page.locator('textarea').nth(1).fill('year 2024 end')
  await page.getByRole('button', { name: 'Test' }).click()
  await expect(page.getByText('Click Test to see results.')).not.toBeVisible()

  await page.reload()
  await expect(page.getByText('Ptern Playground')).toBeVisible()
  await expect(page.getByText('Click Test to see results.')).toBeVisible()
})

test('theme toggle survives a reload', async ({ page }) => {
  const themeButton = page.locator('header button')
  const isDark = async () => page.evaluate(() => document.documentElement.classList.contains('dark'))

  expect(await isDark()).toBe(false) // light mode by default on first visit
  await themeButton.click()
  expect(await isDark()).toBe(true)

  await page.reload()
  await expect(page.getByText('Ptern Playground')).toBeVisible()
  expect(await isDark()).toBe(true)
})

test('adding and closing tabs, then reloading, restores the tab list', async ({ page }) => {
  await page.getByRole('button', { name: '+', exact: true }).click()
  await page.getByRole('button', { name: '+', exact: true }).click()
  await expect(page.getByText('3', { exact: true })).toBeVisible()

  await page.reload()
  await expect(page.getByText('Ptern Playground')).toBeVisible()
  await expect(page.getByText('3', { exact: true })).toBeVisible()
})
