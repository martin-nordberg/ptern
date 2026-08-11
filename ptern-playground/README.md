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

## Deployment

Learn more about deploying your application with the [documentations](https://vite.dev/guide/static-deploy.html)
