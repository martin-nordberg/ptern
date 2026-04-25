# Ptern Substitution

## Overview

Substitution assembles a string from a ptern and a dictionary of named capture values. It is the inverse of matching: where `match()` extracts named captures from a string, `substitute()` constructs a string from named capture values.

```typescript
const isoDate = ptern`
  !substitutable = true
  yyyy = %Digit * 4;
  mm = '0' '1'..'9' | '1' '0'..'2';
  dd = '0' '1'..'9' | '1'..'2' %Digit | '3' '0'..'1';
  {yyyy} as year '-' {mm} as month '-' {dd} as day
`

isoDate.substitute({ year: "2026", month: "07", day: "04" })
// "2026-07-04"

isoDate.substitute({ year: "202", month: "07", day: "03" })
// Error: "202" does not match {yyyy}
```

Substitution requires the ptern to declare `!substitutable = true`, which triggers a compile-time check that the ptern's final pattern is *substitutable* — that every expression in the pattern can produce a string from capture values alone, without an original input string to draw from.

## Definitions

**Capture-values dict**: A dictionary mapping capture names (strings) to values. A value is either a `string` or a `string[]`. Array values are used for captures inside repetitions; all other captures expect `string`.

**Substitution point**: A named capture `E as name` is a substitution point. The caller may provide `name` directly in the capture-values dict, which short-circuits evaluation of the inner expression `E`. If `name` is absent, evaluation falls through into `E`.

**Substitutable expression**: An expression `E` is *substitutable* if `evaluate(E, captures)` (defined below) can succeed purely from a capture-values dict, without an original input string. Substitutability is a compile-time property defined recursively by syntactic form.

## Annotations

```
!substitutable = true
```
Asserts that the ptern's final pattern is substitutable. The check is performed at compile time — a ptern violating the constraint fails immediately when `ptern\`...\`` is evaluated. Has no effect on matching or replacement operations.

```
!substitutions-ignore-matching = true
```
When true, provided capture values are not validated against the sub-expression's regex during `substitute()`. Default is `false` (validation enabled). Applies only to `substitute()`; has no effect on replacement operations.

It is a compile time error to set a value for `!substitutions-ignore-matching` when
`!substitutable = false` or `!substitutable` is omitted entirely.

## Substitutability

Substitutability is a compile-time boolean property of an expression, defined recursively by syntactic form. The compile-time check verifies that the ptern's final pattern is substitutable when `!substitutable = true` is set.

| Expression | Substitutable? | Reason |
|---|---|---|
| `'literal'` | Yes | Produces its text unconditionally |
| `%Class`, `'a'..'z'`, `%C excluding E` | No | Matches a set of characters; does not determine a unique output |
| `(E)` | Same as `E` | Grouping is transparent |
| `E1 E2 ... En` (sequence) | Yes iff every `Ei` is substitutable | |
| `E1 \| E2 \| ... \| En` (alternation) | Yes iff every `Ei` is substitutable | |
| `E * n` (fixed repetition) | Yes iff `E` is substitutable | |
| `E * n..m` (bounded repetition) | Yes iff `E` contains at least one named capture | Array length drives iteration count |
| `E as name` | Always yes | `name` is a direct substitution point regardless of whether `E` is substitutable |
| `{id}` | Same as the definition of `id` | Transparent; equals the substitutability of the referenced definition |

### Subpattern Context

A subpattern definition `id = E` may itself be substitutable or not. When interpolated as `{id}` inside a named capture (`{id} as name`), the outer capture makes the expression substitutable regardless. When interpolated outside any named capture, `{id}` is substitutable iff the definition of `id` is substitutable.

## Substitution Semantics

**`evaluate(E, captures) → string | error`** is the runtime recursive evaluation function. It produces the assembled string for expression `E` given the capture-values dict, or an error if the substitution cannot succeed.

### Literal
```
evaluate('text', captures) = "text"
```

### Named Capture — `E as name`
1. If `name ∈ captures`:
   - If `captures[name]` is not a `string`: error — scalar value required.
   - If `!substitutions-ignore-matching = false`: validate that `captures[name]` matches `E`'s regex. If not: error.
   - Return `captures[name]`. Inner captures within `E` are not evaluated; values for them in `captures` are silently ignored.
2. If `name ∉ captures` and `E` is substitutable: return `evaluate(E, captures)`.
3. If `name ∉ captures` and `E` is not substitutable: error — `name` is required but not provided.

Rule 1 takes priority: an outer capture always short-circuits evaluation of the inner expression. Inner capture values present in the dict are silently ignored when an outer capture is provided.

### Sequence — `E1 E2 ... En`
```
evaluate(E1 E2 ... En, captures) =
  evaluate(E1, captures) + evaluate(E2, captures) + ... + evaluate(En, captures)
```
If any `evaluate(Ei, captures)` errors, the error propagates immediately. All required captures must be present.

### Alternation — `E1 | E2 | ... | En`
Branches are tried in order from left to right. The first branch for which `evaluate(Ei, captures)` succeeds is selected; its result is returned. If all branches fail: error.

A branch consisting entirely of literals always succeeds — it acts as a fallback default wherever it appears. Branch ordering is the programmer's responsibility, just as with regex alternation: a literal branch placed before a branch with captures will shadow it unconditionally.

A branch fails and fallthrough to the next branch occurs only when a required capture is absent and its sub-expression cannot succeed without it. A validation failure on a *provided* value propagates immediately as an error without trying subsequent branches.

### Grouping — `(E)`
```
evaluate((E), captures) = evaluate(E, captures)
```

### Fixed Repetition — `E * n`
```
evaluate(E * n, captures) = evaluate(E, captures) repeated n times and concatenated
```
`n` is a constant known at compile time. Errors from `evaluate(E, captures)` propagate immediately.

### Bounded Repetition — `E * n..m`
`E` must contain at least one named capture (enforced at compile time). Let the named captures within `E` (not shadowed by an outer capture on `E`) be `name1, name2, ..., namek`.

Each `namei ∈ captures` may be provided as either:
- **`string[]`** (per-iteration): `captures[namei][j]` is used for iteration `j`. The array length must satisfy `n ≤ length ≤ m`.
- **`string`** (broadcast): the same value is used for every iteration.

All array-valued captures must have the same length; error if any two differ. That common length is `len`, the iteration count. If no array-valued capture is present (all provided captures are broadcast strings), the iteration count cannot be determined and is an error for bounded repetitions. For fixed repetitions (`E * n`), broadcast strings work unconditionally since `n` is known.

For each `i` in `0..len-1`: evaluate `E` with each `captures[namei]` replaced by `captures[namei][i]` (arrays) or `captures[namei]` unchanged (broadcast strings). Concatenate the results.

If `n = 0` and a named capture within `E` is absent from `captures` or is present as an empty array `[]`, the repetition produces the empty string.

### Character Classes, Ranges, Set Differences
Not directly evaluable. Their presence outside a named capture in a substitutable expression is a compile-time error.

### Subpattern Interpolation — `{id}`
```
evaluate({id}, captures) = evaluate(definition_of(id), captures)
```
Transparent; evaluates the referenced definition in place.

## Compile-Time Errors

Detected when `ptern\`...\`` is evaluated:

- `!substitutable = true` is set and the final pattern is not substitutable per the table above.
- A character class, range, or set-difference expression appears outside any named capture in the final pattern (including after subpattern expansion).
- A bounded repetition `E * n..m` contains no named capture.

## Runtime Errors

Detected at `substitute()` call time:

- `substitute()` called on a ptern without `!substitutable = true`.
- A required named capture is absent from the captures dict and its expression is not substitutable without it.
- A provided capture value fails validation against the sub-expression's regex (when `!substitutions-ignore-matching = false`).
- A provided capture value is the wrong type (e.g., `string[]` where `string` is required, or vice versa).
- An array value's length falls outside the repetition bounds `[n, m]`, or multiple array values within a repetition have unequal lengths.
- All branches of an alternation fail.

## API

```typescript
substitute(captures: Record<string, string | string[]>): string
```

Returns the assembled string. Extra keys in `captures` that do not correspond to any named capture in the ptern are silently ignored.

All pterns expose `substitute()`. Calling it on a ptern without `!substitutable = true` throws immediately at runtime.

## Language Bindings

- **Gleam**: `ptern.substitute(ptern, captures)` returns `Result(String, SubstitutionError)`.
- **TypeScript**: `ptern.substitute(captures)` throws on error. An ill-formed ptern at module top level causes the module to fail to load.

```gleam
pub type SubstitutionError {
  NotSubstitutable
  MissingCapture(name: String)
  CaptureMismatch(name: String, value: String)
  WrongCaptureType(name: String)
  ArrayLengthError(name: String, length: Int, min: Int, max: Int)
  NoMatchingBranch
}
```

## Examples

### ISO Date With Varying Separator

```typescript
const isoDate = ptern`
  !substitutable = true
  yyyy = %Digit * 4;
  mm = '0' '1'..'9' | '1' '0'..'2';
  dd = '0' '1'..'9' | '1'..'2' %Digit | '3' '0'..'1';
  ({yyyy} as year ('-' | '/') as sep {mm} as month {sep} {dd} as day) as date
`

isoDate.substitute({ date: "2026-07-04", year: "2029" })
// "2026-07-04"
// Outer capture `date` short-circuits; `year: "2029"` is silently ignored.

isoDate.substitute({ year: "2026", month: "07", day: "04" })
// "2026-07-04"
// `sep` absent; ('-' | '/') selects first branch '-' (always-eligible literal fallback).

isoDate.substitute({ year: "2026", month: "07", day: "04", sep: "/" })
// "2026/07/04"
// `sep` provided and validated against ('-' | '/').

isoDate.substitute({ date: "2026.07.04" })
// Error: "2026.07.04" does not match the regex for `date`.

isoDate.substitute({ year: "2026", month: "07", day: "04", sep: "." })
// Error: "." does not match ('-' | '/').
```

### Repeated Capture

```typescript
const csv = ptern`
  !substitutable = true
  field = %Any * 1..100;
  {field} as col (',' {field} as col) * 0..20
`

csv.substitute({ col: ["name", "age", "city"] })
// "name,age,city"
// col[0] = "name" consumed by the leading (non-repeated) {field} as col
// col[1..] = ["age", "city"] consumed by the repeated (',' {field} as col) * 0..20
```

When the same capture name appears in both a non-repeated and a repeated position, the non-repeated occurrence consumes the first array element and the repetition consumes the remainder. The array length must therefore equal 1 + (number of repetition iterations).

### Subpattern Substitutability

```typescript
const tagged = ptern`
  !substitutable = true
  word = %Alpha * 1..20;
  '<' {word} as tag '>' {word} as body '</' {word} as tag '>'
`

tagged.substitute({ tag: "em", body: "hello" })
// "<em>hello</em>"
// `tag` appears twice; both occurrences use the same provided value.
```

