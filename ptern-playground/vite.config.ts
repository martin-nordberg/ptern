import { defineConfig } from 'vite'
import solid from 'vite-plugin-solid'
import tailwindcss from '@tailwindcss/vite'

// Overridable via PORT so a busy/reserved default port doesn't require
// editing this file — playwright.config.ts reads the same variable.
const port = Number(process.env.PORT) || 5173

export default defineConfig({
  plugins: [tailwindcss(), solid()],
  // Pinned (rather than left to Vite's silent fall-back-to-next-port
  // behavior) so playwright.config.ts's webServer.url can rely on it: if
  // the port is genuinely unavailable, fail loudly instead of quietly
  // binding elsewhere and leaving Playwright's health check to time out
  // confused.
  server: {
    port,
    strictPort: true,
  },
})
