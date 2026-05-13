# Ptern Playground — Feature Specification

**Version:** 0.1 (Draft)
**Date:** 2026-05-08

---

## 1. Overview

The Ptern Playground is a browser-based interactive environment for writing, formatting, and testing Ptern patterns without writing host-language code. It depends only on the transpiled JavaScript output of the Gleam implementation and runs entirely client-side.

The playground is a self-contained project located in the `ptern-playground/` subdirectory of the repository, alongside `ptern-gleam/`. It consumes the compiled output of `ptern-gleam/` as a local dependency.

---

## 2. Technology Stack

| Layer | Technology |
|-------|------------|
| UI framework | SolidJS |
| Styling | TailwindCSS |
| Build tool | Vite |
| Dev runtime | Bun |
| Ptern engine | Transpiled Gleam output (ES module) |

The playground imports the compiled Gleam output as a plain ES module and calls the public Ptern API directly in the browser. No server is required at runtime.

### 2.1 Gleam Output Integration

The compiled Gleam JavaScript is not imported directly from `ptern-gleam/build/`; instead it is copied into `ptern-playground/src/ptern/` as part of the dev/build script. This keeps the playground project self-contained within Vite's project root. The copy includes the `ptern` package output and all transitive Gleam stdlib dependencies.

### 2.2 Dev and Build Script

A single combined script (e.g. `bun run dev`) performs the following steps in order:

1. Run `gleam build` in `ptern-gleam/` to produce the compiled JavaScript output.
2. Copy the relevant output files into `ptern-playground/src/ptern/`.
3. Start the Vite dev server.

The production build script follows the same steps 1–2, then runs `vite build` in place of step 3.

---

## 3. Application State

The following state is maintained by the application:

| State item | Type | Persisted |
|------------|------|-----------|
| Ptern source text | `String` | TODO §9.1 |
| Compiled ptern or compile error | `Result(Ptern, CompileError)` | Derived |
| Format options | `FormatOptions` | Local storage |
| Test tabs | `List(TestTab)` | TODO §9.1 |
| Active tab index | `Int` | Session only |

A `TestTab` contains:
- A name string (TODO §9.2)
- An input string for matching
- A replacement values JSON string (raw text, may be invalid)
- A parsed replacement dict or JSON parse error (derived)

---

## 4. Layout

The page is divided into two main sections, stacked vertically on narrow viewports and side-by-side on wide viewports:

1. **Left / top panel** — Ptern editor and compile output (§5)
2. **Right / bottom panel** — Test case tabs (§6)

The layout switches from stacked to side-by-side at Tailwind's `2xl` breakpoint (1536px).

### 4.1 Title Area

A header row showing the application name and a link to the Ptern documentation. No interactive controls in this area.

---

## 5. Ptern Editor Panel

### 5.1 Source Editor

A multi-line text area for entering the Ptern source string.

**Evaluation timing:** The ptern is compiled on every keystroke (debounced). Test results within each tab are not updated automatically; they are produced by clicking a **Test** button inside the tab (§7.1). When the ptern source or the tab's replacement values change after a test has been run, the existing results are grayed out to indicate they are stale, until the Test button is clicked again.

### 5.2 Compile Status

Displayed below or alongside the editor. Shows one of:

- **OK** — the ptern compiled successfully
- **Lex error** — the offending character and its position in the source
- **Parse error** — a human-readable message (e.g. "unexpected token '|', expected expression")
- **Semantic errors** — a list of all semantic errors, each with a description

Errors are shown as plain text messages only. No inline highlighting or line/column position information is provided.

### 5.3 Pattern Metadata

When compilation succeeds, display:

| Field | Source |
|-------|--------|
| Min length | `ptern.min_length(p)` |
| Max length | `ptern.max_length(p)` (or "unbounded") |
| Compiled regex | The raw regex source string and flags |

The compiled regex is shown in a read-only, monospace, scrollable field, hidden by default and revealed by a "Show regex" disclosure toggle.

### 5.4 Format Button

Applies `ptern.format(source, format_options)` and replaces the editor content with the result in place. If formatting fails (because the source has a lex or parse error), the button is disabled or a brief error message is shown.

### 5.5 Format Options Button

Opens a modal dialog with controls for each `FormatOptions` field:

| Field | Control type |
|-------|-------------|
| `aligned` | Checkbox |
| `compact` | Checkbox |
| `line_width` | Number input (min 40) |
| `reordered` | Checkbox |

Dismissing the dialog with "Save" persists the options to local storage and immediately re-applies formatting if the source is currently valid.

### 5.6 Copy Button

Copies the current text of the source editor to the clipboard. The button briefly shows a confirmation label ("Copied!") after a successful copy.

---

## 6. Test Case Tabs

A tab bar below (or to the right of) the editor. Each tab represents one independent test case. A "+" button at the end of the tab bar adds a new tab.

Tabs are labelled with sequential integers ("1", "2", "3", …). When a tab is closed, all tabs to its right are renumbered so the sequence remains gapless. Closing the last tab replaces it with a fresh empty tab rather than leaving the tab bar empty.

The maximum number of tabs is 20. The "+" button is hidden when this limit is reached.
Tabs cannot be reordered.

---

## 7. Per-Tab Content

### 7.1 Input String and Test Button

A multi-line text area for the string to test against.

A **Test** button below the input string triggers evaluation of all results in §§7.2–7.5. The button is disabled when the ptern has not compiled successfully.

Results are grayed out (stale) whenever the ptern source or the tab's replacement values have changed since the last test run. Clicking Test clears the stale state and shows fresh results.

### 7.2 Boolean Match Results

A row of labeled Yes/No indicators, one per boolean operation:

| Label | Operation |
|-------|-----------|
| Matches all | `ptern.matches_all_of(p, input)` |
| Matches start | `ptern.matches_start_of(p, input)` |
| Matches end | `ptern.matches_end_of(p, input)` |
| Matches in | `ptern.matches_in(p, input)` |

### 7.3 Occurrence Match Results

For each boolean that is `True`, display the corresponding occurrence result in a read-only JSON-formatted block:

| Condition | Operation | Display label |
|-----------|-----------|---------------|
| matches_all_of is true | `ptern.match_all_of(p, input)` | "Match (all)" |
| matches_start_of is true | `ptern.match_start_of(p, input)` | "Match (start)" |
| matches_end_of is true | `ptern.match_end_of(p, input)` | "Match (end)" |
| matches_in is true | `ptern.match_first_in(p, input)` | "First match" |
| matches_in is true | `ptern.match_all_in(p, input)` | "All matches" |

A `MatchOccurrence` is rendered as:
```json
{ "index": 4, "length": 3, "captures": { "year": "2026" } }
```

`match_next_in` is not included in the playground.

### 7.4 Replacement

A text area for entering the replacement value dictionary as JSON. The expected structure mirrors `Dict(String, ReplacementValue)`:

```json
{
  "year": "2027",
  "word": ["hello", "world"]
}
```

A string value becomes a `ScalarReplacement`; an array of strings becomes an `ArrayReplacement`.

If the JSON is malformed, display a parse error beneath the text area and disable replacement evaluation.

When the JSON is valid, display one labeled result per replace operation, shown only when the corresponding `matches_*` result is `True`:

| Label | Operation |
|-------|-----------|
| Replace (all) | `ptern.replace_all_of(p, input, replacements)` |
| Replace (start) | `ptern.replace_start_of(p, input, replacements)` |
| Replace (end) | `ptern.replace_end_of(p, input, replacements)` |
| Replace (first) | `ptern.replace_first_in(p, input, replacements)` |
| Replace (all in) | `ptern.replace_all_in(p, input, replacements)` |

Each result shows either the replaced string or the replacement error (`InvalidReplacementValue`, `WrongReplacementType`, `ArrayLengthMismatch`, `DuplicateRepetitionCapture`) in a clearly styled error state.

`replace_next_in` is not included in the playground.

### 7.5 Substitution

Shown only when the compiled ptern has `!substitutable = true`.

A text area for entering the capture value dictionary as JSON (same format as §7.4). A separate text area from the replacement input since substitution does not require an input string.

The result of `ptern.substitute(p, captures)` is displayed below. On success, the assembled string is shown. On error, the `SubstitutionError` variant is shown in a styled error state:
- `NotSubstitutable` — should not occur (panel is hidden)
- `MissingCapture(name)` — "Missing capture: name"
- `CaptureMismatch(name, value)` — "Value does not match pattern for: name"
- `ArrayLengthError(name, length, min, max)` — "Wrong array length for: name"
- `NoMatchingBranch` — "No alternation branch matched"

---

## 8. State Persistence

### 8.1 Local Storage

Format options (§5.5) are saved to local storage under a versioned key (e.g. `ptern-playground-v1-format-options`). The version suffix allows future option additions without reading stale data.

### 8.2 Ptern Source and Test Tabs

Ptern source and all tab data are saved to local storage on every change and restored on load. The storage key is `ptern-playground-state`. A `version` field inside the payload allows the app to detect and discard stale data when the schema changes, without needing to version the key itself.

The schema is:

```json
{
  "version": 1,
  "source": "!case-insensitive = true\n\n%Alpha * 1..? as word",
  "formatOptions": {
    "aligned": true,
    "compact": false,
    "lineWidth": 80,
    "reordered": false
  },
  "tabs": [
    {
      "input": "Hello World",
      "replacements": "{ \"word\": \"there\" }"
    }
  ],
  "activeTab": 0
}
```

Notes:
- `replacements` is stored as a raw string so an in-progress or invalid JSON value is preserved across reloads.
- Test results are not persisted; they are always re-run after load to avoid displaying stale output.
- Field names use camelCase to match JavaScript/JSON convention.

URL-based state encoding is not used: a pattern with several definitions and multiple test cases can easily exceed practical URL length limits, making it an unreliable sharing mechanism.

---

## 9. Open Questions (TODOs)

| # | Question |
|---|----------|
| ~~9.1~~ | ~~Should the ptern source and test tabs persist across page reloads?~~ Resolved: local storage only; URL encoding is impractical for patterns of realistic size. |
| ~~9.2~~ | ~~Do test tabs have user-editable names?~~ Resolved: sequential integers, renumbered on close. |
| ~~9.3~~ | ~~What viewport width triggers the stacked → side-by-side layout transition?~~ Resolved: Tailwind `2xl` (1536px). |
| ~~9.4~~ | ~~Is ptern compilation triggered on every keystroke or only on an explicit action?~~ Resolved: compile on keystroke (debounced); test results on explicit Test button per tab; stale results gray out on ptern or replacement change. |
| ~~9.5~~ | ~~Are error positions highlighted inline?~~ Resolved: plain text messages only; no inline highlighting or line/column info. |
| ~~9.6~~ | ~~Is the compiled regex shown by default or behind a toggle?~~ Resolved: hidden by default, revealed by a "Show regex" toggle. |
| ~~9.7~~ | ~~Is there a maximum number of test tabs?~~ Resolved: 20; "+" button hidden at limit. |
| ~~9.8~~ | ~~Can test tabs be reordered by drag-and-drop?~~ Resolved: no. |
| ~~9.9~~ | ~~Single-line or multi-line input?~~ Resolved: multi-line text area. |
| ~~9.10~~ | ~~How to expose `match_next_in`'s `start_index` in the UI?~~ Resolved: omitted from the playground. |
| ~~9.11~~ | ~~How to expose `replace_next_in`'s `start_index` in the UI?~~ Resolved: omitted from the playground. |
| ~~9.12~~ | ~~What is the local storage JSON schema?~~ Resolved: see §8.1–8.2. |
| ~~9.13~~ | ~~What is the deployment target?~~ Resolved: manual static hosting for now; GitHub Pages is a future option if the library warrants a public presence. |
| ~~9.14~~ | ~~What is the top-level directory structure of `ptern-playground/`?~~ Resolved: standard SolidJS (Vite) template structure; Gleam output copied into `src/ptern/` including stdlib dependencies. |
