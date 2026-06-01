# Ptern User Guide — TypeScript API

Ptern is a pattern language that compiles to regular expressions. It is designed to be readable first — every construct is either a plain keyword or punctuation that carries an obvious meaning. You should be able to read a ptern aloud and have it make sense.

This guide builds up the language from scratch, introducing each concept with working examples. The formal specification (`ptern-specification.md`) is the complete reference; this guide is the on-ramp.

All examples assume:

```typescript
import { compile, format } from "@ptern/tern";
```

---

## A First Taste

Here is a ptern that matches an ISO date:

```
%Digit * 4 as year '-' %Digit * 2 as month '-' %Digit * 2 as day
```

Read it aloud: "four digits captured as year, a dash, two digits captured as month, a dash, two digits captured as day." It is longer than the equivalent regular expression (`\d{4}-\d{2}-\d{2}`) but leaves nothing to interpret.

With the TypeScript API:

```typescript
const isoDate = compile(
  "%Digit * 4 as year '-' %Digit * 2 as month '-' %Digit * 2 as day",
);
```

**Boolean test:**

```typescript
isoDate.matchesAllOf("2026-07-04")                    // true
isoDate.matchesAllOf("2026-7-4")                      // false — single-digit month/day
isoDate.matchesIn("Event on 2026-07-04 at noon")      // true
```

**Occurrence match:**

```typescript
isoDate.matchFirstIn("Event on 2026-07-04 at noon")
// { index: 9, length: 10,
//   captures: { year: "2026", month: "07", day: "04" } }
```

**Replacement:**

```typescript
isoDate.replaceFirstIn(
  "Event on 2026-07-04 at noon",
  { year: "2027" },
)
// "Event on 2027-07-04 at noon"
// month and day are untouched because they were not in the replacements object
```

**Substitution** (assembling a string from scratch):

```typescript
const isoDateSub = compile(
  "!substitutable = true\n" +
  "%Digit * 4 as year '-' %Digit * 2 as month '-' %Digit * 2 as day",
);

isoDateSub.substitute({ year: "2026", month: "07", day: "04" })
// "2026-07-04"
```

These four operations — boolean test, occurrence match, replacement, substitution — are the core of what ptern does. The rest of this guide explains how to write patterns that drive them.

---

## Literals

The simplest pattern is a literal string:

```typescript
const hello = compile("'hello'");

hello.matchesAllOf("hello")   // true
hello.matchesAllOf("Hello")   // false — case matters by default
hello.matchesAllOf("hello!")  // false — exact match required for matchesAllOf
hello.matchesIn("say hello")  // true — matchesIn finds it anywhere
```

Literals can use either single or double quotes. The two forms are identical:

```typescript
compile("'hello'")    // same as
compile('"hello"')
```

An empty literal `''` or `""` is a compile-time error — every literal must contain at least one character.

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
compile("'\\t'")        // ptern for a tab character
compile("'can\\'t'")    // ptern matching "can't"
compile("'é'")          // ptern matching 'é'
```

---

## Sequences

Place two patterns side by side (with a space between them) to match one followed by the other:

```typescript
const greeting = compile("'hello' ' ' 'world'");

greeting.matchesAllOf("hello world")   // true
greeting.matchesAllOf("helloworld")    // false — space is required
```

**The space between patterns is the sequence operator.** It is not just formatting; it is what makes one pattern follow another. This is intentional: it forces you to write patterns that are easy to read by preventing everything from running together.

You can sequence as many pieces as you like:

```typescript
const dateWithSlashes = compile("%Digit * 2 '/' %Digit * 2 '/' %Digit * 4");

dateWithSlashes.matchesAllOf("04/28/2026")   // true
```

---

## Alternatives

Use `|` to match any one of several options:

```typescript
const yesOrNo = compile("'yes' | 'no'");

yesOrNo.matchesAllOf("yes")    // true
yesOrNo.matchesAllOf("no")     // true
yesOrNo.matchesAllOf("maybe")  // false
```

Alternatives can themselves contain sequences:

```typescript
const httpOrHttps = compile("'http' '://' | 'https' '://'");

httpOrHttps.matchesStartOf("https://example.com")  // true
httpOrHttps.matchesStartOf("ftp://example.com")    // false
```

When a pattern matches, the **first** matching alternative (left to right) is selected. This matters when alternatives overlap.

---

## Grouping

Parentheses `( )` override precedence and let you treat a compound expression as a single unit:

```typescript
// Without grouping: three separate alternatives
compile("'a' | 'b' | 'c'");

// With grouping: one of 'a', 'b', or 'c', followed by a digit
compile("('a' | 'b' | 'c') %Digit");
```

```typescript
const colorKeyword = compile("'color' | 'colour'");    // two full alternatives
const colourAlt    = compile("'colo' ('u') * 0..1 'r'");  // optional 'u'
```

Grouping is also how you apply repetition to a multi-element pattern (see Repetition below).

---

## Character Classes

A character class matches any **single character** from a named set. They are written with a `%` prefix:

```typescript
const digit   = compile("%Digit");  // matches any of 0–9
const letter  = compile("%Alpha");  // matches any of a–z or A–Z
const alnum   = compile("%Alnum");  // matches any letter or digit
const anyChar = compile("%Any");    // matches any single character including newline
const wordCh  = compile("%Word");   // matches a–z, A–Z, 0–9, _
```

```typescript
digit.matchesAllOf("7")     // true
digit.matchesAllOf("a")     // false
letter.matchesAllOf("Q")    // true
anyChar.matchesAllOf("\n")  // true
```

Character classes pair naturally with repetition:

```typescript
const word  = compile("%Alpha * 1..?");          // one or more letters
const ident = compile("%Alpha %Alnum * 0..?");   // letter then letters-or-digits
```

For matching Unicode text beyond ASCII, use Unicode category classes:

```typescript
compile("%L * 1..?")   // one or more Unicode letters (any script)
compile("%N * 1..?")   // one or more Unicode numbers
compile("%Lu")         // one uppercase Unicode letter
compile("%Ll")         // one lowercase Unicode letter
```

A full list of all character class names is in [Appendix A](#appendix-a-character-class-reference).

---

## Character Ranges

Match any single character within an inclusive range using `..`:

```typescript
const lowerLetter  = compile("'a'..'z'");
const upperLetter  = compile("'A'..'Z'");
const singleDigit  = compile("'0'..'9'");
const hexDigitPart = compile("'a'..'f'");
```

```typescript
lowerLetter.matchesAllOf("m")    // true
lowerLetter.matchesAllOf("M")    // false
lowerLetter.matchesAllOf("mm")   // false — exactly one character
```

Both endpoints must be single characters. The range must not be inverted (`'z'..'a'` is an error).

Ranges compose with sequences and repetition just like any other expression:

```typescript
// A hexadecimal digit
const hexDigit = compile("'0'..'9' | 'a'..'f' | 'A'..'F'");

// An octal number
const octal = compile("'0' '0'..'7' * 1..?");
```

---

## Set Difference

`excluding` removes characters from a single-character set:

```typescript
// Any character except a double quote
const nonQuote     = compile('%Any excluding \'"\'');

// Any digit except 0
const nonZeroDigit = compile("%Digit excluding '0'");

// Any digit except 8 or 9
const octalDigit   = compile("%Digit excluding '8'..'9'");
```

Both sides of `excluding` must match exactly one character.

A practical use: matching the contents of a quoted string without letting a closing quote slip through:

```typescript
const quotedString = compile("'\"' (%Any excluding '\"') * 0..? '\"'");

quotedString.matchesAllOf('"hello world"')  // true
```

---

## Repetition

Repeat a pattern with `*`:

### Fixed count

```typescript
const fourDigits   = compile("%Digit * 4");   // exactly 4
const threeLetters = compile("%Alpha * 3");   // exactly 3

fourDigits.matchesAllOf("2026")    // true
fourDigits.matchesAllOf("202")     // false
fourDigits.matchesAllOf("20261")   // false
```

### Bounded range

```typescript
const twoToFour = compile("%Digit * 2..4");   // 2, 3, or 4 digits

twoToFour.matchesAllOf("12")      // true
twoToFour.matchesAllOf("1234")    // true
twoToFour.matchesAllOf("1")       // false
twoToFour.matchesAllOf("12345")   // false
```

### Optional (zero or one)

`* 0..1` is the idiomatic "maybe once" form:

```typescript
const optionalSign = compile("('+' | '-') * 0..1 %Digit * 1..?");

optionalSign.matchesAllOf("42")     // true
optionalSign.matchesAllOf("+42")    // true
optionalSign.matchesAllOf("-42")    // true
optionalSign.matchesAllOf("+-42")   // false
```

### Unbounded (at least N)

`* n..?` means "n or more":

```typescript
const oneOrMore  = compile("%Digit * 1..?");   // at least one
const zeroOrMore = compile("%Digit * 0..?");   // any number
```

### Repeating a group

Apply `*` to a grouped expression to repeat a multi-element sequence:

```typescript
// Three groups of four digits separated by dashes
const creditCard = compile("%Digit * 4 ('-' %Digit * 4) * 3");

creditCard.matchesAllOf("1234-5678-9012-3456")  // true
```

### Lazy repetition: `fewest`

By default, repetition is **greedy** — it consumes as many iterations as possible while still allowing the overall pattern to match. Add `fewest` after any variable-count repetition to make it **lazy**: prefer the fewest iterations that still allow the pattern to match.

```typescript
// Greedy — %Any * 1..? swallows as far as possible before stopping at '</'
const greedy = compile("'<' %Alpha * 1..? '>' %Any * 1..? '</'");
greedy.matchFirstIn("<b>hello</b><em>world</em>")
// { index: 0, length: 22, captures: {} } — runs all the way to the last '</'

// Lazy — stops at the first '</'
const lazyP = compile("'<' %Alpha * 1..? '>' %Any * 1..? fewest '</'");
lazyP.matchFirstIn("<b>hello</b><em>world</em>")
// { index: 0, length: 11, captures: {} } — stops at the first '</'
```

`fewest` works with any variable-count form:

```
%Any * 1..? fewest      // one or more, fewest first
%Any * 0..? fewest      // zero or more, fewest first
%Any * 0..1 fewest      // optional, prefer not to match
%Any * 3..10 fewest     // 3 to 10, prefer 3
```

Applying `fewest` to an exact count is a compile-time error — there is nothing to minimise when the count is fixed.

**`fewest` vs `excluding`:** For patterns bounded by a single-character delimiter, `excluding` is the better choice — it prevents the delimiter from being consumed at all, eliminating backtracking entirely. Use `fewest` when the end delimiter is more than one character and `excluding` cannot help:

```typescript
// Single-char delimiter — use excluding (no backtracking)
const quoted = compile("'\"' %Any excluding '\"' * 0..? '\"'");

// Multi-char end delimiter — use fewest
const bold = compile("'<b>' %Any * 0..? fewest '</b>'");
```

---

## Named Captures

Add `as name` to any expression to capture the matched text under that name:

```typescript
const yearP = compile("%Digit * 4 as year");

yearP.matchFirstIn("The year is 2026")
// { index: 11, length: 4, captures: { year: "2026" } }
```

The `captures` object in the result maps each capture name to the text that was matched at that position. Names that did not participate in the match (e.g. an unmatched branch of an alternation) are absent.

A capture can wrap any expression, not just atomic ones:

```typescript
const isoDate = compile(
  "%Digit * 4 as year '-' %Digit * 2 as month '-' %Digit * 2 as day",
);

isoDate.matchFirstIn("Published 2026-04-28")
// { index: 10, length: 10,
//   captures: { year: "2026", month: "04", day: "28" } }
```

### Using captures for replacement

Pass a subset of captures in a replacements object to any `replace*` method. Any capture not mentioned retains its original matched value:

```typescript
isoDate.replaceFirstIn(
  "Published 2026-04-28",
  { year: "2027" },
)
// "Published 2027-04-28"   — month and day unchanged

isoDate.replaceAllIn(
  "2026-01-01 and 2026-06-15",
  { year: "2027" },
)
// "2027-01-01 and 2027-06-15"
```

### The same name in multiple places

You can reuse a capture name at more than one position in a pattern. The same replacement value is applied to every occurrence:

```typescript
const tagged = compile(
  "'<' %Alpha * 1..? as tag '>' " +
  "%Any * 0..? as body " +
  "'</' %Alpha * 1..? as tag '>'",
);

tagged.replaceFirstIn(
  "<em>hello</em>",
  { tag: "strong" },
)
// "<strong>hello</strong>"   — both occurrences of `tag` replaced
```

During matching, `captures` holds the value from the **last** matched position for each name (the closing tag in this example).

---

## Subpattern Definitions

For anything beyond a trivial pattern, define named sub-expressions at the top and interpolate them with `{ }`. This is the main readability tool:

```typescript
const isoDate = compile(
  "yyyy = %Digit * 4;\n" +
  "mm   = '0' '1'..'9' | '1' '0'..'2';\n" +
  "dd   = '0' '1'..'9' | '1'..'2' %Digit | '3' '0'..'1';\n" +
  "{yyyy} as year '-' {mm} as month '-' {dd} as day",
);
```

Each definition is `name = pattern ;`. The final line (no semicolon) is the body expression that actually matches. Definitions may reference other definitions.

Every definition must be used — if a definition's name never appears in a `{name}` that is reachable from the body expression, the pattern fails to compile with an `unusedDefinition` error.

### Interpolation vs. backreference

`{name}` means different things depending on what `name` refers to:

- If `name` is a **definition**, `{name}` expands to that definition's pattern — it matches the same strings the definition matches.
- If `name` is a **capture** (established earlier by `expression as name`), `{name}` is a **backreference** — it matches the exact text that was captured earlier, as if it were a literal.

A classic use of backreferences is detecting doubled words or matching paired delimiters:

```typescript
// Detects a repeated word separated by a space
const doubled = compile("%Alpha * 1..? as word ' ' {word}");

doubled.matchesAllOf("hello hello")  // true
doubled.matchesAllOf("hello world")  // false — different words
doubled.matchesIn("the the problem") // true — finds "the the"
```

```typescript
// Matches XML-like open/close tags where the tag names must agree
const element = compile(
  "'<' %Alpha * 1..20 as tag '>' %Any * 0..10000 '</' {tag} '>'",
);

element.matchesAllOf("<em>hello</em>")    // true
element.matchesAllOf("<em>hello</div>")   // false — mismatched tags
```

---

## Annotations

Annotations appear at the very top of a ptern, before any definitions. They configure how the entire pattern compiles or behaves.

### `!case-insensitive = true`

Makes literals and character ranges match both uppercase and lowercase:

```typescript
const keyword = compile(
  "!case-insensitive = true\n" +
  "'select' | 'from' | 'where'",
);

keyword.matchesAllOf("SELECT")   // true
keyword.matchesAllOf("From")     // true
keyword.matchesAllOf("WHERE")    // true
```

### `!multiline = true`

Makes `@line-start` and `@line-end` match at the boundary of each line instead of the whole string. It also causes `matchesAllOf`, `matchesStartOf`, and `matchesEndOf` to operate at line boundaries. The annotation is also enabled automatically whenever `@line-start` or `@line-end` appears in the pattern.

### `!replacements-ignore-matching = true`

By default, replacement validates each provided value against the sub-pattern for that capture. Set this annotation to skip validation and accept any string. Useful when the replacement is intentionally different in kind from the matched text:

```typescript
const p = compile(
  "!replacements-ignore-matching = true\n" +
  "%Digit * 4 as year",
);

p.replaceFirstIn("2026", { year: "YYYY" })
// "YYYY"
```

### `!allow-backtracking = true`

By default, the compiler rejects patterns that could cause catastrophic backtracking. Three checks are run on patterns with variable-count repetitions:

**Overlapping alternation branches in a repetition** — if two branches share characters at the boundary between iterations, `ambiguousRepetitionAdjacency` is reported:

```typescript
compile("('a' | 'ab') * 1..?")   // Error: 'a' and 'ab' both start with 'a'
compile("(%Alpha | '_') * 1..?")  // OK: %Alpha and '_' are disjoint
```

**Variable-length body that overlaps itself** — if the body of a variable-count repetition is variable-length and its last and first character sets overlap, `ambiguousRepetitionBody` is reported:

```typescript
compile("(%Alpha * 1..?) * 1..?")    // Error: inner repetition is variable-length
compile("('x' %Digit * 1..?) * 1..?") // OK: last=%Digit, first='x' — disjoint
```

**Adjacent unbounded repetitions** — two directly adjacent unbounded repetitions with overlapping character sets produce `ambiguousAdjacentRepetition`:

```typescript
compile("%Digit * 1..? %Digit * 1..?")        // Error: both unbounded, %Digit∩%Digit ≠ ∅
compile("%Digit * 1..? '-' %Digit * 1..?")    // OK: literal '-' separates them
```

Set `!allow-backtracking = true` to opt out when a pattern is structurally safe but the static analysis cannot prove it.

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
const wholeWord = compile("@word-start %Alpha * 1..? @word-end");

wholeWord.matchesIn("say hello there")  // true  — "hello" is a whole word
wholeWord.matchesIn("123")              // false — no alphabetic word
```

For line-anchored patterns, `@line-start` and `@line-end` work across multiple lines when multiline mode is active:

```typescript
const lineNumber = compile("@line-start %Digit * 1..?");

lineNumber.matchAllIn("1 first\n2 second\n3 third")
// three occurrences: index 0, index 8, index 17
```

---

## All Match Operations

Every ptern exposes the same set of matching operations. They differ only in where they anchor the match:

| Method                              | Where it looks                       | Returns |
|:------------------------------------|:-------------------------------------|:--------|
| `matchesAllOf(s)`                   | Must cover the whole string          | `boolean` |
| `matchesStartOf(s)`                 | Must start at index 0                | `boolean` |
| `matchesEndOf(s)`                   | Must end at `s.length`               | `boolean` |
| `matchesIn(s)`                      | Anywhere in the string               | `boolean` |
| `matchAllOf(s)`                     | Must cover the whole string          | `MatchOccurrence \| null` |
| `matchStartOf(s)`                   | Must start at index 0                | `MatchOccurrence \| null` |
| `matchEndOf(s)`                     | Must end at `s.length`               | `MatchOccurrence \| null` |
| `matchFirstIn(s)`                   | First occurrence anywhere            | `MatchOccurrence \| null` |
| `matchNextIn(s, start)`             | First occurrence at or after `start` | `MatchOccurrence \| null` |
| `matchAllIn(s)`                     | Every non-overlapping occurrence     | `MatchOccurrence[]` |

A `MatchOccurrence` carries:
- `index` — start position in the string
- `length` — length of the matched substring
- `captures` — `Record<string, string>` mapping capture names to their matched strings

```typescript
const version = compile(
  "num = %Digit * 1..10;\n" +
  "{num} as major '.' {num} as minor '.' {num} as patch",
);

version.matchFirstIn("Using package v1.23.456 in production")
// { index: 14, length: 8,
//   captures: { major: "1", minor: "23", patch: "456" } }

version.matchAllIn("v1.0.0 and v2.3.4")
// [
//   { index: 1,  length: 5, captures: { major: "1", minor: "0", patch: "0" } },
//   { index: 11, length: 5, captures: { major: "2", minor: "3", patch: "4" } }
// ]
```

`matchNextIn` is useful for iterating through matches manually:

```typescript
function collectCaptures(p: Ptern, input: string, key: string): string[] {
  const results: string[] = [];
  let pos = 0;
  let m = p.matchNextIn(input, pos);
  while (m !== null) {
    const v = m.captures[key];
    if (v !== undefined) results.push(v);
    pos = m.index + m.length;
    m = p.matchNextIn(input, pos);
  }
  return results;
}

const num = compile("%Digit * 1..? as n");
collectCaptures(num, "a1b22c333", "n")
// ["1", "22", "333"]
```

For the common case of collecting all matches, `matchAllIn` is more concise:

```typescript
const num = compile("%Digit * 1..? as n");
num.matchAllIn("a1b22c333").map(m => m.captures["n"]!)
// ["1", "22", "333"]
```

---

## Length Metadata

`minLength()` and `maxLength()` return the shortest and longest string the pattern can match, computed at compile time:

```typescript
const p = compile("%Digit * 2..4");
p.minLength()   // 2
p.maxLength()   // 4

const q = compile("%Digit * 1..?");
q.minLength()   // 1
q.maxLength()   // null — unbounded
```

Position assertions contribute zero to both bounds. This lets you use ptern as a quick validity check — if an input string's length is already outside `[minLength(), maxLength()]`, you can skip the regex entirely.

---

## Replacement in Depth

Replacement modifies a string by substituting new text at the positions of named captures, leaving everything else unchanged.

### Validation

By default, each replacement value is validated against the sub-pattern for its capture. A value that would not have matched the original pattern throws `PternReplacementError`:

```typescript
const p = compile("%Digit * 4 as year");

p.replaceFirstIn("2026", { year: "2027" })  // "2027" — valid
p.replaceFirstIn("2026", { year: "abc" })   // throws PternReplacementError
```

Set `!replacements-ignore-matching = true` to disable validation for the whole pattern.

### Multiple captures

Any subset of captures may appear in the replacements object. Omitted captures retain their original values:

```typescript
const isoDate = compile(
  "yyyy = %Digit * 4;\n" +
  "mm   = '0' '1'..'9' | '1' '0'..'2';\n" +
  "dd   = '0' '1'..'9' | '1'..'2' %Digit | '3' '0'..'1';\n" +
  "{yyyy} as year '-' {mm} as month '-' {dd} as day",
);

isoDate.replaceFirstIn("2026-07-04", { month: "12" })
// "2026-12-04"   — year and day unchanged
```

### Captures inside repetitions

When a named capture appears inside a repeated sub-pattern, you can provide a `string[]` to replace each iteration independently:

```typescript
const csv = compile(
  "!replacements-ignore-matching = true\n" +
  "%Any excluding ',' * 1..100 as col (',' %Any excluding ',' * 1..100 as col) * 0..20",
);

csv.replaceFirstIn("alice,bob,carol", { col: ["ALICE", "BOB", "CAROL"] })
// "ALICE,BOB,CAROL"
```

The array length must equal the number of iterations in the actual match. Providing the wrong length throws `PternReplacementError` with `.replacementError.kind === "arrayLengthMismatch"`.

A plain string inside a repetition is **broadcast** — it replaces every iteration with the same value:

```typescript
csv.replaceFirstIn("alice,bob,carol", { col: "X" })
// "X,X,X"
```

### All six replace methods

Each method targets a different region of the input. They return the modified string, or the original if the pattern does not match that region, or throw `PternReplacementError` if a replacement value is invalid.

```typescript
p.replaceAllOf(input, replacements)              // whole string
p.replaceStartOf(input, replacements)            // prefix
p.replaceEndOf(input, replacements)              // suffix
p.replaceFirstIn(input, replacements)            // first occurrence
p.replaceNextIn(input, startIndex, replacements) // first at/after startIndex
p.replaceAllIn(input, replacements)              // all occurrences
```

---

## Substitution

Substitution is the inverse of matching: instead of extracting captures from a string, you provide capture values and assemble a new string from scratch. No original input string is needed.

To enable substitution, add `!substitutable = true`:

```typescript
const isoDate = compile(
  "!substitutable = true\n" +
  "yyyy = %Digit * 4;\n" +
  "mm   = '0' '1'..'9' | '1' '0'..'2';\n" +
  "dd   = '0' '1'..'9' | '1'..'2' %Digit | '3' '0'..'1';\n" +
  "{yyyy} as year '-' {mm} as month '-' {dd} as day",
);

isoDate.substitute({ year: "2026", month: "07", day: "04" })
// "2026-07-04"
```

`substitute` returns a `string` or throws `PternSubstitutionError`. Error kinds include:

| `.substitutionError.kind` | Meaning |
|:--------------------------|:--------|
| `"notSubstitutable"`      | Pattern was compiled without `!substitutable = true` |
| `"missingCapture"`        | A required capture name was not provided |
| `"captureMismatch"`       | Provided value does not match the capture's sub-pattern |
| `"noMatchingBranch"`      | No alternation branch could be satisfied |
| `"arrayLengthError"`      | Array length is outside the repetition bounds |

### Alternation in substitution

In a substitutable alternation, the first branch whose required captures are all present is selected:

```typescript
const yearOrWord = compile(
  "!substitutable = true\n" +
  "%Digit * 4 as year | %Alpha * 1..20 as word",
);

yearOrWord.substitute({ year: "2026" })   // "2026" — first branch selected
yearOrWord.substitute({ word: "hello" })  // "hello" — second branch selected
yearOrWord.substitute({})                 // throws PternSubstitutionError (noMatchingBranch)
```

### Repeated captures in substitution

An array of values drives the iteration count for a bounded repetition:

```typescript
const csv = compile(
  "!substitutable = true\n" +
  "field = %Any excluding ',' * 1..100;\n" +
  "{field} as col (',' {field} as col) * 0..20",
);

csv.substitute({ col: ["name", "age", "city"] })
// "name,age,city"
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

```typescript
// NOT expressible as a single ptern: at least one lowercase, one uppercase, one digit.
// Use several pterns tested independently:

const hasLower   = compile("%Lower * 1..?");
const hasUpper   = compile("%Upper * 1..?");
const hasDigit   = compile("%Digit * 1..?");
const longEnough = compile("%Any * 8..?");

function isValidPassword(s: string): boolean {
  return hasLower.matchesIn(s)
    && hasUpper.matchesIn(s)
    && hasDigit.matchesIn(s)
    && longEnough.matchesAllOf(s);
}
```

Simultaneous lookahead requirements are not expressible as a single ptern. Use multiple pterns and combine the results in code. Compile patterns once and keep them as module-level constants.

---

## Compile Errors

`compile()` throws `PternCompileError` if the source is invalid. The `.compileError` property carries the structured error:

```typescript
import { compile, PternCompileError } from "@ptern/tern";
import type { CompileError } from "@ptern/tern";

try {
  compile("''");
} catch (e) {
  if (e instanceof PternCompileError) {
    const err: CompileError = e.compileError;
    switch (err.kind) {
      case "lexError":
        console.error("Lex error:", err.error.kind);
        break;
      case "parseError":
        console.error("Parse error:", err.error.kind);
        break;
      case "semanticErrors":
        for (const se of err.errors) {
          console.error("Semantic error:", se.kind);
        }
        break;
    }
  }
}
```

Common semantic error kinds: `emptyLiteral`, `unusedDefinition`, `undefinedName`, `circularDefinition`, `unknownAnnotation`, `fewestOnExactRepetition`, `ambiguousRepetitionBody`, `ambiguousAdjacentRepetition`.

---

## Formatting

The `format()` function takes a ptern source string and returns a canonically formatted version. It is useful for normalising hand-written pterns and building editor integrations.

```typescript
import { format } from "@ptern/tern";

const source = "!case-insensitive=true\nword=%Alpha*1..?;\n{word}";

format(source)
// "!case-insensitive = true\n\nword = %Alpha * 1..? ;\n\n{word}"
```

Formatting succeeds as long as the source lexes and parses — semantic errors do not prevent it. `format()` throws `PternFormatError` on lex or parse failure, or if `lineWidth < 40`.

### FormatOptions

```typescript
import { format, defaultFormatOptions } from "@ptern/tern";
import type { FormatOptions } from "@ptern/tern";

// Defaults:
const opts: FormatOptions = {
  lineWidth: 80,   // maximum line length; must be >= 40
  compact:   false, // strip optional whitespace around operators
  aligned:   true,  // align = signs within annotation and definition blocks
  reordered: false, // reorder definitions into dependency order
};
```

### What the formatter does

**Output structure.** Sections are emitted in this order:

1. Annotation block (annotations sorted lexicographically by name)
2. Blank separator (when annotations and a subsequent section are present, and `compact: false`)
3. Definition block (in source order, or topological order when `reordered: true`)
4. Blank separator (when definitions and the body are present, and `compact: false`)
5. Body expression

**Token normalisation.** String literals are normalised to single-quote delimiters. Double quotes are used only when the literal content contains a single-quote character. Character class names are normalised to title case (`%Alpha`, `%Digit`, etc.).

**Alignment.** When `aligned: true` (the default), the `=` signs within each block are aligned to a common column:

```
// Input (misaligned):
// !case-insensitive = true
// !multiline = true
// !substitutable = true
//
// Formatted (aligned: true):
// !case-insensitive = true
// !multiline        = true
// !substitutable    = true
```

**Line breaking.** Long lines are broken at the rightmost sequence space, then before the rightmost outer `|`. Lines that cannot be broken within `lineWidth` are emitted at their natural length.

### Compact mode

Setting `compact: true` removes optional whitespace around operators and suppresses blank separator lines:

```typescript
format("( 'a' | 'b' ) * 3", { ...defaultFormatOptions, compact: true })
// "('a'|'b')*3"
```

### Reordering definitions

When `reordered: true`, definitions are sorted into topological layers — dependencies come before the definitions that reference them — and alphabetically within each layer:

```typescript
const source = "full = {first} ' ' {last} ;\nfirst = %Alpha * 1..? ;\nlast = %Alpha * 1..? ;";
format(source, { ...defaultFormatOptions, reordered: true })
// "first = %Alpha * 1..? ;\nlast  = %Alpha * 1..? ;\n\nfull  = {first} ' ' {last} ;"
```

### Idempotency

Formatting is idempotent: applying `format` to already-formatted output returns the same string.

```typescript
const once  = format(source);
const twice = format(once);
once === twice   // true
```

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

| Annotation                              | Default | Meaning |
|:----------------------------------------|:-------:|:--------|
| `!allow-backtracking = true`            | `false` | Suppress all compile-time backtracking safety checks |
| `!case-insensitive = true`              | `false` | Literals and ranges match both cases |
| `!multiline = true`                     | `false` | `@line-start`/`@line-end` match per-line (also set automatically by those assertions) |
| `!replacements-ignore-matching = true`  | `false` | Skip validation of replacement values |
| `!substitutable = true`                 | `false` | Enable `substitute()` and check substitutability at compile time |
| `!substitutions-ignore-matching = true` | `false` | Skip validation in `substitute()` (requires `!substitutable = true`) |

---

## Appendix C: Operator Precedence

Tightest binding first:

| Operator | Example |
|:---------|:--------|
| `( )` grouping, `{ }` interpolation | `('a' \| 'b') * 3` |
| `..` character range | `'a'..'z'` |
| `excluding` set difference | `%Alpha excluding 'q'` |
| `*` repetition | `%Digit * 4` |
| `fewest` lazy modifier | `%Any * 1..? fewest` |
| `as` capture | `%Digit * 4 as year` |
| sequence (space) | `'hello' ' ' 'world'` |
| `\|` alternation | `'cat' \| 'dog'` |
