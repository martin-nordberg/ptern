# Ptern User Guide

Ptern is a pattern language that compiles to regular expressions. It is designed to be readable first — every construct is either a plain keyword or punctuation that carries an obvious meaning. You should be able to read a ptern aloud and have it make sense.

This guide builds up the language from scratch, introducing each concept with working examples. The formal specification (`ptern-specification.md`) is the complete reference; this guide is the on-ramp.

---

## A First Taste

Here is a ptern that matches an ISO date:

```
%Digit * 4 as year '-' %Digit * 2 as month '-' %Digit * 2 as day
```

Read it aloud: "four digits captured as year, a dash, two digits captured as month, a dash, two digits captured as day." It is longer than the equivalent regular expression (`\d{4}-\d{2}-\d{2}`) but leaves nothing to interpret.

With the TypeScript API:

```typescript
import { ptern } from "./index.ts"

const isoDate = ptern`
  %Digit * 4 as year '-' %Digit * 2 as month '-' %Digit * 2 as day
`
```

**Boolean test:**

```typescript
isoDate.matchesAllOf("2026-07-04")      // true
isoDate.matchesAllOf("2026-7-4")        // false — single-digit month/day
isoDate.matchesIn("Event on 2026-07-04 at noon")  // true
```

**Occurrence match:**

```typescript
isoDate.matchFirstIn("Event on 2026-07-04 at noon")
// { index: 9, length: 10, captures: { year: "2026", month: "07", day: "04" } }
```

**Replacement:**

```typescript
isoDate.replaceFirstIn("Event on 2026-07-04 at noon", { year: "2027" })
// "Event on 2027-07-04 at noon"
// month and day are untouched because they were not in the replacements dict
```

**Substitution** (assembling a string from scratch):

```typescript
const isoDateSubstitutable = ptern`
  !substitutable = true
  %Digit * 4 as year '-' %Digit * 2 as month '-' %Digit * 2 as day
`

isoDateSubstitutable.substitute({ year: "2026", month: "07", day: "04" })
// "2026-07-04"
```

These four operations — boolean test, occurrence match, replacement, substitution — are the core of what ptern does. The rest of this guide explains how to write patterns that drive them.

---

## Literals

The simplest pattern is a literal string:

```typescript
const hello = ptern`'hello'`

hello.matchesAllOf("hello")   // true
hello.matchesAllOf("Hello")   // false — case matters by default
hello.matchesAllOf("hello!")  // false — exact match required for matchesAllOf
hello.matchesIn("say hello")  // true — matchesIn finds it anywhere
```

Literals can use either single or double quotes. The two forms are identical:

```typescript
ptern`'hello'`   // same as
ptern`"hello"`
```

Inside a literal, these escape sequences are recognised:

| Escape | Meaning |
|:------:|:--------|
| `\n`   | Newline |
| `\t`   | Tab |
| `\r`   | Carriage return |
| `\'`   | Literal single quote |
| `\"`   | Literal double quote |
| `\\`   | Literal backslash |
| `\uXXXX` | Unicode character by code point |

```typescript
ptern`'\t'`          // matches a tab character
ptern`'can\'t'`      // matches the apostrophe in "can't"
ptern`'é'`      // matches 'é'
```

---

## Sequences

Place two patterns side by side (with a space between them) to match one followed by the other:

```typescript
const greeting = ptern`'hello' ' ' 'world'`

greeting.matchesAllOf("hello world")   // true
greeting.matchesAllOf("helloworld")    // false — space is required
```

**The space between patterns is the sequence operator.** It is not just formatting; it is what makes one pattern follow another. This is intentional: it forces you to write patterns that are easy to read by preventing everything from running together.

You can sequence as many pieces as you like:

```typescript
const dateWithSlashes = ptern`
  %Digit * 2 '/' %Digit * 2 '/' %Digit * 4
`

dateWithSlashes.matchesAllOf("04/28/2026")   // true
```

---

## Alternatives

Use `|` to match any one of several options:

```typescript
const yesOrNo = ptern`'yes' | 'no'`

yesOrNo.matchesAllOf("yes")    // true
yesOrNo.matchesAllOf("no")     // true
yesOrNo.matchesAllOf("maybe")  // false
```

Alternatives can themselves contain sequences:

```typescript
const httpOrHttps = ptern`'http' '://' | 'https' '://'`

httpOrHttps.matchesStartOf("https://example.com")  // true
httpOrHttps.matchesStartOf("ftp://example.com")    // false
```

When a pattern matches, the **first** matching alternative (left to right) is selected. This matters when alternatives overlap.

---

## Grouping

Parentheses `( )` override precedence and let you treat a compound expression as a single unit:

```typescript
// Without grouping: three separate alternatives
ptern`'a' | 'b' | 'c'`

// With grouping: one of 'a', 'b', or 'c', followed by a digit
ptern`('a' | 'b' | 'c') %Digit`
```

```typescript
const colorKeyword = ptern`'color' | 'colour'`  // two full alternatives
const colourAlt    = ptern`'colo' ('u') * 0..1 'r'`  // optional 'u'
```

Grouping is also how you apply repetition to a multi-element pattern (see Repetition below).

---

## Character Classes

A character class matches any **single character** from a named set. They are written with a `%` prefix:

```typescript
const digit     = ptern`%Digit`     // matches any of 0–9
const letter    = ptern`%Alpha`     // matches any of a–z or A–Z
const alnum     = ptern`%Alnum`     // matches any letter or digit
const anyChar   = ptern`%Any`       // matches any single character including newline
const wordChar  = ptern`%Word`      // matches a–z, A–Z, 0–9, _
```

```typescript
digit.matchesAllOf("7")        // true
digit.matchesAllOf("a")        // false
letter.matchesAllOf("Q")       // true
anyChar.matchesAllOf("\n")     // true
```

Character classes pair naturally with repetition:

```typescript
const word  = ptern`%Alpha * 1..?`    // one or more letters
const ident = ptern`%Alpha %Alnum * 0..?`  // letter then letters-or-digits
```

For matching Unicode text beyond ASCII, use Unicode category classes:

```typescript
ptern`%L * 1..?`   // one or more Unicode letters (any script)
ptern`%N * 1..?`   // one or more Unicode numbers
ptern`%Lu`         // one uppercase Unicode letter
ptern`%Ll`         // one lowercase Unicode letter
```

A full list of all character class names is in [Appendix A](#appendix-a-character-class-reference).

---

## Character Ranges

Match any single character within an inclusive range using `..`:

```typescript
const lowerLetter  = ptern`'a'..'z'`
const upperLetter  = ptern`'A'..'Z'`
const singleDigit  = ptern`'0'..'9'`
const hexDigitPart = ptern`'a'..'f'`
```

```typescript
lowerLetter.matchesAllOf("m")   // true
lowerLetter.matchesAllOf("M")   // false
lowerLetter.matchesAllOf("mm")  // false — exactly one character
```

Both endpoints must be single characters. The range must not be inverted (`'z'..'a'` is an error).

Ranges compose with sequences and repetition just like any other expression:

```typescript
// A hexadecimal digit
const hexDigit = ptern`'0'..'9' | 'a'..'f' | 'A'..'F'`

// An octal number
const octal = ptern`'0' '0'..'7' * 1..?`
```

---

## Set Difference

`excluding` removes characters from a single-character set:

```typescript
// Any character except a double quote
const nonQuote = ptern`%Any excluding '"'`

// Any digit except 0
const nonZeroDigit = ptern`%Digit excluding '0'`

// Any digit except 8 or 9
const octalDigit = ptern`%Digit excluding '8'..'9'`
```

Both sides of `excluding` must match exactly one character.

A practical use: matching the contents of a quoted string without letting a closing quote slip through:

```typescript
const quotedString = ptern`'"' (%Any excluding '"') * 0..? '"'`

quotedString.matchesAllOf('"hello world"')   // true
quotedString.matchesAllOf('"say "hi""')      // false
```

---

## Repetition

Repeat a pattern with `*`:

### Fixed count

```typescript
const fourDigits   = ptern`%Digit * 4`   // exactly 4
const threeLetters = ptern`%Alpha * 3`   // exactly 3

fourDigits.matchesAllOf("2026")   // true
fourDigits.matchesAllOf("202")    // false
fourDigits.matchesAllOf("20261")  // false
```

### Bounded range

```typescript
const twoToFour = ptern`%Digit * 2..4`   // 2, 3, or 4 digits

twoToFour.matchesAllOf("12")     // true
twoToFour.matchesAllOf("1234")   // true
twoToFour.matchesAllOf("1")      // false
twoToFour.matchesAllOf("12345")  // false
```

### Optional (zero or one)

`* 0..1` is the idiomatic "maybe once" form:

```typescript
const optionalSign = ptern`('+' | '-') * 0..1 %Digit * 1..?`

optionalSign.matchesAllOf("42")    // true
optionalSign.matchesAllOf("+42")   // true
optionalSign.matchesAllOf("-42")   // true
optionalSign.matchesAllOf("+-42")  // false
```

### Unbounded (at least N)

`* n..?` means "n or more":

```typescript
const oneOrMore  = ptern`%Digit * 1..?`   // at least one
const zeroOrMore = ptern`%Digit * 0..?`   // any number
```

### Repeating a group

Apply `*` to a grouped expression to repeat a multi-element sequence:

```typescript
// Three groups of four digits separated by dashes
const creditCard = ptern`%Digit * 4 ('-' %Digit * 4) * 3`

creditCard.matchesAllOf("1234-5678-9012-3456")  // true
```

Repetition is **greedy**: it consumes as many characters as possible while still allowing the overall pattern to match.

---

## Named Captures

Add `as name` to any expression to capture the matched text under that name:

```typescript
const year = ptern`%Digit * 4 as year`

year.matchFirstIn("The year is 2026")
// { index: 11, length: 4, captures: { year: "2026" } }
```

The `captures` object in the result maps each capture name to the text that was matched at that position. Names that did not participate in the match (e.g. an unmatched branch of an alternation) are absent.

A capture can wrap any expression, not just atomic ones:

```typescript
const isoDate = ptern`
  %Digit * 4 as year '-' %Digit * 2 as month '-' %Digit * 2 as day
`

isoDate.matchFirstIn("Published 2026-04-28")
// { index: 10, length: 10, captures: { year: "2026", month: "04", day: "28" } }
```

### Using captures for replacement

Pass a subset of captures in a `replacements` dict to `replace*` methods. Any capture not mentioned retains its original matched value:

```typescript
isoDate.replaceFirstIn("Published 2026-04-28", { year: "2027" })
// "Published 2027-04-28"   — month and day unchanged

isoDate.replaceAllIn("2026-01-01 and 2026-06-15", { year: "2027" })
// "2027-01-01 and 2027-06-15"
```

### The same name in multiple places

You can reuse a capture name at more than one position in a pattern. The same replacement value is applied to every occurrence:

```typescript
const tagged = ptern`
  '<' %Alpha * 1..? as tag '>'
  %Any * 0..? as body
  '</' %Alpha * 1..? as tag '>'
`

tagged.replaceFirstIn("<em>hello</em>", { tag: "strong" })
// "<strong>hello</strong>"   — both occurrences of `tag` replaced
```

During matching, `captures.tag` holds the value from the **last** matched position (the closing tag in this example).

---

## Subpattern Definitions

For anything beyond a trivial pattern, define named sub-expressions at the top and interpolate them with `{ }`. This is the main readability tool:

```typescript
const isoDate = ptern`
  yyyy = %Digit * 4;
  mm   = '0' '1'..'9' | '1' '0'..'2';
  dd   = '0' '1'..'9' | '1'..'2' %Digit | '3' '0'..'1';
  {yyyy} as year '-' {mm} as month '-' {dd} as day
`
```

Each definition is `name = pattern ;`. The final line (no semicolon) is the body expression that actually matches. Definitions may reference other definitions.

Definitions make the individual pieces testable in isolation and make the body readable at a glance. Compare the body to its equivalent regex fragment — `(\d{4})-(0[1-9]|1[0-2])-(0[1-9]|[12]\d|3[01])` — and the ptern wins on readability every time.

### Interpolation vs. backreference

`{name}` means different things depending on what `name` refers to:

- If `name` is a **definition**, `{name}` expands to that definition's pattern — it matches the same strings the definition matches.
- If `name` is a **capture** (established earlier by `expression as name`), `{name}` is a **backreference** — it matches the exact text that was captured earlier, as if it were a literal.

---

## Annotations

Annotations appear at the very top of a ptern, before any definitions. They configure how the entire pattern compiles or behaves.

### `!case-insensitive = true`

Makes literals and character ranges match both uppercase and lowercase:

```typescript
const keyword = ptern`
  !case-insensitive = true
  'select' | 'from' | 'where'
`

keyword.matchesAllOf("SELECT")   // true
keyword.matchesAllOf("From")     // true
keyword.matchesAllOf("WHERE")    // true
```

### `!multiline = true`

Makes `@line-start` and `@line-end` match at the boundary of each line instead of the whole string. It also causes `matchesAllOf`, `matchesStartOf`, and `matchesEndOf` to operate at line boundaries rather than string boundaries: for example, `matchesAllOf` returns `true` if any complete line in the input is a full match. The annotation is also enabled automatically whenever `@line-start` or `@line-end` appears in the pattern (see Position Assertions below).

### `!replacements-ignore-matching = true`

By default, replacement validates each provided value against the sub-pattern for that capture:

```typescript
const p = ptern`%Digit * 4 as year`

p.replaceFirstIn("2026", { year: "abc" })
// throws: "abc" does not match %Digit * 4
```

Set `!replacements-ignore-matching = true` to skip validation and accept any string as a replacement value. Useful when the replacement is intentionally different in kind from the matched text (e.g. replacing a year with a placeholder like `"YYYY"`):

```typescript
const p = ptern`
  !replacements-ignore-matching = true
  %Digit * 4 as year
`

p.replaceFirstIn("2026", { year: "YYYY" })   // "YYYY"
```

---

## Position Assertions

Position assertions match a **position** in the string, not a character. They are zero-width — they do not consume any input.

| Assertion     | Matches the position… |
|:--------------|:----------------------|
| `@word-start` | Between a non-word and a word character (start of a word) |
| `@word-end`   | Between a word and a non-word character (end of a word) |
| `@line-start` | At the start of a line (enables multiline mode) |
| `@line-end`   | At the end of a line (enables multiline mode) |

```typescript
const wholeWord = ptern`@word-start %Alpha * 1..? @word-end`

wholeWord.matchesIn("say hello there")  // true  — "hello" is a whole word
wholeWord.matchesIn("123")              // false — no alphabetic word
```

Without the word boundaries, `%Alpha * 1..?` would match the alphabetic portion of `"hello123"`. With them, only a standalone word matches:

```typescript
const un = ptern`@word-start 'un'`

un.matchesIn("undo")    // true  — "un" is at a word start
un.matchesIn("fun")     // false — "un" is mid-word
```

For line-anchored patterns, `@line-start` and `@line-end` work across multiple lines when multiline mode is active:

```typescript
const lineNumber = ptern`@line-start %Digit * 1..?`

lineNumber.matchAllIn("1 first\n2 second\n3 third")
// three occurrences: { index:0 }, { index:8 }, { index:17 }
```

---

## All Six Match Operations

Every ptern exposes the same set of matching operations. They differ only in where they anchor the match:

| Operation               | Where it looks                         | Returns |
|:------------------------|:---------------------------------------|:--------|
| `matchesAllOf(s)`       | Must cover the whole string            | `boolean` |
| `matchesStartOf(s)`     | Must start at index 0                  | `boolean` |
| `matchesEndOf(s)`       | Must end at `s.length`                 | `boolean` |
| `matchesIn(s)`          | Anywhere in the string                 | `boolean` |
| `matchAllOf(s)`         | Must cover the whole string            | `MatchOccurrence \| null` |
| `matchStartOf(s)`       | Must start at index 0                  | `MatchOccurrence \| null` |
| `matchEndOf(s)`         | Must end at `s.length`                 | `MatchOccurrence \| null` |
| `matchFirstIn(s)`       | First occurrence anywhere              | `MatchOccurrence \| null` |
| `matchNextIn(s, start)` | First occurrence at or after `start`   | `MatchOccurrence \| null` |
| `matchAllIn(s)`         | Every non-overlapping occurrence       | `MatchOccurrence[]` |

A `MatchOccurrence` carries:
- `index` — start position in the string
- `length` — length of the matched substring
- `captures` — dictionary of capture names to their matched strings

```typescript
const version = ptern`
  num = %Digit * 1..10;
  {num} as major '.' {num} as minor '.' {num} as patch
`

version.matchFirstIn("Using package v1.23.456 in production")
// { index: 14, length: 8, captures: { major: "1", minor: "23", patch: "456" } }

version.matchAllIn("v1.0.0 and v2.3.4")
// [
//   { index: 1,  length: 5, captures: { major: "1", minor: "0", patch: "0" } },
//   { index: 11, length: 5, captures: { major: "2", minor: "3", patch: "4" } }
// ]
```

`matchNextIn` is useful for iterating through matches manually:

```typescript
const num = ptern`%Digit * 1..? as n`
let pos = 0
let m
while ((m = num.matchNextIn("a1b22c333", pos)) !== null) {
  console.log(m.captures.n)  // "1", "22", "333"
  pos = m.index + m.length
}
```

---

## Length Metadata

`minLength()` and `maxLength()` return the shortest and longest string the pattern can match, computed at compile time:

```typescript
const p = ptern`%Digit * 2..4`
p.minLength()   // 2
p.maxLength()   // 4

const q = ptern`%Digit * 1..?`
q.minLength()   // 1
q.maxLength()   // null — unbounded
```

Position assertions contribute zero to both bounds. This lets you use ptern as a quick validity check — if an input string's length is already outside `[min, max]`, you can skip the regex entirely.

---

## Replacement in Depth

Replacement modifies a string by substituting new text at the positions of named captures, leaving everything else unchanged.

### Validation

By default, each replacement value is validated against the sub-pattern for its capture. A value that would not have matched the original pattern is rejected:

```typescript
const p = ptern`%Digit * 4 as year`

p.replaceFirstIn("2026", { year: "2027" })   // "2027" — valid
p.replaceFirstIn("2026", { year: "20" })     // throws: too short
p.replaceFirstIn("2026", { year: "abc" })    // throws: not digits
```

Set `!replacements-ignore-matching = true` to disable validation for the whole pattern.

### Multiple captures

Any subset of captures may appear in the replacements dict. Omitted captures retain their original values:

```typescript
const isoDate = ptern`
  yyyy = %Digit * 4;
  mm   = '0' '1'..'9' | '1' '0'..'2';
  dd   = '0' '1'..'9' | '1'..'2' %Digit | '3' '0'..'1';
  {yyyy} as year '-' {mm} as month '-' {dd} as day
`

isoDate.replaceFirstIn("2026-07-04", { month: "12" })
// "2026-12-04"   — year and day unchanged
```

### Round-trip consistency

If you match a string and pass the captured values back as replacements, you get the original string:

```typescript
const m = isoDate.matchFirstIn("2026-07-04")
isoDate.replaceAllOf("2026-07-04", m.captures)
// "2026-07-04" — identity
```

### Captures inside repetitions

When a named capture appears inside a repeated sub-pattern, you can provide a `string[]` to replace each iteration independently:

```typescript
const csv = ptern`
  !replacements-ignore-matching = true
  %Any * 1..100 as col (',' %Any * 1..100 as col) * 0..20
`

csv.replaceFirstIn("alice,bob,carol", { col: ["ALICE", "BOB", "CAROL"] })
// "ALICE,BOB,CAROL"
```

The array length must equal the number of iterations in the actual match. Providing the wrong length throws `ArrayLengthMismatch`.

A scalar value inside a repetition is **broadcast** — it replaces every iteration with the same value:

```typescript
csv.replaceFirstIn("alice,bob,carol", { col: "X" })
// "X,X,X"
```

If the same capture name appears both inside and outside a repetition (see §Subpattern Definitions for an example), the array's first element fills the non-repeated occurrence and the remaining elements fill the iterations.

### All six replace operations

Each replace operation targets a different region of the input. They return the modified string, or the original if the pattern does not match that region.

```typescript
p.replaceAllOf(input, replacements)           // whole string
p.replaceStartOf(input, replacements)         // prefix
p.replaceEndOf(input, replacements)           // suffix
p.replaceFirstIn(input, replacements)         // first occurrence
p.replaceNextIn(input, startIndex, replacements) // first at/after startIndex
p.replaceAllIn(input, replacements)           // all occurrences
```

---

## Substitution

Substitution is the inverse of matching: instead of extracting captures from a string, you provide capture values and assemble a new string from scratch. No original input string is needed.

To enable substitution, add `!substitutable = true`:

```typescript
const isoDate = ptern`
  !substitutable = true
  yyyy = %Digit * 4;
  mm   = '0' '1'..'9' | '1' '0'..'2';
  dd   = '0' '1'..'9' | '1'..'2' %Digit | '3' '0'..'1';
  {yyyy} as year '-' {mm} as month '-' {dd} as day
`

isoDate.substitute({ year: "2026", month: "07", day: "04" })
// "2026-07-04"
```

### What makes a pattern substitutable

The compiler checks that every part of the pattern can produce output from capture values alone. Literal strings always can. Character classes (`%Digit`) and ranges (`'a'..'z'`) cannot — they match a set of characters but cannot choose one without being told.

These patterns are substitutable:
- A literal: `'hello'`
- A named capture (regardless of what is inside it): `%Digit * 4 as year`
- A sequence or alternation where every branch is substitutable

These are not:
- A bare character class: `%Digit` (which character would you pick?)
- A bounded repetition with no named capture: `%Digit * 1..4` (how many iterations?)

A bounded repetition `E * n..m` *is* substitutable if `E` contains at least one named capture — the length of the provided array drives the iteration count.

### Alternation in substitution

In a substitutable alternation, the first branch whose required captures are provided is selected:

```typescript
const isoWithSep = ptern`
  !substitutable = true
  {yyyy} as year ('-' | '/') as sep {mm} as month {sep} {dd} as day
`

isoWithSep.substitute({ year: "2026", month: "07", day: "04" })
// "2026-07-04"   — 'sep' absent; '-' wins as the first (literal) branch

isoWithSep.substitute({ year: "2026", month: "07", day: "04", sep: "/" })
// "2026/07/04"   — 'sep' provided; validated against ('-' | '/')
```

A branch made entirely of literals is always eligible and acts as a fallback. If no branch can succeed, `substitute` throws.

### Repeated captures in substitution

An array of values drives the iteration count for a bounded repetition:

```typescript
const csv = ptern`
  !substitutable = true
  field = %Any * 1..100;
  {field} as col (',' {field} as col) * 0..20
`

csv.substitute({ col: ["name", "age", "city"] })
// "name,age,city"
// col[0] fills the leading occurrence; col[1..] fill the repeated group
```

---

## Building Real Patterns

Here are a few complete examples that pull together the concepts above.

### US phone number

```
area     = %Digit * 3;
exchange = %Digit * 3;
line     = %Digit * 4;
('+1 ') * 0..1
( '(' {area} as area-code ') ' {exchange} as exchange '-' {line} as line
| {area} as area-code '-' {exchange} as exchange '-' {line} as line )
```

Two formats — `(555) 123-4567` and `555-123-4567` — handled by alternation. An optional `+1 ` prefix. Named captures for each component.

### Floating-point number

```
!case-insensitive = true
digits = %Digit * 1..20;
exp    = 'e' ('+' | '-') * 0..1 {digits} as exponent;
('+' | '-') * 0..1 {digits} as integer ('.' {digits}) * 0..1 {exp} * 0..1
```

The annotation makes `e` and `E` equivalent. The `exp` definition is only interpolated if the optional `{exp}` group matches.

### Password validator (what ptern cannot do)

```
// NOT expressible: at least one lowercase, one uppercase, one digit
// Use three separate pterns tested independently:
const hasLower  = ptern`%Lower * 1..?`
const hasUpper  = ptern`%Upper * 1..?`
const hasDigit  = ptern`%Digit * 1..?`
const longEnough = ptern`%Any * 8..?`

function isValidPassword(s: string): boolean {
  return hasLower.matchesIn(s)  &&
         hasUpper.matchesIn(s)  &&
         hasDigit.matchesIn(s)  &&
         longEnough.matchesAllOf(s)
}
```

Simultaneous lookahead requirements are not expressible as a single ptern. Use multiple pterns and combine the results in code.

---

## Appendix A: Character Class Reference

### Special

| Class  | Meaning |
|:------:|:--------|
| `%Any` | Any single character (including newline) |

### POSIX Classes

| Class     | Meaning |
|:---------:|:--------|
| `%Alnum`  | ASCII letters and digits (`[A-Za-z0-9]`) |
| `%Alpha`  | ASCII letters (`[A-Za-z]`) |
| `%Ascii`  | Any ASCII character (0–127) |
| `%Blank`  | Space or tab |
| `%Cntrl`  | ASCII control characters |
| `%Digit`  | ASCII digits (`[0-9]`) |
| `%Graph`  | Visible ASCII characters |
| `%Lower`  | ASCII lowercase letters (`[a-z]`) |
| `%Print`  | Printable ASCII characters |
| `%Punct`  | ASCII punctuation and symbols |
| `%Space`  | ASCII whitespace (space, tab, newline, CR, FF, VT) |
| `%Upper`  | ASCII uppercase letters (`[A-Z]`) |
| `%Word`   | ASCII word characters (`[A-Za-z0-9_]`) |
| `%Xdigit` | Hexadecimal digits (`[0-9A-Fa-f]`) |

### Unicode General Category Classes

Short names (`%L`, `%N`, …) and long PascalCase aliases (`%Letter`, `%Number`, …) are both accepted. See `ptern-specification.md §5` for the full table.

| Short | Meaning |
|:-----:|:--------|
| `%L`  | Any Unicode letter |
| `%Lu` | Uppercase letter |
| `%Ll` | Lowercase letter |
| `%N`  | Any Unicode number |
| `%Nd` | Decimal digit |
| `%P`  | Any Unicode punctuation |
| `%S`  | Any Unicode symbol |
| `%Z`  | Any Unicode separator |
| `%C`  | Any "other" character |
| `%M`  | Any combining mark |

---

## Appendix B: Annotation Reference

| Annotation                       | Default | Meaning |
|:---------------------------------|:-------:|:--------|
| `!case-insensitive = true`       | `false` | Literals and ranges match both cases |
| `!multiline = true`              | `false` | `@line-start`/`@line-end` match per-line (also set automatically by those assertions) |
| `!replacements-ignore-matching`  | `false` | Skip validation of replacement values |
| `!substitutable = true`          | `false` | Enable `substitute()` and check substitutability at compile time |
| `!substitutions-ignore-matching` | `false` | Skip validation in `substitute()` (requires `!substitutable = true`) |

---

## Appendix C: Operator Precedence

Tightest binding first:

| Operator | Example |
|:---------|:--------|
| `( )` grouping, `{ }` interpolation | `('a' \| 'b') * 3` |
| `..` character range | `'a'..'z'` |
| `excluding` set difference | `%Alpha excluding 'q'` |
| `*` repetition | `%Digit * 4` |
| `as` capture | `%Digit * 4 as year` |
| sequence (space) | `'hello' ' ' 'world'` |
| `\|` alternation | `'cat' \| 'dog'` |
