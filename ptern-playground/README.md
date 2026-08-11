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

If Vite's default port 5173 is unavailable, set `PORT` (read by both `vite.config.ts` and `playwright.config.ts`), e.g. `PORT=5183 bun run dev` in one terminal and `PORT=5183 bun run test:e2e` in another.

**Known sandbox limitation:** in at least one containerized dev environment this project has been developed in, Playwright's own `webServer` auto-spawn (the mechanism `test:e2e` normally relies on to start `bun run dev` for you) hung indefinitely when run via `bunx playwright test` — reproduced even with a trivial `python3 -m http.server` in place of the real `command`, and confirmed unrelated to this project's code. Playwright's own server-reuse detection is unaffected and works fine. If `bun run test:e2e` hangs at startup for you, start `bun run dev` yourself in one terminal first, then run `bun run test:e2e` (or `bunx playwright test`) in another — `reuseExistingServer` (on by default outside of `CI`) will detect the already-running server and skip spawning entirely, sidestepping whatever is wrong with process-spawning in that specific environment. This has not been observed with a real `node` binary on `PATH`; it may be specific to environments where `bunx` runs Playwright's Node-targeted CLI through Bun's own runtime instead.

## Deployment

Learn more about deploying your application with the [documentations](https://vite.dev/guide/static-deploy.html)
