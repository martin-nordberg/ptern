import { defineConfig, devices } from '@playwright/test'

// Overridable via PORT (see vite.config.ts) so a busy/reserved default
// port doesn't require editing config files in either place.
const port = Number(process.env.PORT) || 5173
const baseURL = `http://localhost:${port}`

export default defineConfig({
  testDir: './tests',
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  reporter: 'list',

  use: {
    baseURL,
    trace: 'retain-on-failure',
    screenshot: 'only-on-failure',
  },

  projects: [
    { name: 'chromium', use: { ...devices['Desktop Chrome'] } },
  ],

  // `bun run dev` already builds @ptern/tern first (see the build-engine
  // script) before starting Vite — no separate engine-build step needed
  // here. reuseExistingServer lets you run `bun run dev` yourself in one
  // terminal and `bun run test:e2e` in another without a port conflict —
  // and is required, not just convenient, in any environment where
  // Playwright's own webServer auto-spawn can't launch a background
  // process (observed in this project's dev sandbox specifically; see
  // ptern-playground/README.md).
  webServer: {
    command: 'bun run dev',
    url: baseURL,
    reuseExistingServer: !process.env.CI,
    timeout: 60_000,
  },
})
