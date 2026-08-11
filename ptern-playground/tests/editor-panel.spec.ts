// Covers documentation/ideas/playground.md §5 (Ptern Editor Panel): compile
// status for each error class, pattern metadata, the Format button, the
// Format Options modal, and the Copy button.

import { test, expect } from '@playwright/test'
import { apiFixture, compileFixture } from './fixtures'
import { sourceEditor } from './helpers'

test.beforeEach(async ({ page }) => {
  await page.goto('/')
  await expect(page.getByText('Ptern Playground')).toBeVisible()
})

test('valid pattern compiles successfully', async ({ page }) => {
  const { pattern } = apiFixture('digit4_year')
  await sourceEditor(page).fill(pattern)
  await expect(page.getByText('Successful Compilation')).toBeVisible()
})

test('lex error shows a message', async ({ page }) => {
  const { pattern } = compileFixture('lex_error_unterminated_string')
  await sourceEditor(page).fill(pattern)
  await expect(page.getByText('Unterminated string literal')).toBeVisible()
})

test('parse error shows a message', async ({ page }) => {
  const { pattern } = compileFixture('parse_error_missing_rep_count')
  await sourceEditor(page).fill(pattern)
  await expect(page.getByText('Unexpected end of input')).toBeVisible()
})

test('semantic error shows a message', async ({ page }) => {
  const { pattern } = compileFixture('semantic_undefined_reference')
  await sourceEditor(page).fill(pattern)
  await expect(page.getByText('Undefined reference: foo')).toBeVisible()
})

test('Format button disabled on lex/parse error, enabled on semantic error', async ({ page }) => {
  const formatButton = page.getByRole('button', { name: 'Format', exact: true })

  await sourceEditor(page).fill(compileFixture('lex_error_unterminated_string').pattern)
  await expect(page.getByText('Unterminated string literal')).toBeVisible()
  await expect(formatButton).toBeDisabled()

  // A semantic error still leaves the source lexable/parsable, so
  // formatting remains available (EditorPanel.tsx's canFormat()).
  await sourceEditor(page).fill(compileFixture('semantic_undefined_reference').pattern)
  await expect(page.getByText('Undefined reference: foo')).toBeVisible()
  await expect(formatButton).toBeEnabled()
})

test('pattern metadata: min/max length and Show regex', async ({ page }) => {
  const { pattern } = apiFixture('digit4_year')
  const minLength = apiFixture('digit4_year').cases.find(c => c.op === 'minLength')!.expect as number
  const maxLength = apiFixture('digit4_year').cases.find(c => c.op === 'maxLength')!.expect as number

  await sourceEditor(page).fill(pattern)
  await expect(page.getByText('Successful Compilation')).toBeVisible()

  await expect(page.getByText('Min length')).toBeVisible()
  await expect(page.getByText('Max length')).toBeVisible()
  const table = page.locator('table')
  await expect(table).toContainText(String(minLength))
  await expect(table).toContainText(String(maxLength))

  await page.getByText('Show regex').click()
  const regexBox = page.locator('details div.font-mono')
  await expect(regexBox).toBeVisible()
  const regexText = await regexBox.textContent()
  expect(regexText).toMatch(/^\/.+\/[a-z]+$/) // "/source/flags"
})

test('Format button reformats the source in place', async ({ page }) => {
  await sourceEditor(page).fill('!case-insensitive=true\nword=%Alpha*1..?;\n{word}')
  await expect(page.getByText('Successful Compilation')).toBeVisible()

  await page.getByRole('button', { name: 'Format', exact: true }).click()
  await expect(sourceEditor(page)).toHaveValue('!case-insensitive = true\n\nword  = %Alpha * 1..? ;\n\n{word}')
})

test('Format Options modal: toggling Compact changes formatted output', async ({ page }) => {
  await sourceEditor(page).fill("( 'a' | 'b' ) * 3")
  await expect(page.getByText('Successful Compilation')).toBeVisible()

  await page.getByRole('button', { name: 'Format Options' }).click()
  // The modal's <h2> heading, not the button that opened it — both have
  // the exact text "Format Options", so getByText alone is ambiguous.
  await expect(page.getByRole('heading', { name: 'Format Options' })).toBeVisible()

  await page.getByText('Compact', { exact: true }).click()
  await page.getByRole('button', { name: 'Save' }).click()

  await expect(sourceEditor(page)).toHaveValue("('a'|'b')*3")
})

test('Format Options modal: Cancel discards changes', async ({ page }) => {
  await sourceEditor(page).fill("( 'a' | 'b' ) * 3")
  await page.getByRole('button', { name: 'Format Options' }).click()
  await page.getByText('Compact', { exact: true }).click()
  await page.getByRole('button', { name: 'Cancel' }).click()

  // Modal closed without reformatting or persisting the checkbox state.
  // (The "Format Options" *button* stays visible regardless — assert on
  // the modal's heading, which disappears when the modal closes.)
  await expect(page.getByRole('heading', { name: 'Format Options' })).not.toBeVisible()
  await page.getByRole('button', { name: 'Format', exact: true }).click()
  await expect(sourceEditor(page)).toHaveValue("( 'a' | 'b' ) * 3")
})

test('Copy button copies the source and shows confirmation', async ({ page, context }) => {
  await context.grantPermissions(['clipboard-read', 'clipboard-write'])
  const { pattern } = apiFixture('digit4_year')
  await sourceEditor(page).fill(pattern)

  await page.getByRole('button', { name: 'Copy', exact: true }).click()
  await expect(page.getByRole('button', { name: 'Copied!' })).toBeVisible()

  const clipboardText = await page.evaluate(() => navigator.clipboard.readText())
  expect(clipboardText).toBe(pattern)
})
