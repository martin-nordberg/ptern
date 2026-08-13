# Suggested dev container image for ptern.
#
# STATUS: proposal, living in documentation/ideas/ — see README.md in this
# folder. JDK (for ptern-kotlin) and Node.js come from devcontainer.json
# features instead of here; this Dockerfile only handles the two toolchains
# that don't have a trustworthy official feature: Gleam and Bun, plus the
# apt packages Playwright's Chromium needs at runtime.

FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04

# Bump these when the ptern-gleam/ptern-typescript toolchain moves on.
# Current as of Aug 2026; check https://github.com/gleam-lang/gleam/releases
# and https://bun.sh for newer versions before reusing this file verbatim.
ARG GLEAM_VERSION=1.18.1
ARG BUN_VERSION=1.3.14

# --- Gleam ------------------------------------------------------------
# ptern-gleam targets JavaScript only (see gleam.toml: target = "javascript",
# runtime "bun") so the Gleam compiler alone is enough here — no Erlang/OTP
# install needed, unlike a typical BEAM-targeting Gleam project.
RUN curl -fsSL -o /tmp/gleam.tar.gz \
      "https://github.com/gleam-lang/gleam/releases/download/v${GLEAM_VERSION}/gleam-v${GLEAM_VERSION}-x86_64-unknown-linux-musl.tar.gz" \
    && tar -xzf /tmp/gleam.tar.gz -C /usr/local/bin gleam \
    && rm /tmp/gleam.tar.gz \
    && gleam --version

# --- Playwright's Chromium runtime libraries ---------------------------
# Baked in at build time (root, apt-get) so `bunx playwright install chromium`
# in postCreateCommand only has to fetch the browser binary, not packages —
# see ptern-playground/README.md's "missing Chromium shared libraries" note,
# which lists this same set for a bare WSL2 Ubuntu install.
RUN apt-get update && apt-get install -y --no-install-recommends \
      libnspr4 libnss3 libasound2t64 libatk1.0-0t64 libatk-bridge2.0-0t64 \
      libcups2t64 libdrm2 libgbm1 libgtk-3-0t64 libxcomposite1 libxdamage1 \
      libxfixes3 libxrandr2 libxkbcommon0 \
    && rm -rf /var/lib/apt/lists/*

# --- Bun ----------------------------------------------------------------
# Installed for the non-root `vscode` user that devcontainer.json's
# remoteUser selects (the base image provides this user with passwordless
# sudo already configured).
USER vscode
RUN curl -fsSL https://bun.sh/install | BUN_INSTALL="/home/vscode/.bun" bash -s "bun-v${BUN_VERSION}"
ENV BUN_INSTALL="/home/vscode/.bun"
ENV PATH="${BUN_INSTALL}/bin:${PATH}"

RUN bun --version
