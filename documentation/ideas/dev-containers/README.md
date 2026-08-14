# Dev container for ptern: WebStorm (Windows laptop) → Docker (Kubuntu desktop)

**Status:** planning document / proposal. Nothing here is wired up yet — `devcontainer.json`
and `Dockerfile` in this folder are drafts to review and adapt, not a live `.devcontainer/`.
See [Adopting this](#adopting-this) for what promoting them involves, and
[TBD](#tbd) for open questions.

## Goal

Run all ptern development — editing, building, testing, the Playground dev server, Playwright
E2E — inside a single Docker container that lives on a networked Kubuntu desktop, while you
drive it from WebStorm on a Windows laptop. The laptop keeps its Windows install (and WSL2)
untouched as a thin client; the desktop does the compiling.

```
 Windows laptop                                    Kubuntu desktop (LAN)
┌───────────────────────────────┐                 ┌───────────────────────────────┐
│ WebStorm                       │                 │ sshd                          │
│  └─ Remote Development          │  IDE protocol   │ Docker Engine                 │
│      (JetBrains Client,          │  over SSH,     │  └─ ptern dev container       │
│       talks to a backend          │  relayed       │      ├─ backend IDE process   │
│       IDE that runs inside         │  through WSL2 │      │  (WebStorm "backend")  │
│       the container)                │◄─────────────┤      ├─ gleam, bun, JDK 25,   │
│                                     │               │      │  Go, Rust, Python,     │
│ WSL2                                │   SSH         │      │  Gradle wrapper,       │
│  └─ docker CLI, active context ─────┼──────────────►│      │  Playwright/Chromium   │
│      "ptern-devbox" → ssh://kubuntu │               │      └─ /workspaces/ptern     │
│      (see "Where WSL2 fits in")      │              │          (repo clone, lives   │
└───────────────────────────────┘                    │          on this machine)     │
                                                       └───────────────────────────────┘
```

The key mental model: WebStorm's "Dev Containers" feature is really two things glued
together — (1) a Docker connection from the laptop to a machine that has a Docker daemon, and
(2) once there, a normal devcontainer.json build+attach, with a full IDE backend process
running *inside* the container and a lightweight "JetBrains Client" on the laptop rendering
its UI. Your keystrokes go over that connection; the compiling, indexing, and test-running all
happen on the Kubuntu box. What's specific to this setup: the Docker connection in (1) is
provided by WSL2's `docker` CLI, itself pointed at the Kubuntu box over SSH via a Docker
*context* — not by any Docker install on Windows itself. See [Part
2](#part-2--windows-laptop-point-webstorms-docker-connection-at-wsl2) for why that's the shape
and [TBD](#tbd) for the one thing about it that needs confirming hands-on.

## Why this shape, and where WSL2 fits in

- **All the toolchains live in one place, once.** ptern is more polyglot than a first glance
  at `CLAUDE.md` suggests, and getting more so: Gleam+Bun (`ptern-gleam`), TypeScript+Bun
  (`ptern-typescript`), Solid.js+Vite+Tailwind+Playwright (`ptern-playground`), Kotlin/JVM+Gradle
  (`ptern-kotlin`), and — planned, not yet in the repo — Go, Rust, and Python 3 ports. Installing
  and version-pinning seven toolchains on a Windows laptop (even via WSL2) is real ongoing
  maintenance; doing it once in an image on a beefier desktop is less work over time and gives
  you a disposable, reproducible environment. It also means adding each new port later is a
  `devcontainer.json`/`Dockerfile` edit, not a fresh round of laptop setup.
- **Compute and disk.** A gaming/workstation-class Kubuntu desktop is presumably beefier than
  the laptop — Gradle/JVM builds, a Rust `cargo build`, and a Chromium install all appreciate
  that, and it's one machine's disk absorbing seven toolchains' worth of caches instead of the
  laptop's.
- **WSL2's role here is load-bearing, but narrow.** It is **not** where the container runs or
  where the repo is cloned — that's still the Kubuntu box, for the compute/disk reasons above,
  and to sidestep the WSL2 Playwright issue noted below. What it *is*: the one piece of Linux
  userland on the laptop with a `docker` CLI already on it, which is exactly what WebStorm
  needs to reach a Docker daemon it isn't running locally. Pointing WebStorm's Docker
  connection at WSL2 (Part 2) means Windows itself never needs Docker installed at all — no
  Docker Desktop, no native `docker.exe`.
- **This also sidesteps a WSL2 issue you've already hit.** `ptern-playground/README.md`
  documents a WSL2-specific hang: Playwright's `webServer` auto-spawn deadlocks under `bunx`
  when there's no native Linux `node` binary on `PATH`, plus a handful of missing Chromium
  shared libraries on a bare WSL2 Ubuntu install. A real Linux container on the Kubuntu box
  isn't WSL2, so the *specific* WSL2 interaction shouldn't apply — but see the
  [TBD](#tbd) item on verifying that, since the README's own wording ("not a bug in this
  project") leaves open whether the `bunx`-spawns-a-process half of it could still occur.
  The suggested `devcontainer.json` installs a real Node.js binary as a hedge either way.

## Where Claude can help

Called out inline below where most relevant, and summarized here:

- **Keeping the pinned versions current.** `Dockerfile` pins exact Gleam and Bun versions;
  `devcontainer.json` pins a JDK major version. Ask Claude to check these against
  `ptern-gleam/gleam.toml`, `ptern-gleam/manifest.toml`, `ptern-kotlin/build.gradle.kts`, and
  upstream releases periodically, and bump them. Once `ptern-go`/`ptern-rust`/`ptern-python`
  exist, the same applies to their now-`"latest"` feature versions — ask Claude to pin those
  to whatever `go.mod`/`Cargo.toml`/`pyproject.toml` each port ends up specifying.
- **First-connection debugging.** SSH/Docker-context/Gateway-log failures during initial setup
  are exactly the kind of "read the error, check the obvious things, propose a fix" loop
  Claude is good at — paste the error from WebStorm's connection log or `docker context`
  output.
- **A unifying task runner.** Three build tools already (`bun`, `gleam`, `./gradlew`), with
  `go`/`cargo`/`pytest` on the way, means an ever-growing set of command vocabularies. If that
  friction is annoying in daily use, ask Claude to draft a root `Justfile` or `Makefile` with
  common targets (`test`, `test-gleam`, `test-kotlin`, `test-playground`, `dev`) — a good
  `documentation/ideas/` follow-up in its own right, and one worth waiting on until the new
  ports actually land rather than guessing their command shapes now.
- **Scaffolding each new port's devcontainer wiring.** When `ptern-go`/`ptern-rust`/
  `ptern-python` actually land, ask Claude to update this guide's `devcontainer.json` in the
  same PR/commit: pin the feature version, add the real `postCreateCommand` priming step, and
  add its test command to [Day-to-day workflow](#day-to-day-workflow) — keeping the doc in
  sync with the repo rather than drifting.
- **Running inside the container.** If you install the `claude` CLI in the image too (see
  [TBD](#tbd)), Claude Code can act directly on the Kubuntu-side checkout, which is handy for
  anything that needs the full toolchain (running `gleam test` or `./gradlew test` itself)
  rather than reasoning about it from outside.

## Part 1 — Kubuntu desktop: install Docker + SSH

Run these on the Kubuntu box itself (physically, or via any SSH session you already have to
it).

```sh
# Docker Engine (official repo, not the Ubuntu-archive docker.io package)
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Run docker without sudo
sudo usermod -aG docker "$USER"
newgrp docker          # or just log out/in
docker run hello-world # sanity check
```

```sh
# SSH server, so the laptop can reach this box
sudo apt-get install -y openssh-server
sudo systemctl enable --now ssh

# If ufw is active, allow it
sudo ufw allow OpenSSH

# Note how to address this machine from the laptop
hostname -I     # LAN IP(s)
hostname        # short hostname — often reachable as <hostname>.local via mDNS
                 # (Kubuntu desktops normally have avahi-daemon running already;
                 # confirm with `systemctl status avahi-daemon`)
```

Clone the repo directly on this machine — not on the laptop, and not through the Gateway
"clone from VCS" flow (that flow is meant for sources that *aren't* already on the target
host; you already have this repo, so save the extra hop):

```sh
mkdir -p ~/code && cd ~/code
git clone <your-remote-url-for-ptern> ptern
```

## Part 2 — Windows laptop: point WebStorm's Docker connection at WSL2

You already have a Docker CLI in WSL2 and specifically don't want one added to Windows itself
(no Docker Desktop, no native `docker.exe`). That's compatible with this whole plan —
JetBrains' Docker tooling has a first-class "WSL" connection type that shells out to a chosen
WSL distro's own `docker` command rather than requiring one on Windows. All of the following
happens in your WSL2 shell; nothing installs on the Windows side.

**SSH key**, generated in WSL2 (it's WSL2's `docker` CLI that will actually be dialing out to
the Kubuntu box, so it needs its own trusted key — the Windows-native OpenSSH client is not
part of this path):

```sh
# in WSL2
ssh-keygen -t ed25519 -C "you@example.com (wsl2-docker-relay)"
ssh-copy-id <kubuntu-user>@<kubuntu-host>
ssh <kubuntu-user>@<kubuntu-host>   # sanity check — should now log in with no password prompt
```

**Docker context**, pointed at the Kubuntu box over that SSH connection, made the *default*
context so any invocation of `docker` in this WSL distro — including a non-interactive one
WebStorm makes on your behalf — uses it without needing extra flags or env vars:

```sh
# still in WSL2
docker context create ptern-devbox --docker "host=ssh://<kubuntu-user>@<kubuntu-host>"
docker context use ptern-devbox
docker version   # confirms it reached the *remote* daemon: look for a populated Server: section
```

**In WebStorm** (native Windows app): **Settings → Build, Execution, Deployment → Docker → +**,
choose connection type **WSL**, and pick the distro you just set up. Apply, then check the
**Services** tool window's Docker section — it should show the Kubuntu box's containers/images
(empty is fine at this point), confirming WebStorm is really reaching the remote engine through
WSL2 and not a local one.

Later, in the Dev Containers wizard (Part 3), you'll pick this same WSL-based connection
instead of configuring a separate SSH-based one — one Docker connection, one hop through WSL2,
one SSH leg from there to the Kubuntu box.

## Part 3 — First connection, in WebStorm

1. Close any open project so you're on WebStorm's **Welcome Screen** (Dev Containers only
   shows up there, not while a project is open).
2. **Remote Development → Dev Containers → New Dev Container**.
3. In the Docker connection field, select the **WSL**-type connection you configured in
   Part 2 (it should already be registered from the Settings step, so it's just a dropdown
   pick here — no new SSH setup in this dialog).
4. Choose **existing sources** (not "from VCS") and give the path to the repo on the Kubuntu
   box: `/home/<kubuntu-user>/code/ptern`.
5. For the devcontainer config path: while this file is still living under
   `documentation/ideas/dev-containers/`, point explicitly at
   `documentation/ideas/dev-containers/devcontainer.json` (WebStorm's dialog has a field for
   this — it isn't limited to the default `.devcontainer/devcontainer.json` location). Once
   [adopted](#adopting-this) at the standard path, this step becomes unnecessary — it'll
   auto-detect.
6. Confirm the JetBrains backend is **WebStorm** (the suggested `devcontainer.json` hints this
   via `customizations.jetbrains.backend`, but double-check the dropdown — see the
   [Kotlin caveat](#caveat-webstorm-and-kotlin) below).
7. **Build Container and Continue.** First build downloads/compiles everything (JDK feature,
   Node feature, Gleam, Bun, Chromium's apt libs) and can take several minutes; rebuilds after
   that are fast because of the cache volumes in `devcontainer.json`.
8. Once it opens, a JetBrains Client window on your laptop is now driving a full WebStorm
   backend process running inside the container on the Kubuntu box, with the repo mounted at
   `/workspaces/ptern`.

## Caveat: WebStorm and Kotlin

WebStorm is a JavaScript/TypeScript-focused IDE — it does not have Kotlin/Gradle language
support the way IntelliJ IDEA does (no Kotlin syntax highlighting, no Gradle project import,
no run-gutter-icons for `ptern-kotlin/src`). Inside this dev container you can still build and
test `ptern-kotlin` perfectly well from the integrated terminal (`cd ptern-kotlin &&
./gradlew test`), but you won't get IDE-assisted Kotlin editing.

If/when `ptern-kotlin` needs real day-to-day editing, the fix isn't a different container —
it's a **second Gateway connection to the same host, with IntelliJ IDEA as the backend**
instead of WebStorm (Gateway supports having different IDE backends attached to the same or
different dev containers). Left as a [TBD](#tbd) below rather than designed in, since it's not
needed until it's needed.

## Day-to-day workflow

Everything below runs in WebStorm's integrated terminal, which is a real terminal *inside the
container* (so on the Kubuntu box, not Windows and not WSL2):

```sh
# Gleam
cd ptern-gleam && gleam test
cd ptern-gleam && gleam build

# TypeScript engine
cd ptern-typescript && bun test

# Playground (dev server + E2E)
bun run dev              # from ptern-playground/, or `bun run --cwd ptern-playground dev`
bun run test:e2e         # from ptern-playground/

# Kotlin
cd ptern-kotlin && ./gradlew test

# Go, Rust, Python — once each port exists (not in the repo yet)
cd ptern-go && go test ./...
cd ptern-rust && cargo test
cd ptern-python && pytest
```

The Vite dev server's port (5173) is auto-forwarded per `devcontainer.json`; WebStorm will
prompt to open it in a local Windows browser tab when it comes up.

For editor-driven runs, add WebStorm **Shell Script** run configurations for the commands
above (Run → Edit Configurations → **+** → Shell Script, working directory set per-module) —
`gleam` and `gradlew` aren't npm scripts, so they won't show up in WebStorm's automatic
npm-scripts panel the way `ptern-typescript`'s and `ptern-playground`'s `bun run` scripts will.

## Adopting this

To go from "proposal" to "the repo's real dev container":

1. `mkdir .devcontainer && git mv documentation/ideas/dev-containers/devcontainer.json documentation/ideas/dev-containers/Dockerfile .devcontainer/`
2. Drop the "STATUS: proposal" header comments in both files.
3. Re-verify the pinned Gleam/Bun/JDK versions are still current (see
   [Where Claude can help](#where-claude-can-help)).
4. Redo the WebStorm "existing sources" step pointing at the default
   `.devcontainer/devcontainer.json` — no explicit path override needed at that point.
5. Leave this `README.md` behind in `documentation/ideas/dev-containers/` as the human-facing
   setup guide, or fold its non-obsolete parts into a top-level `CONTRIBUTING.md` — whichever
   this repo's docs conventions prefer at the time.

## TBD

Open questions this document doesn't resolve:

- **LAN addressing for the Kubuntu box.** Plain LAN IP, mDNS `.local` hostname, a static DHCP
  reservation, or a Tailscale/VPN hostname (useful if the laptop ever leaves the LAN, e.g.
  working from elsewhere)? Affects `<kubuntu-host>` throughout Part 2's `ssh-copy-id` and
  `docker context create` commands.
- **Does WebStorm's Dev Containers wizard actually offer the WSL-type Docker connection, not
  just the general Docker Settings page?** Part 2/3 assume the "WSL" connection type
  registered under Settings → Docker is also selectable from the Dev Containers wizard's
  connection dropdown — plausible (they appear to share the same connection registry) but not
  hands-on verified. **Fallback if not:** a one-line `docker.cmd` on Windows `PATH` that shells
  out to `wsl.exe -d <distro> -- docker %*` presents as a native `docker.exe` to anything that
  needs one, without installing Docker Desktop or a real Windows Docker binary — the one
  compromise that might be needed if the wizard insists on a native-looking executable. Try
  the no-shim path first.
- **Does the JetBrains Client ↔ backend-IDE protocol traffic itself also ride the WSL2→SSH
  relay, or does Gateway open a second, separate connection to the Kubuntu box for that?** If
  the latter, that second hop would need its own SSH trust from *somewhere* Windows-native can
  reach — confirm on first connection; Part 2/3 as written assume it doesn't.
- **Does the WSL2 `bunx`/Playwright `webServer` hang reproduce inside this container?**
  Untested. If it does, bake the workaround (`bun run dev` in one terminal, `test:e2e` in
  another) into a checked-in WebStorm run configuration rather than relying on memory.
- **Second backend for Kotlin editing.** Add an IntelliJ IDEA Gateway connection alongside the
  WebStorm one now, or defer until `ptern-kotlin` sees real active development?
- **Claude Code inside the container.** Install the `claude` CLI in the image (so it can act
  directly on the Kubuntu-side checkout, with the full toolchain available) — worth it, or
  keep Claude Code laptop-side only, working through the same terminal a human would?
- **SSH hardening.** This makes the Kubuntu desktop a standing SSH endpoint on the LAN.
  Worth disabling password auth (key-only, which Part 2 already sets up in practice) and/or
  `fail2ban`, or is LAN-only exposure enough as-is?
- **Exact WebStorm menu wording.** Part 3's steps are current as of WebStorm 2026.2's public
  docs; JetBrains has moved this UI before and will again — sanity-check menu names against
  whatever version is actually installed the first time through.
- **Unifying task runner** (`Justfile`/`Makefile` across `bun`/`gleam`/`gradlew`, soon
  `go`/`cargo`/`pytest`) — worth doing at all, and if so, is it in scope for this document or a
  separate `documentation/ideas/` proposal?
- **Go/Rust/Python toolchain specifics, once each port exists.** Exact language versions to
  pin (left on feature default `"latest"` for now, deliberately — see
  [Where Claude can help](#where-claude-can-help)); for Python specifically, which packaging
  tool (`pip`, `poetry`, `uv`) — affects both the `python` feature's options and the
  `postCreateCommand` priming step sketched in `devcontainer.json`.
