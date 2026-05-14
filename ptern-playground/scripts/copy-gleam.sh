#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLAYGROUND_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$PLAYGROUND_ROOT/.." && pwd)"
GLEAM_BUILD="$REPO_ROOT/ptern-gleam/build/dev/javascript"
DEST="$PLAYGROUND_ROOT/src/ptern"

echo "Building Gleam project..."
(cd "$REPO_ROOT/ptern-gleam" && gleam build)

echo "Copying Gleam output to src/ptern/..."
rm -rf "$DEST/ptern" "$DEST/gleam_stdlib" "$DEST/gleam_version"
rm -f "$DEST/prelude.mjs"
cp -r "$GLEAM_BUILD/ptern" "$DEST/"
cp -r "$GLEAM_BUILD/gleam_stdlib" "$DEST/"
cp -r "$GLEAM_BUILD/gleam_version" "$DEST/"
cp "$GLEAM_BUILD/prelude.mjs" "$DEST/"

echo "Done."
