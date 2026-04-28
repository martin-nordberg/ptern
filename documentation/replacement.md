# Ptern Replacement

## Overview

Replacement modifies a string by substituting new values for named captures within a match, leaving all other matched text unchanged. The original string provides the baseline: any named capture not given a replacement retains its originally matched text.

```typescript
const isoDate = ptern`
  yyyy = %Digit * 4;
  mm = '0' '1'..'9' | '1' '0'..'2';
  dd = '0' '1'..'9' | '1'..'2' %Digit | '3' '0'..'1';
  {yyyy} as year '-' {mm} as month '-' {dd} as day
`

isoDate.replaceFirstIn("Independence Day 2026-07-04 - the 250th", { year: "2027" })
// "Independence Day 2027-07-04 - the 250th"

isoDate.replaceAllIn("2026-07-04 and 2026-12-25", { year: "2027" })
// "2027-07-04 and 2027-12-25"
```

Replacement requires no special annotation. It works on any ptern, regardless of whether `!substitutable = true` is set.

## Comparison With Substitution

Replacement and substitution share a common structure — both take a capture-values dict and reconstruct text from named capture values — but differ in their relationship to an original input string:

| Aspect | Substitution | Replacement |
|---|---|---|
| Input | Capture-values dict only | Original string + capture-values dict |
| Missing capture | Error (unless expression is substitutable) | Original matched text preserved |
| Branch/iteration selection | Driven by captures dict | Driven by the original regex match |
| Requires `!substitutable = true` | Yes | No |
| Capture value validation | Optional (`!substitutions-ignore-matching`) | Optional (`!replacements-ignore-matching`) |
| Array values for repetitions | Yes — drives iteration count | Yes — replaces per-iteration values |
| Return value | Assembled string | Modified original string; original unchanged if no match |

## Annotations

```
!replacements-ignore-matching = true
```
When true, provided replacement values are not validated against the sub-expression's regex during replace operations. Default is `false` (validation enabled). Applies only to replacement operations; has no effect on `substitute()`.

## Definitions

**Capture-values dict**: A dictionary mapping capture names (strings) to values. A value is either a `string` or a `string[]`. Array values are used for replacing per-iteration values of captures inside repetitions; see Bounded Repetition below.

**Match info**: The result of running the ptern's regex against the input string, including the matched span and the span of each named capture (obtained via the `d` / `hasIndices` flag). During replacement, each named capture has a known span in the original string.

**Replacement point**: A named capture `E as name` is a replacement point. If `name` appears in the capture-values dict, the replacement value is used instead of the original matched text for that capture's span. If `name` is absent, the original matched text flows through. Either way, evaluation continues recursively into `E` only when `name` is absent.

## Replacement Semantics

**`replace(E, captures, original, span) → string`** is the recursive evaluation function. `original` is the full input string; `span = (start, end)` is the matched region of `E` within `original`. It always succeeds — it never errors due to a missing capture, because the original text is always a valid fallback.

### Literal
```
replace('text', captures, original, span) = original.slice(span.start, span.end)
```
Produces the original matched text for this literal (always equal to the literal itself).

### Character Class, Range, Set Difference
```
replace(%Class, captures, original, span) = original.slice(span.start, span.end)
```
Produces the original matched character. Not a replacement point.

### Named Capture — `E as name`
1. If `name ∈ captures` and `captures[name]` is a `string`:
   - If `!replacements-ignore-matching = false`: validate that `captures[name]` matches `E`'s regex. If not: error.
   - Return `captures[name]`. Evaluation of `E` is skipped; any inner captures in `captures` are silently ignored.
2. If `name ∈ captures` and `captures[name]` is a `string[]`: error — scalar value required for a non-repetition capture.
3. If `name ∉ captures`: return `replace(E, captures, original, span_of_E)`.

Rule 1 short-circuits at the outer capture, identical in structure to substitution. If `name` is present, inner capture values in the dict are silently ignored — the inner expression is not evaluated and the provided value replaces the entire matched span for `name`, subsuming all inner capture spans.

**Multiple occurrences of the same name**: When a capture name appears at more than one position in the pattern, the same replacement value applies uniformly to every occurrence. A scalar value replaces all non-repetition occurrences identically. An array value applies to all occurrences inside a single repetition (per-iteration semantics); if the same name appears inside two distinct repetitions, the array cannot be consistently distributed and is a runtime error (`DuplicateRepetitionCapture`).

### Sequence — `E1 E2 ... En`
```
replace(E1 E2 ... En, captures, original, span) =
  replace(E1, captures, original, span_of_E1) +
  replace(E2, captures, original, span_of_E2) + ... +
  replace(En, captures, original, span_of_En)
```
Each `Ei` has its own matched span within `original`. Unmapped captures produce their original matched text.

### Alternation — `E1 | E2 | ... | En`
Exactly one branch `Ei` matched the original input. Only that branch has a matched span. Replacement operates exclusively within the matched branch:
```
replace(E1 | ... | En, captures, original, span) = replace(Ei, captures, original, span)
```
Named captures belonging to unmatched branches are not present in match info and are absent from the dict — they are silently ignored if provided in `captures`.

Contrast with substitution, where the captures dict selects which branch to use. In replacement, the branch is fixed by the original match.

### Grouping — `(E)`
```
replace((E), captures, original, span) = replace(E, captures, original, span)
```

### Fixed Repetition — `E * n`
The repetition matched exactly `n` iterations, each with its own span. Without array support:
```
replace(E * n, captures, original, span) =
  replace(E, captures, original, span_of_iter_1) +
  replace(E, captures, original, span_of_iter_2) + ... +
  replace(E, captures, original, span_of_iter_n)
```
The same scalar replacement value in `captures` (if any) applies to all iterations.

With array support (see Bounded Repetition below for the extended form): each iteration may receive a distinct replacement value.

### Bounded Repetition — `E * n..m` (and Array-Valued Captures)

The original match determined the actual iteration count `k` (where `n ≤ k ≤ m`), with `k` matched spans for `E`.

A named capture `name` within `E` may be provided in `captures` as either:
- **`string[]`** (per-iteration): `captures[name][i]` replaces the matched value of `name` in iteration `i`. The array length must equal `k` (the actual iteration count from the original match).
- **`string`** (broadcast): the same replacement value applies to every iteration.

If `captures[name]` is a `string[]` with length ≠ `k`: error.

When `E` contains multiple named captures with array values, all arrays must have length `k`.

For each iteration `i` in `0..k-1`:
```
replace(E, captures_with_scalars_for_iter_i, original, span_of_iter_i)
```
where `captures_with_scalars_for_iter_i` replaces each `string[]` value `captures[name]` with the scalar `captures[name][i]`, leaving broadcast strings unchanged.

**Implementation note**: Capturing per-iteration spans requires the two-pass approach described in `match-array.md`. The main regex (with `d` flag) identifies the span of the entire repetition; a sub-regex with the `g` flag is then applied within that span to extract per-iteration spans. This is a prerequisite for both array-valued replacement and array-valued matching.

## Runtime Errors

The following are detected at call time:

- A provided capture value is a `string[]` for a capture that is not inside a repetition.
- A provided array has length ≠ `k` (the actual iteration count from the original match).
- A capture name with an array value appears inside more than one distinct repetition.
- When `!replacements-ignore-matching = false`: a provided replacement value does not match the sub-expression's regex.

Unlike substitution, a missing capture is never a runtime error. The original matched text is always a valid fallback.

## API

```typescript
replaceAllOf(input: string,    replacements: Record<string, string | string[]>): string
replaceStartOf(input: string,  replacements: Record<string, string | string[]>): string
replaceEndOf(input: string,    replacements: Record<string, string | string[]>): string
replaceFirstIn(input: string,  replacements: Record<string, string | string[]>): string
replaceNextIn(input: string, startIndex: number,
                               replacements: Record<string, string | string[]>): string
replaceAllIn(input: string,    replacements: Record<string, string | string[]>): string
```

Each method returns the modified string, or the original `input` unchanged if the ptern does not match. Extra keys in `replacements` that do not correspond to any named capture in the ptern (including captures from unmatched alternation branches) are silently ignored.

The `replacements` parameter type is `Record<string, string | string[]>` to accommodate array-valued captures inside repetitions. This changes the current `Record<string, string>` and is a breaking change to the existing API.

## Language Bindings

- **Gleam**: `ptern.replace_first_in(ptern, input, replacements)` etc. return `String` (the original if no match) or `Result(String, ReplacementError)` when validation is enabled.
- **TypeScript**: Replacement methods throw on validation error. They return `input` unchanged if no match.

```gleam
pub type ReplacementError {
  CaptureMismatch(name: String, value: String)
  WrongCaptureType(name: String)
  ArrayLengthMismatch(name: String, provided: Int, actual: Int)
  DuplicateRepetitionCapture(name: String)
}
```

## Examples

### Partial Replacement (Existing Behavior)

```typescript
const isoDate = ptern`
  yyyy = %Digit * 4;
  mm = '0' '1'..'9' | '1' '0'..'2';
  dd = '0' '1'..'9' | '1'..'2' %Digit | '3' '0'..'1';
  ({yyyy} as year '-' {mm} as month '-' {dd} as day) as date
`

isoDate.replaceFirstIn("Independence Day 2026-07-04 - the 250th", { year: "2027" })
// "Independence Day 2027-07-04 - the 250th"
// month and day retain their original values; `date` is not in replacements, so
// the inner captures are evaluated individually.

isoDate.replaceFirstIn("Independence Day 2026-07-04 - the 250th", { date: "2027-07-04" })
// "Independence Day 2027-07-04 - the 250th"
// Outer capture `date` short-circuits; year/month/day are silently ignored.

isoDate.replaceAllIn("2026-07-04 and 2026-12-25", { year: "2027" })
// "2027-07-04 and 2027-12-25"
```

### Per-Iteration Array Replacement (Extended Behavior)

```typescript
const csv = ptern`
  field = %Any * 1..100;
  {field} as col (',' {field} as col) * 0..20
`

csv.replaceFirstIn("name,age,city", { col: ["NAME", "AGE", "CITY"] })
// "NAME,AGE,CITY"
// col[0] replaces the first iteration, col[1] the second, col[2] the third.

csv.replaceFirstIn("name,age,city", { col: "X" })
// "X,X,X"
// Broadcast: scalar "X" applied to every iteration.
```

### Outer vs. Inner Capture Priority

```typescript
const tagged = ptern`
  word = %Alpha * 1..20;
  '<' {word} as tag '>' {word} as body '</' {word} as tag '>'
`

tagged.replaceFirstIn("<em>hello</em>", { body: "world" })
// "<em>world</em>"
// `tag` is absent; original tag text "em" flows through.

tagged.replaceFirstIn("<em>hello</em>", { tag: "strong", body: "world" })
// "<strong>world</strong>"
// Both captures replaced; `tag` appears in two positions and both are updated.
```

