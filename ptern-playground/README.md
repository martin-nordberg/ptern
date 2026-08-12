## Usage

This project is part of a Bun workspace (the repository root `package.json`), together with `../ptern-typescript`, whose `@ptern/tern` package is the ptern engine this playground uses. Run `bun install` from the **repository root**, not from inside `ptern-playground/` — that's what sets up the `@ptern/tern` workspace symlink.

```bash
$ bun install   # from the repository root
```

### Learn more on the [Solid Website](https://solidjs.com) and come chat with us on our [Discord](https://discord.com/invite/solidjs)

## Available Scripts

In this directory, you can run:

### `bun run dev`

Builds `@ptern/tern` (`bun run build` in `../ptern-typescript`) and then runs the app in development mode.<br>
Open [http://localhost:5173](http://localhost:5173) to view it in the browser.

### `bun run build`

Builds `@ptern/tern` first, then type-checks and builds the app for production to the `dist` folder.<br>
It correctly bundles Solid in production mode and optimizes the build for the best performance.

The build is minified and the filenames include the hashes.<br>
Your app is ready to be deployed!

### `bun run test:e2e`

Runs the end-to-end test suite (`tests/*.spec.ts`, using [Playwright](https://playwright.dev)) against a real Chromium browser. One-time setup: `bunx playwright install --with-deps chromium`.

The suite auto-starts `bun run dev` and waits for it to be ready — you don't need to start the dev server yourself first. It reuses an already-running dev server instead of starting a second one if you happen to have `bun run dev` open in another terminal.

The specs pull real patterns and expected results from `../test-fixtures/` (the same corpus `ptern-typescript`'s own engine tests use — see `tests/fixtures.ts`) where practical, rather than inventing new expected values, so the E2E layer stays anchored to the same source of truth. They intentionally cover UI *wiring* — does the app correctly call and render `@ptern/tern`'s results — not pattern-language correctness, which the engine's own 700+ fixture-driven tests already cover exhaustively.

If port 5173 is unavailable (e.g. taken by another project's dev server), set `PORT` (read by both `vite.config.ts` and `playwright.config.ts`), e.g. `PORT=5183 bun run dev` in one terminal and `PORT=5183 bun run test:e2e` in another. `vite.config.ts` sets `strictPort: true` specifically so this fails loudly and immediately if the port really is taken, rather than Vite silently binding to the next free one and leaving Playwright's health check polling the wrong URL.

**WSL2 note — `webServer` auto-spawn hang.** On WSL2 (Windows Subsystem for Linux) without a native Linux `node` binary on `PATH` (only a Windows-side `node.exe`, e.g. under `/mnt/c/...`), Playwright's own `webServer` auto-spawn — the mechanism `test:e2e` normally relies on to start `bun run dev` for you — hangs indefinitely when run via `bunx playwright test`. Reproduced even with a trivial `python3 -m http.server` standing in for the real `command`, so it's an interaction between `bunx` (running Playwright's Node-targeted CLI through Bun's own runtime instead of a real `node`) and spawning a persistent background process, not a bug in this project. Playwright's own already-running-server *detection* is unaffected and works fine. Workaround: start `bun run dev` yourself in one terminal first, then run `bun run test:e2e` (or `bunx playwright test`) in another — `reuseExistingServer` (on by default outside of `CI`) detects the already-running server and skips spawning entirely. Installing a native Linux Node.js in the WSL distro (rather than relying on `bunx`'s Bun-runtime fallback) would likely avoid this too, but hasn't been verified.

**WSL2 note — missing Chromium shared libraries.** A fresh WSL2 Ubuntu install may be missing a few shared libraries Chromium needs (`libnspr4`, `libnss3`, `libasound2t64`), since it's not built with desktop/browser packages in mind. If `bunx playwright install --with-deps chromium` can't run `apt-get install` for you (e.g. no interactive `sudo`), install them manually once: `sudo apt-get update && sudo apt-get install -y libnspr4 libnss3 libasound2t64`. After that, launching Chromium works normally with no further workaround needed.

## Deployment

Learn more about deploying your application with the [documentations](https://vite.dev/guide/static-deploy.html)
