// Small page-interaction helpers shared across specs, for the handful of
// DOM shapes (label -> sibling value) that recur across EditorPanel.tsx
// and TabContent.tsx.

import type { Page } from '@playwright/test'

export function sourceEditor(page: Page) {
  return page.locator('textarea').first()
}

// A label div ("Matches in", "Replace (first)", ...) followed by its
// value/result as the next sibling element.
export function labeledValue(page: Page, label: string) {
  return page.getByText(label, { exact: true }).locator('xpath=following-sibling::*[1]')
}
