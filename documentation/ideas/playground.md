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
| Language | TypeScript |
| UI framework | SolidJS |
| Styling | TailwindCSS |
| Build tool | Vite |
| Dev runtime | Bun |
| Ptern engine | Transpiled Gleam output (ES module) |

The playground is written in TypeScript throughout. It imports the compiled Gleam output as a plain ES module and calls the public Ptern API directly in the browser. No server is required at runtime.

The Gleam output is untyped JavaScript; a thin TypeScript declaration file (`src/ptern/ptern.d.ts`) provides types for the public API surface consumed by the playground.

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
| Ptern source text | `string` | Local storage |
| Compiled ptern or compile error | `Ptern \| CompileError \| null` | Derived |
| Format options | `FormatOptions` | Local storage |
| Test tabs | `TestTab[]` | Local storage |
| Active tab index | `number` | Session only |

A `TestTab` contains:
- A sequential integer label (renumbered on close)
- A mode: `'match-replace'` or `'substitution'`
- An input string (used in match/replace mode)
- A capture values JSON string (raw text, shared between both modes; may be invalid)
- A parsed capture values dict or JSON parse error (derived, used for replacement and substitution)

---

## 4. Layout

The page is divided into two main sections, stacked vertically on narrow viewports and side-by-side on wide viewports:

1. **Left / top panel** — Ptern editor and compile output (§5)
2. **Right / bottom panel** — Test case tabs (§6)

The layout switches from stacked to side-by-side at Tailwind's `2xl` breakpoint (1536px). In side-by-side mode the two panels are separated by a 10 px gap with no border; each panel occupies half of the remaining width.

**Scrolling model:** there is a single page-level scroll bar. Neither panel has its own scroll container. Content in both panels flows into the normal document and the page grows to fit.

### 4.1 Title Area

A header row with the application name on the far left and the light/dark mode toggle on the far right. The space between them is empty. No other interactive controls in this area. A documentation link may be added later.

### 4.2 Theming

The application supports light and dark modes, toggled by an icon button in the title area. The button shows a sun icon (☀) in dark mode (click to switch to light) and a moon icon (☽) in light mode (click to switch to dark). The active mode is persisted to local storage under `ptern-playground-v1-theme`. The default on first visit is light mode, regardless of the OS preference.

**Consistency:** both the editor panel and the test panel share the same colour palette. No panel has its own background colour; all surface colours come from the active theme.

**Light mode** uses a warm sepia-tinted background rather than pure white. Tailwind's `stone` scale provides a suitable off-white base (`stone-50` / `stone-100` for surfaces, `stone-200`–`stone-300` for borders, `stone-700`–`stone-900` for text).

**Dark mode** uses a dark neutral background. Tailwind's `zinc` or `neutral` scale is appropriate (`zinc-900` for the page background, `zinc-800` for elevated surfaces, `zinc-600`–`zinc-700` for borders, `zinc-100`–`zinc-300` for text).

Tailwind's `class`-based dark mode strategy is used (`darkMode: 'class'` in `tailwind.config.ts`), with a `dark` class toggled on the `<html>` element.

**Stale result styling:** stale results are rendered with muted colours — specifically, text and badge colours shift to a mid-range tone from the active theme's scale (e.g. `stone-400` in light mode, `zinc-500` in dark mode) rather than the normal content colour. No opacity change; no overlay.

### 4.3 Text Areas

All text areas (source editor, input string, capture values) are user-resizable. Resize is vertical only (`resize: vertical`) — horizontal resizing is disabled to prevent panels from overflowing their width.

### 4.4 Typography

**Monospace font** — used for the source editor, the compiled regex field, all JSON input text areas, and all JSON output blocks:

```
'Lucida Console', Monaco, 'Courier New', monospace
```

**UI font** — labels, buttons, tab bar, status messages, and all other prose: Tailwind's default sans-serif stack (`ui-sans-serif, system-ui, sans-serif`).

Both stacks are declared in `tailwind.config.ts` under `theme.fontFamily` and applied via utility classes (`font-mono`, `font-sans`).

**Font size:** 14px (`text-sm`) throughout — source editor, JSON text areas, output blocks, labels, buttons, and all other UI text. This is a comfortable desktop editing size; no mobile scaling is applied.

### 4.5 Spacing

Use Tailwind `p-3` (12px) as the standard internal padding for panels, sections, and UI components. Use `gap-3` between stacked sections within a panel. Tighter elements (badge rows, metadata table rows) may use `p-2` where `p-3` would feel loose.

---

## 5. Ptern Editor Panel

The editor panel is a column flex container. Its sections appear in this order top to bottom:

1. Source editor (§5.1) — grows to fill available height
2. Compile status (§5.2) — immediately below the editor
3. Button row (§5.7) — immediately below compile status
4. Pattern metadata (§5.3) — below buttons, shown only on success

### 5.1 Source Editor

A multi-line text area for entering the Ptern source string.

**Height:** behaviour differs by layout mode.

- **Side-by-side** (`2xl` and above): the editor uses `flex: 1` within the column-flex editor panel, growing to fill all vertical space not claimed by the compile status, button row, and metadata. The panel is anchored to `100dvh` minus the title area height. If the test panel grows taller than the editor panel the page extends and the editor stays at its natural height.
- **Stacked** (below `2xl`): the editor panel height is fixed at `50dvh`. The editor textarea fills that height via `flex: 1` within the panel, leaving room for compile status, buttons, and metadata below it. The page scrolls normally beyond this point.

**Evaluation timing:** The ptern is compiled on mount (immediately, without debounce) and on every subsequent keystroke (debounced at 200 ms). Test results within each tab are not updated automatically; they are produced by clicking a **Test** button inside the tab (§7.1). When the ptern source, the tab's input string, or the tab's capture values change after a test has been run, the existing results are muted to indicate they are stale, until the Test button is clicked again.

### 5.2 Compile Status

Displayed immediately below the source editor, above the button row. Plain text only — no background color, no border.

- **Success** — green text: "Successful Compilation"
- **Lex error** — red text: the offending character and its position in the source
- **Parse error** — red text: a human-readable message (e.g. "unexpected token '|', expected expression")
- **Semantic errors** — red text: each error on its own line

No inline highlighting or line/column position information is provided beyond what appears in the message text.

### 5.3 Pattern Metadata

Shown below the button row only when compilation succeeds.

Min and max length are displayed in a small two-column table: labels in the first column, values in the second.

| Label | Value |
|-------|-------|
| Min length | `ptern.min_length(p)` |
| Max length | `ptern.max_length(p)`, or "unbounded" if there is no upper bound |

The compiled regex is shown separately below the table inside a `<details>/<summary>` element. The summary label is "Show regex". When expanded, the regex source string and flags are displayed in a read-only, monospace, horizontally scrollable field.

### 5.4 Format Button

Applies `ptern.format(source, format_options)` and replaces the editor content with the result in place. Disabled when the source has a lex or parse error.

### 5.5 Format Options Button

Opens a modal dialog with controls for each `FormatOptions` field:

| Field | Control type |
|-------|-------------|
| `aligned` | Checkbox |
| `compact` | Checkbox |
| `line_width` | Number input (min 40) |
| `reordered` | Checkbox |

The dialog has **Save** and **Cancel** buttons; pressing Escape is equivalent to Cancel. Clicking outside the dialog (on the backdrop) does nothing — the dialog must be dismissed via Save or Cancel. Saving persists the options to local storage and immediately re-applies formatting if the source is currently valid.

### 5.6 Copy Button

Copies the current text of the source editor to the clipboard. The button briefly shows a confirmation label ("Copied!") after a successful copy.

### 5.7 Button Row

The Format (§5.4), Format Options (§5.5), and Copy (§5.6) buttons are arranged in a single horizontal row immediately below the compile status area.

---

## 6. Test Case Tabs

A tab bar below (or to the right of) the editor. Each tab represents one independent test case. A "+" button at the end of the tab bar adds a new tab.

Tabs are labelled with sequential integers ("1", "2", "3", …). When a tab is closed, all tabs to its right are renumbered so the sequence remains gapless. Closing the last tab replaces it with a fresh empty tab rather than leaving the tab bar empty.

The maximum number of tabs is 20. The "+" button is hidden when this limit is reached. Tabs cannot be reordered.

If the tabs overflow the available width, the tab bar scrolls horizontally. The "+" button scrolls with the tabs (it is the last item in the scrollable row). The "+" button is styled as an inactive tab — same shape, borders (left, top, right), and muted background — with a "+" label in place of a number.

Each tab has a close button (×) that is hidden by default and revealed on hover. The close button is always visible on touch devices (no hover state available).

**Tab styling:** each tab has a border on the left, top, and right sides only — no bottom border. A continuous border runs along the top of the test panel at the same level as the tab bottoms. The active tab's background matches the panel background and its missing bottom border makes it visually contiguous with the panel, as though the panel extends up into the tab. Inactive tabs use a muted background colour. The continuous top-of-panel border is interrupted only by the active tab, reinforcing the open-bottom effect.

---

## 7. Per-Tab Content

### 7.1 Mode Toggle

At the top of each tab, a pill switch toggles between **Match / Replace** and **Substitution** mode. The active option is highlighted within the pill; the inactive option is visually recessed. The Substitution option is disabled (unclickable, muted) when the compiled ptern does not have `!substitutable = true`. If the tab is currently in Substitution mode and the ptern is recompiled without `!substitutable`, the tab automatically switches back to Match / Replace mode.

Switching mode resets the tab to the "not yet tested" state — any previously shown results are cleared and the "Click Test to see results" prompt is shown.

### 7.2 Capture Values

A shared JSON text area used in both modes. Its position within the tab layout depends on the active mode: below the input string in Match / Replace mode (§7.3), and as the sole input in Substitution mode (§7.7). The value is preserved when switching modes.

The expected format:

```json
{
  "year": "2027",
  "word": ["hello", "world"]
}
```

A string value is interpreted as a `ScalarReplacement` (for replacement) or a scalar capture (for substitution); an array of strings is interpreted as an `ArrayReplacement` / array capture. The same JSON text and the same `captureValues` field in local storage are used in both modes — toggling between modes does not clear or replace this value.

An empty capture values field (empty string) is treated as an empty object `{}` rather than as invalid JSON. This ensures replacement and substitution results are shown for patterns with no named captures.

If the JSON is malformed (non-empty but invalid), a parse error is displayed beneath the text area and all capture-dependent results are disabled.

### 7.3 Match / Replace Mode

Shown when the tab is in Match / Replace mode. The inputs appear in this order top to bottom:

1. **Input string** — multi-line text area for the string to test against.
2. **Capture values** — the shared JSON text area (§7.2).
3. **Test button** — below both text areas. Triggers evaluation of all results below (§§7.4–7.6). Disabled when the ptern has not compiled successfully.

**Stale state:** results are muted whenever the ptern source, the input string, or the capture values have changed since the last test run. This includes the case where the ptern has entered an error state — past results remain visible but muted, and the Test button stays disabled until the ptern compiles successfully again. Clicking Test clears the muted state and shows fresh results. Before the Test button has been clicked for the first time, the results area shows a prompt: "Click Test to see results."

### 7.4 Boolean Match Results

A row of labeled badges, one per boolean operation:

| Label | Operation |
|-------|-----------|
| Matches all | `ptern.matches_all_of(p, input)` |
| Matches start | `ptern.matches_start_of(p, input)` |
| Matches end | `ptern.matches_end_of(p, input)` |
| Matches in | `ptern.matches_in(p, input)` |

Each badge displays an icon followed by a word: a green checkmark and "Yes" when the result is `true`, a red cross and "No" when `false`. The operation label (e.g. "Matches all") appears above the badge.

### 7.5 Occurrence Match Results

For each boolean that is `true`, display the corresponding occurrence result in a read-only JSON-formatted block:

| Condition | Operation | Display label |
|-----------|-----------|---------------|
| matches_all_of is true | `ptern.match_all_of(p, input)` | "Match (all)" |
| matches_start_of is true | `ptern.match_start_of(p, input)` | "Match (start)" |
| matches_end_of is true | `ptern.match_end_of(p, input)` | "Match (end)" |
| matches_in is true | `ptern.match_first_in(p, input)` | "First match" |
| matches_in is true | `ptern.match_all_in(p, input)` | "All matches" |

Each result displays the matched substring extracted from the input using the occurrence's `index` and `length`. If the occurrence has a non-empty captures dict, it is shown on the same line after the substring:

```
"2026-05-14"  { "year": "2026", "month": "05", "day": "14" }
```

If there are no captures, only the substring is shown:

```
"2026-05-14"
```

`match_all_in` shows one line per occurrence in the same format:

```
"2026-05-14"  { "year": "2026", "month": "05", "day": "14" }
"2025-01-01"  { "year": "2025", "month": "01", "day": "01" }
"2024-12-31"  { "year": "2024", "month": "12", "day": "31" }
```

`match_next_in` is not included in the playground.

### 7.6 Replacement Results

Shown only when the capture values JSON is valid. One labeled result per replace operation, displayed only when the corresponding `matches_*` result is `true`:

| Label | Operation |
|-------|-----------|
| Replace (all) | `ptern.replace_all_of(p, input, captures)` |
| Replace (start) | `ptern.replace_start_of(p, input, captures)` |
| Replace (end) | `ptern.replace_end_of(p, input, captures)` |
| Replace (first) | `ptern.replace_first_in(p, input, captures)` |
| Replace (all in) | `ptern.replace_all_in(p, input, captures)` |

Each result shows either the replaced string or the replacement error (`InvalidReplacementValue`, `WrongReplacementType`, `ArrayLengthMismatch`, `DuplicateRepetitionCapture`) as red plain text with no background or border.

`replace_next_in` is not included in the playground.

### 7.7 Substitution Mode

Shown when the tab is in Substitution mode (only available when the ptern has `!substitutable = true`).

The capture values text area (§7.2) is the input. No separate input string is required.

**Test button:** same as in Match / Replace mode — triggers evaluation, disabled when ptern has not compiled, and results are muted when the ptern source or capture values change. Before first click: "Click Test to see results."

The result of `ptern.substitute(p, captures)` is displayed below the Test button. On success, the assembled string is shown. On error, red plain text with no background or border:

- `NotSubstitutable` — should not occur (mode is unavailable)
- `MissingCapture(name)` — "Missing capture: name"
- `CaptureMismatch(name, value)` — "Value does not match pattern for: name"
- `ArrayLengthError(name, length, min, max)` — "Wrong array length for: name"
- `NoMatchingBranch` — "No alternation branch matched"

---

## 8. State Persistence

### 8.1 Local Storage

All persistent state is saved under two keys:

| Key | Contents |
|-----|----------|
| `ptern-playground-state` | Ptern source, format options, tabs (schema below) |
| `ptern-playground-v1-theme` | `"light"` or `"dark"` |

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
      "mode": "match-replace",
      "input": "Hello World",
      "captureValues": "{ \"word\": \"there\" }"
    }
  ]
}
```

Notes:
- `captureValues` is stored as a raw string so an in-progress or invalid JSON value is preserved across reloads. The same field is used in both Match / Replace and Substitution modes.
- `mode` is either `"match-replace"` or `"substitution"`. On load, if `mode` is `"substitution"` but the restored ptern is not substitutable, the tab silently resets to `"match-replace"`.
- Test results are not persisted. Tabs restore to the "not yet tested" state on load, showing the "Click Test to see results" prompt. No automatic re-run occurs.
- `formatOptions` is stored inline in the main state object (not under a separate key).
- Field names use camelCase to match JavaScript/JSON convention.

**Initial state:** when no stored state is found (first visit or cleared storage), the app loads a short ISO date example:

```
%Digit * 4 as year '-' %Digit * 2 as month '-' %Digit * 2 as day
```

One tab is present with an empty input string and empty capture values.

If localStorage is unavailable (e.g. private browsing, storage quota exceeded), the app runs normally but does not attempt to save or restore state. Work is silently lost when the window closes. No warning is shown.

URL-based state encoding is not used: a pattern with several definitions and multiple test cases can easily exceed practical URL length limits, making it an unreliable sharing mechanism.

---

## 9. Open Questions (TODOs)

| # | Question |
|---|----------|
| ~~9.1~~ | ~~Should the ptern source and test tabs persist across page reloads?~~ Resolved: local storage only; URL encoding is impractical for patterns of realistic size. |
| ~~9.2~~ | ~~Do test tabs have user-editable names?~~ Resolved: sequential integers, renumbered on close. |
| ~~9.3~~ | ~~What viewport width triggers the stacked → side-by-side layout transition?~~ Resolved: Tailwind `2xl` (1536px). |
| ~~9.4~~ | ~~Is ptern compilation triggered on every keystroke or only on an explicit action?~~ Resolved: compile on keystroke (debounced); test results on explicit Test button per tab; results are muted when ptern source, input, or capture values change. |
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
