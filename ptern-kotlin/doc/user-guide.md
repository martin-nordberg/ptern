# Ptern User Guide — Kotlin API

> **See also:** [Gleam User Guide](../../ptern-gleam/doc/user-guide.md) for the Gleam edition, or [TypeScript User Guide](../../ptern-typescript/doc/user-guide.md) for the `@ptern/tern` edition.

Ptern is a pattern language that compiles to regular expressions. It is designed to be readable first — every construct is either a plain keyword or punctuation that carries an obvious meaning. You should be able to read a ptern aloud and have it make sense.

This guide builds up the language from scratch, introducing each concept with working examples. The formal specification (`ptern-specification.md`) is the complete reference; this guide is the on-ramp.

All examples assume:

```kotlin
import io.ptern.Ptern
import io.ptern.ReplacementValue
```

The Kotlin edition compiles each ptern to a `java.util.regex.Pattern` and runs on the JVM — there is no JavaScript runtime involved. The language and its semantics are identical to the Gleam and TypeScript editions; only the surrounding API is idiomatic Kotlin.

---

## A First Taste

Here is a ptern that matches an ISO date:

```
%Digit * 4 as year '-' %Digit * 2 as month '-' %Digit * 2 as day
```

Read it aloud: "four digits captured as year, a dash, two digits captured as month, a dash, two digits captured as day." It is longer than the equivalent regular expression (`\d{4}-\d{2}-\d{2}`) but leaves nothing to interpret.

With the Kotlin API:

```kotlin
val isoDate = Ptern.compile(
    "%Digit * 4 as year '-' %Digit * 2 as month '-' %Digit * 2 as day"
)
```

**Boolean test:**

```kotlin
isoDate.matchesAllOf("2026-07-04")                    // true
isoDate.matchesAllOf("2026-7-4")                      // false — single-digit month/day
isoDate.matchesIn("Event on 2026-07-04 at noon")      // true
```

**Occurrence match:**

```kotlin
isoDate.matchFirstIn("Event on 2026-07-04 at noon")
// MatchOccurrence(index=9, length=10, captures={year=2026, month=07, day=04})
```

**Replacement:**

```kotlin
isoDate.replaceFirstIn(
    "Event on 2026-07-04 at noon",
    mapOf("year" to ReplacementValue.Scalar("2027")),
)
// "Event on 2027-07-04 at noon"
// month and day are untouched because they were not in the replacements map
```

**Substitution** (assembling a string from scratch):

```kotlin
val isoDateSub = Ptern.compile(
    """
    !substitutable = true
    %Digit * 4 as year '-' %Digit * 2 as month '-' %Digit * 2 as day
    """.trimIndent()
)

isoDateSub.substitute(
    mapOf(
        "year" to ReplacementValue.Scalar("2026"),
        "month" to ReplacementValue.Scalar("07"),
        "day" to ReplacementValue.Scalar("04"),
    )
)
// "2026-07-04"
```

These four operations — boolean test, occurrence match, replacement, substitution — are the core of what ptern does. The rest of this guide explains how to write patterns that drive them.

---

## Literals

The simplest pattern is a literal string:

```kotlin
val hello = Ptern.compile("'hello'")

hello.matchesAllOf("hello")   // true
hello.matchesAllOf("Hello")   // false — case matters by default
hello.matchesAllOf("hello!")  // false — exact match required for matchesAllOf
hello.matchesIn("say hello")  // true — matchesIn finds it anywhere
```

Literals can use either single or double quotes. The two forms are identical:

```kotlin
Ptern.compile("'hello'")    // same as
Ptern.compile("\"hello\"")
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

```kotlin
Ptern.compile("'\\t'")        // ptern for a tab character
Ptern.compile("'can\\'t'")    // ptern matching "can't"
Ptern.compile("'é'")          // ptern matching 'é'
```

---

## Sequences

Place two patterns side by side (with a space between them) to match one followed by the other:

```kotlin
val greeting = Ptern.compile("'hello' ' ' 'world'")

greeting.matchesAllOf("hello world")   // true
greeting.matchesAllOf("helloworld")    // false — space is required
```

**The space between patterns is the sequence operator.** It is not just formatting; it is what makes one pattern follow another. This is intentional: it forces you to write patterns that are easy to read by preventing everything from running together.

You can sequence as many pieces as you like:

```kotlin
val dateWithSlashes = Ptern.compile("%Digit * 2 '/' %Digit * 2 '/' %Digit * 4")

dateWithSlashes.matchesAllOf("04/28/2026")   // true
```

---

## Alternatives

Use `|` to match any one of several options:

```kotlin
val yesOrNo = Ptern.compile("'yes' | 'no'")

yesOrNo.matchesAllOf("yes")    // true
yesOrNo.matchesAllOf("no")     // true
yesOrNo.matchesAllOf("maybe")  // false
```

Alternatives can themselves contain sequences:

```kotlin
val httpOrHttps = Ptern.compile("'http' '://' | 'https' '://'")

httpOrHttps.matchesStartOf("https://example.com")  // true
httpOrHttps.matchesStartOf("ftp://example.com")    // false
```

When a pattern matches, the **first** matching alternative (left to right) is selected. This matters when alternatives overlap.

---

## Grouping

Parentheses `( )` override precedence and let you treat a compound expression as a single unit:

```kotlin
// Without grouping: three separate alternatives
Ptern.compile("'a' | 'b' | 'c'")

// With grouping: one of 'a', 'b', or 'c', followed by a digit
Ptern.compile("('a' | 'b' | 'c') %Digit")
```

```kotlin
val colorKeyword = Ptern.compile("'color' | 'colour'")       // two full alternatives
val colourAlt    = Ptern.compile("'colo' ('u') * 0..1 'r'")  // optional 'u'
```

Grouping is also how you apply repetition to a multi-element pattern (see Repetition below).

---

## Character Classes

A character class matches any **single character** from a named set. They are written with a `%` prefix:

```kotlin
val digit   = Ptern.compile("%Digit")  // matches any of 0–9
val letter  = Ptern.compile("%Alpha")  // matches any of a–z or A–Z
val alnum   = Ptern.compile("%Alnum")  // matches any letter or digit
val anyChar = Ptern.compile("%Any")    // matches any single character including newline
val wordCh  = Ptern.compile("%Word")   // matches a–z, A–Z, 0–9, _
```

```kotlin
digit.matchesAllOf("7")     // true
digit.matchesAllOf("a")     // false
letter.matchesAllOf("Q")    // true
anyChar.matchesAllOf("\n")  // true
```

Character classes pair naturally with repetition:

```kotlin
val word  = Ptern.compile("%Alpha * 1..?")          // one or more letters
val ident = Ptern.compile("%Alpha %Alnum * 0..?")   // letter then letters-or-digits
```

For matching Unicode text beyond ASCII, use Unicode category classes:

```kotlin
Ptern.compile("%L * 1..?")   // one or more Unicode letters (any script)
Ptern.compile("%N * 1..?")   // one or more Unicode numbers
Ptern.compile("%Lu")         // one uppercase Unicode letter
Ptern.compile("%Ll")         // one lowercase Unicode letter
```

A full list of all character class names is in [Appendix A](#appendix-a-character-class-reference).

---

## Character Ranges

Match any single character within an inclusive range using `..`:

```kotlin
val lowerLetter  = Ptern.compile("'a'..'z'")
val upperLetter  = Ptern.compile("'A'..'Z'")
val singleDigit  = Ptern.compile("'0'..'9'")
val hexDigitPart = Ptern.compile("'a'..'f'")
```

```kotlin
lowerLetter.matchesAllOf("m")    // true
lowerLetter.matchesAllOf("M")    // false
lowerLetter.matchesAllOf("mm")   // false — exactly one character
```

Both endpoints must be single characters. The range must not be inverted (`'z'..'a'` is an error).

Ranges compose with sequences and repetition just like any other expression:

```kotlin
// A hexadecimal digit
val hexDigit = Ptern.compile("'0'..'9' | 'a'..'f' | 'A'..'F'")

// An octal number
val octal = Ptern.compile("'0' '0'..'7' * 1..?")
```

---

## Set Difference

`excluding` removes characters from a single-character set:

```kotlin
// Any character except a double quote
val nonQuote     = Ptern.compile("%Any excluding '\"'")

// Any digit except 0
val nonZeroDigit = Ptern.compile("%Digit excluding '0'")

// Any digit except 8 or 9
val octalDigit   = Ptern.compile("%Digit excluding '8'..'9'")
```

Both sides of `excluding` must match exactly one character. When both sides are the same expression — `%Digit excluding %Digit`, `'x' excluding 'x'`, or `'a'..'z' excluding 'a'..'z'` — the result would be an empty character class, so the compiler rejects the pattern. Semantically equivalent but textually distinct pairs (e.g. `%Digit excluding '0'..'9'`) are not caught at compile time.

A practical use: matching the contents of a quoted string without letting a closing quote slip through:

```kotlin
val quotedString = Ptern.compile("'\"' (%Any excluding '\"') * 0..? '\"'")

quotedString.matchesAllOf("\"hello world\"")   // true
```

---

## Repetition

Repeat a pattern with `*`:

### Fixed count

```kotlin
val fourDigits   = Ptern.compile("%Digit * 4")   // exactly 4
val threeLetters = Ptern.compile("%Alpha * 3")   // exactly 3

fourDigits.matchesAllOf("2026")    // true
fourDigits.matchesAllOf("202")     // false
fourDigits.matchesAllOf("20261")   // false
```

### Bounded range

```kotlin
val twoToFour = Ptern.compile("%Digit * 2..4")   // 2, 3, or 4 digits

twoToFour.matchesAllOf("12")      // true
twoToFour.matchesAllOf("1234")    // true
twoToFour.matchesAllOf("1")       // false
twoToFour.matchesAllOf("12345")   // false
```

### Optional (zero or one)

`* 0..1` is the idiomatic "maybe once" form:

```kotlin
val optionalSign = Ptern.compile("('+' | '-') * 0..1 %Digit * 1..?")

optionalSign.matchesAllOf("42")     // true
optionalSign.matchesAllOf("+42")    // true
optionalSign.matchesAllOf("-42")    // true
optionalSign.matchesAllOf("+-42")   // false
```

### Unbounded (at least N)

`* n..?` means "n or more":

```kotlin
val oneOrMore  = Ptern.compile("%Digit * 1..?")   // at least one
val zeroOrMore = Ptern.compile("%Digit * 0..?")   // any number
```

### Repeating a group

Apply `*` to a grouped expression to repeat a multi-element sequence:

```kotlin
// Three groups of four digits separated by dashes
val creditCard = Ptern.compile("%Digit * 4 ('-' %Digit * 4) * 3")

creditCard.matchesAllOf("1234-5678-9012-3456")  // true
```

### Lazy repetition: `fewest`

By default, repetition is **greedy** — it consumes as many iterations as possible while still allowing the overall pattern to match. Add `fewest` after any variable-count repetition to make it **lazy**: prefer the fewest iterations that still allow the pattern to match.

```kotlin
// Greedy — %Any * 1..? swallows as far as possible before stopping at '</'
val greedy = Ptern.compile("'<' %Alpha * 1..? '>' %Any * 1..? '</'")
greedy.matchFirstIn("<b>hello</b><em>world</em>")
// index 0, length 23 — runs all the way to the last '</'

// Lazy — stops at the first '</'
val lazyP = Ptern.compile("'<' %Alpha * 1..? '>' %Any * 1..? fewest '</'")
lazyP.matchFirstIn("<b>hello</b><em>world</em>")
// index 0, length 10 — stops at the first '</'
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

```kotlin
// Single-char delimiter — use excluding (no backtracking)
val quoted = Ptern.compile("'\"' %Any excluding '\"' * 0..? '\"'")

// Multi-char end delimiter — use fewest
val bold = Ptern.compile("'<b>' %Any * 0..? fewest '</b>'")
```

Lazy repetition is still subject to the same compile-time backtracking safety checks as greedy repetition. A `fewest` quantifier on a structurally ambiguous pattern still requires `!allow-backtracking = true`.

---

## Named Captures

Add `as name` to any expression to capture the matched text under that name:

```kotlin
val yearP = Ptern.compile("%Digit * 4 as year")

yearP.matchFirstIn("The year is 2026")
// MatchOccurrence(index=12, length=4, captures={year=2026})
```

The `captures` map in the result maps each capture name to the text that was matched at that position. Names that did not participate in the match (e.g. an unmatched branch of an alternation) are absent.

A capture can wrap any expression, not just atomic ones:

```kotlin
val isoDate = Ptern.compile(
    "%Digit * 4 as year '-' %Digit * 2 as month '-' %Digit * 2 as day"
)

isoDate.matchFirstIn("Published 2026-04-28")
// MatchOccurrence(index=10, length=10, captures={year=2026, month=04, day=28})
```

### Using captures for replacement

Pass a subset of captures in a replacements map to any `replace*` method. Any capture not mentioned retains its original matched value:

```kotlin
isoDate.replaceFirstIn(
    "Published 2026-04-28",
    mapOf("year" to ReplacementValue.Scalar("2027")),
)
// "Published 2027-04-28"   — month and day unchanged

isoDate.replaceAllIn(
    "2026-01-01 and 2026-06-15",
    mapOf("year" to ReplacementValue.Scalar("2027")),
)
// "2027-01-01 and 2027-06-15"
```

### The same name in multiple places

A capture name is allowed to appear more than once in a pattern — the parser and validator do not reject it. What that buys you differs depending on *where* the repeat occurs:

- **Inside a repeated sub-pattern** (`( ... as name ) * n..m`), every iteration's occurrence is tracked independently. This is the array-replacement mechanism described in [Captures inside repetitions](#captures-inside-repetitions) below — a `List<String>` (or a broadcast scalar) reaches every occurrence.
- **At two unrelated, non-repeated positions** in a sequence, only the *first* occurrence is wired up as a real capture group; later occurrences with the same name match the same grammar but do not contribute to `captures`, and are not touched by `replace*`:

```kotlin
val range = Ptern.compile("%Digit * 1..? as n '-' %Digit * 1..? as n")

range.matchFirstIn("12-34")?.captures                                   // {n=12} — only the first occurrence
range.replaceFirstIn("12-34", mapOf("n" to ReplacementValue.Scalar("9"))) // "9-34" — only the first occurrence changes
```

If you need every non-repeated occurrence of a value to move together, give each position its own name and pass the same replacement value to each, or restructure the pattern so the repeated text is expressed as a repetition (see above) or a `{name}` backreference (see [Subpattern Definitions](#subpattern-definitions)).

---

## Subpattern Definitions

For anything beyond a trivial pattern, define named sub-expressions at the top and interpolate them with `{ }`. This is the main readability tool:

```kotlin
val isoDate = Ptern.compile(
    """
    yyyy = %Digit * 4;
    mm   = '0' '1'..'9' | '1' '0'..'2';
    dd   = '0' '1'..'9' | '1'..'2' %Digit | '3' '0'..'1';
    {yyyy} as year '-' {mm} as month '-' {dd} as day
    """.trimIndent()
)
```

Each definition is `name = pattern ;`. The final line (no semicolon) is the body expression that actually matches. Definitions may reference other definitions.

Every definition must be used — if a definition's name never appears in a `{name}` that is reachable (directly or through other definitions) from the body expression, the pattern fails to compile with an `UnusedDefinition` error. This catches dead code early and keeps patterns free of stale definitions.

Definitions make the individual pieces testable in isolation and make the body readable at a glance. Compare the body to its equivalent regex fragment — `(\d{4})-(0[1-9]|1[0-2])-(0[1-9]|[12]\d|3[01])` — and the ptern wins on readability every time.

### Interpolation vs. backreference

`{name}` means different things depending on what `name` refers to:

- If `name` is a **definition**, `{name}` expands to that definition's pattern — it matches the same strings the definition matches.
- If `name` is a **capture** (established earlier by `expression as name`), `{name}` is a **backreference** — it matches the exact text that was captured earlier, as if it were a literal.

A classic use of backreferences is detecting doubled words or matching paired delimiters:

```kotlin
// Detects a repeated word separated by a space
val doubled = Ptern.compile("%Alpha * 1..? as word ' ' {word}")

doubled.matchesAllOf("hello hello")   // true
doubled.matchesAllOf("hello world")   // false — different words
doubled.matchesIn("the the problem")  // true — finds "the the"
```

```kotlin
// Matches XML-like open/close tags where the tag names must agree
val element = Ptern.compile(
    "'<' %Alpha * 1..20 as tag '>' %Any * 0..10000 '</' {tag} '>'"
)

element.matchesAllOf("<em>hello</em>")    // true
element.matchesAllOf("<em>hello</div>")   // false — mismatched tags
```

Note that a backreference matches a runtime-determined string, so the backtracking checker models its character set as the same as the capture expression's. Patterns that are safe — even when a backreference appears adjacent to a variable-length repetition — compile without warnings. Use `!allow-backtracking = true` only if the static checks flag a pattern you have verified to be safe.

---

## Annotations

Annotations appear at the very top of a ptern, before any definitions. They configure how the entire pattern compiles or behaves.

### `!case-insensitive = true`

Makes literals and character ranges match both uppercase and lowercase:

```kotlin
val keyword = Ptern.compile(
    """
    !case-insensitive = true
    'select' | 'from' | 'where'
    """.trimIndent()
)

keyword.matchesAllOf("SELECT")   // true
keyword.matchesAllOf("From")     // true
keyword.matchesAllOf("WHERE")    // true
```

### `!multiline = true`

Makes `@line-start` and `@line-end` match at the boundary of each line instead of the whole string. The annotation is also enabled automatically whenever `@line-start` or `@line-end` appears in the pattern (see Position Assertions below).

Unlike the Gleam and TypeScript editions, the Kotlin port anchors `matchesAllOf`, `matchStartOf`, and `matchEndOf` with the absolute string boundaries `\A`/`\z` rather than `^`/`$`. This means `!multiline` in Kotlin only changes the behaviour of `@line-start`/`@line-end` themselves — it does not make `matchesAllOf` (and friends) treat any single line of a multi-line input as a full match the way the other editions do.

### `!replacements-ignore-matching = true`

In the Gleam and TypeScript editions, replacement validates each provided value against the sub-pattern for that capture by default, and this annotation disables that validation. **The current Kotlin port does not yet perform that validation at all** — `replace*` methods accept any string as a replacement value regardless of whether it would have matched the capture's sub-pattern, and this annotation has no additional effect. `ReplacementError.InvalidReplacementValue` and `ReplacementError.WrongReplacementType` are declared in the API for parity with the other editions but are not currently thrown. See [Validation](#validation) below.

### `!allow-backtracking = true`

By default, the compiler rejects patterns that could cause catastrophic backtracking in the JVM regex engine. Three checks are run on any pattern that contains variable-count repetitions (`* n..m` with `n < m`, or `* n..?`); exact-count repetitions (`* n`) are exempt.

**Overlapping alternation branches in a repetition** — if two branches of an alternation share characters at the boundary between iterations, `AmbiguousRepetitionAdjacency` is reported:

```kotlin
// Error: 'a' and 'ab' both start with 'a' — engine cannot tell them apart
Ptern.compile("('a' | 'ab') * 1..?")

// OK: %Alpha and '_' are disjoint
Ptern.compile("(%Alpha | '_') * 1..?")

// OK: %Alpha and %Digit are disjoint
Ptern.compile("(%Alpha | %Digit) * 1..?")
```

**Variable-length body that overlaps itself** — if the body of a variable-count repetition is variable-length and its last and first character sets overlap, `AmbiguousRepetitionBody` is reported. A fixed-length body is never flagged:

```kotlin
// Error: inner repetition is variable-length; %Alpha∩%Alpha ≠ ∅
Ptern.compile("(%Alpha * 1..?) * 1..?")

// OK: last=%Digit, first='x' — disjoint
Ptern.compile("('x' %Digit * 1..?) * 1..?")

// OK: body %Digit is fixed length 1
Ptern.compile("(%Digit) * 1..?")
```

**Adjacent unbounded repetitions** — two directly adjacent unbounded repetitions with overlapping character sets produce `AmbiguousAdjacentRepetition`. A bounded repetition (`* n..m`) on either side avoids the check:

```kotlin
// Error: both unbounded, %Digit∩%Digit ≠ ∅
Ptern.compile("%Digit * 1..? %Digit * 1..?")

// OK: literal '-' separates them
Ptern.compile("%Digit * 1..? '-' %Digit * 1..?")

// OK: first repetition is bounded (* 1..5)
Ptern.compile("%Alpha * 1..5 %Alpha * 1..?")
```

When a pattern is structurally safe but the static analysis cannot prove it, set `!allow-backtracking = true` to opt out. A real example is a double-quoted string that allows escaped quotes:

```kotlin
val dqString = Ptern.compile(
    """
    !allow-backtracking = true
    char = %Any excluding '"';
    '"' ({char} | '\"') * 0..1000 '"'
    """.trimIndent()
)

dqString.matchesAllOf("\"hello\"")            // true
dqString.matchesAllOf("\"say \\\"hi\\\"\"")   // true — escaped inner quotes
```

The body `({char} | '\"')` has branches of different lengths: `{char}` matches one character, and `'\"'` matches two (`\` then `"`). This makes the body variable-length, and `AmbiguousRepetitionBody` fires because the last character of one iteration can be `"` (from `'\"'`), which overlaps with the first character of the next. In practice the pattern is safe — the outer `'"'` terminates the string and cannot be confused with the `"` inside `'\"'` — but the static check cannot see that structural guarantee.

Note that many patterns that look like they need `!allow-backtracking` can instead be fixed by tightening the character sets. A CSV field defined as `%Any * 1..100` triggers `AmbiguousRepetitionBody` (last char `%Any` overlaps first char `','`), but rewriting it as `%Any excluding ',' * 1..100` removes the overlap entirely and is also more semantically correct.

---

## Position Assertions

Position assertions match a **position** in the string, not a character. They are zero-width — they do not consume any input.

| Assertion     | Matches the position… |
|:--------------|:----------------------|
| `@word-start` | Between a non-word and a word character (start of a word) |
| `@word-end`   | Between a word and a non-word character (end of a word) |
| `@line-start` | At the start of a line (enables multiline mode) |
| `@line-end`   | At the end of a line (enables multiline mode) |

```kotlin
val wholeWord = Ptern.compile("@word-start %Alpha * 1..? @word-end")

wholeWord.matchesIn("say hello there")  // true  — "hello" is a whole word
wholeWord.matchesIn("123")              // false — no alphabetic word
```

Without the word boundaries, `%Alpha * 1..?` would match the alphabetic portion of `"hello123"`. With them, only a standalone word matches:

```kotlin
val un = Ptern.compile("@word-start 'un'")

un.matchesIn("undo")   // true  — "un" is at a word start
un.matchesIn("fun")    // false — "un" is mid-word
```

For line-anchored patterns, `@line-start` and `@line-end` work across multiple lines when multiline mode is active:

```kotlin
val lineNumber = Ptern.compile("@line-start %Digit * 1..?")

lineNumber.matchAllIn("1 first\n2 second\n3 third")
// three occurrences: index 0, index 8, index 17
```

---

## All Match Operations

Every ptern exposes the same set of matching operations. They differ only in where they anchor the match:

| Method                                          | Where it looks                       | Returns |
|:-------------------------------------------------|:-------------------------------------|:--------|
| `matchesAllOf(s)`                               | Must cover the whole string          | `Boolean` |
| `matchesStartOf(s)`                             | Must start at index 0                | `Boolean` |
| `matchesEndOf(s)`                               | Must end at `s.length`               | `Boolean` |
| `matchesIn(s)`                                  | Anywhere in the string               | `Boolean` |
| `matchAllOf(s)`                                 | Must cover the whole string          | `MatchOccurrence?` |
| `matchStartOf(s)`                               | Must start at index 0                | `MatchOccurrence?` |
| `matchEndOf(s)`                                 | Must end at `s.length`               | `MatchOccurrence?` |
| `matchFirstIn(s)`                               | First occurrence anywhere            | `MatchOccurrence?` |
| `matchNextIn(s, startIndex)`                    | First occurrence at or after `startIndex` | `MatchOccurrence?` |
| `matchAllIn(s)`                                 | Every non-overlapping occurrence     | `List<MatchOccurrence>` |

A `MatchOccurrence` is a data class carrying:
- `index: Int` — start position in the string
- `length: Int` — length of the matched substring
- `captures: Map<String, String>` — capture names mapped to their matched strings

```kotlin
val version = Ptern.compile(
    """
    num = %Digit * 1..10;
    {num} as major '.' {num} as minor '.' {num} as patch
    """.trimIndent()
)

version.matchFirstIn("Using package v1.23.456 in production")
// MatchOccurrence(index=15, length=8, captures={major=1, minor=23, patch=456})

version.matchAllIn("v1.0.0 and v2.3.4")
// [
//   MatchOccurrence(index=1,  length=5, captures={major=1, minor=0, patch=0}),
//   MatchOccurrence(index=12, length=5, captures={major=2, minor=3, patch=4}),
// ]
```

`matchNextIn` is useful for iterating through matches manually:

```kotlin
fun collectCaptures(p: Ptern, input: String, key: String): List<String> {
    val results = mutableListOf<String>()
    var pos = 0
    var m = p.matchNextIn(input, pos)
    while (m != null) {
        m.captures[key]?.let { results.add(it) }
        pos = m.index + m.length
        m = p.matchNextIn(input, pos)
    }
    return results
}

val num = Ptern.compile("%Digit * 1..? as n")
collectCaptures(num, "a1b22c333", "n")
// ["1", "22", "333"]
```

For the common case of collecting all matches, `matchAllIn` is more concise:

```kotlin
val num = Ptern.compile("%Digit * 1..? as n")
num.matchAllIn("a1b22c333").mapNotNull { it.captures["n"] }
// ["1", "22", "333"]
```

---

## Length Metadata

`minLength` and `maxLength` are properties on a compiled `Ptern` holding the shortest and longest string the pattern can match, computed at compile time:

```kotlin
val p = Ptern.compile("%Digit * 2..4")
p.minLength   // 2
p.maxLength   // 4

val q = Ptern.compile("%Digit * 1..?")
q.minLength   // 1
q.maxLength   // null — unbounded
```

Position assertions contribute zero to both bounds. This lets you use ptern as a quick validity check — if an input string's length is already outside `[minLength, maxLength]`, you can skip the regex entirely.

---

## Replacement in Depth

Replacement modifies a string by substituting new text at the positions of named captures, leaving everything else unchanged.

### Validation

In the Gleam and TypeScript editions, each replacement value is validated by default against the sub-pattern for its capture, and a value that would not have matched the original pattern is rejected. **The current Kotlin port does not yet perform this validation:**

```kotlin
val p = Ptern.compile("%Digit * 4 as year")

p.replaceFirstIn("2026", mapOf("year" to ReplacementValue.Scalar("2027")))  // "2027"
p.replaceFirstIn("2026", mapOf("year" to ReplacementValue.Scalar("abc")))   // "abc" — accepted, not rejected
```

If you need to guard against invalid replacement values in Kotlin today, validate them yourself before calling `replace*` (for example, by running the sub-pattern through its own `Ptern.compile(...).matchesAllOf(...)` check).

### Multiple captures

Any subset of captures may appear in the replacements map. Omitted captures retain their original values:

```kotlin
val isoDate = Ptern.compile(
    """
    yyyy = %Digit * 4;
    mm   = '0' '1'..'9' | '1' '0'..'2';
    dd   = '0' '1'..'9' | '1'..'2' %Digit | '3' '0'..'1';
    {yyyy} as year '-' {mm} as month '-' {dd} as day
    """.trimIndent()
)

isoDate.replaceFirstIn("2026-07-04", mapOf("month" to ReplacementValue.Scalar("12")))
// "2026-12-04"   — year and day unchanged
```

### Round-trip consistency

If you match a string and pass the captured values back as replacements, you get the original string:

```kotlin
val m = isoDate.matchFirstIn("2026-07-04")!!
val replacements = m.captures.mapValues { (_, v) -> ReplacementValue.Scalar(v) }
isoDate.replaceAllOf("2026-07-04", replacements)
// "2026-07-04" — identity
```

### Captures inside repetitions

When a named capture appears inside a repeated sub-pattern, you can provide a `ReplacementValue.Array` to replace each iteration independently:

```kotlin
val csv = Ptern.compile(
    """
    !replacements-ignore-matching = true
    %Any excluding ',' * 1..100 as col (',' %Any excluding ',' * 1..100 as col) * 0..20
    """.trimIndent()
)

csv.replaceFirstIn(
    "alice,bob,carol",
    mapOf("col" to ReplacementValue.Array(listOf("ALICE", "BOB", "CAROL"))),
)
// "ALICE,BOB,CAROL"
```

The array length must equal the number of iterations in the actual match. Providing the wrong length throws `PternReplacementException` with a `ReplacementError.ArrayLengthMismatch`.

A `ReplacementValue.Scalar` inside a repetition is **broadcast** — it replaces every iteration with the same value:

```kotlin
csv.replaceFirstIn("alice,bob,carol", mapOf("col" to ReplacementValue.Scalar("X")))
// "X,X,X"
```

If the same capture name appears both inside and outside a repetition, the array's first element fills the non-repeated occurrence and the remaining elements fill the iterations.

### All six replace methods

Each method targets a different region of the input. They return the modified string, or the original string if the pattern does not match that region, or throw `PternReplacementException` if a replacement value is invalid.

```kotlin
p.replaceAllOf(input, replacements)                    // whole string
p.replaceStartOf(input, replacements)                  // prefix
p.replaceEndOf(input, replacements)                    // suffix
p.replaceFirstIn(input, replacements)                  // first occurrence
p.replaceNextIn(input, startIndex, replacements)       // first at/after startIndex
p.replaceAllIn(input, replacements)                    // all occurrences
```

---

## Substitution

Substitution is the inverse of matching: instead of extracting captures from a string, you provide capture values and assemble a new string from scratch. No original input string is needed.

To enable substitution, add `!substitutable = true`:

```kotlin
val isoDate = Ptern.compile(
    """
    !substitutable = true
    yyyy = %Digit * 4;
    mm   = '0' '1'..'9' | '1' '0'..'2';
    dd   = '0' '1'..'9' | '1'..'2' %Digit | '3' '0'..'1';
    {yyyy} as year '-' {mm} as month '-' {dd} as day
    """.trimIndent()
)

isoDate.substitute(
    mapOf(
        "year" to ReplacementValue.Scalar("2026"),
        "month" to ReplacementValue.Scalar("07"),
        "day" to ReplacementValue.Scalar("04"),
    )
)
// "2026-07-04"
```

`substitute` returns a `String` or throws `PternSubstitutionException`. The `.error: SubstitutionError` sealed class carries:

| Variant | Meaning |
|:--------|:--------|
| `NotSubstitutable`         | Pattern was compiled without `!substitutable = true` |
| `MissingCapture(name)`     | A required capture name was not provided |
| `CaptureMismatch(name)`    | Provided value does not match the capture's sub-pattern |
| `NoMatchingBranch`         | No alternation branch could be satisfied |
| `ArrayLengthError(name)`   | Array length is outside the repetition bounds |

Unlike `replace*`, `substitute` in Kotlin *does* validate provided values against each capture's sub-pattern (subject to `!substitutions-ignore-matching`), matching the Gleam and TypeScript editions.

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

In a substitutable alternation, the first branch whose required captures are all present is selected:

```kotlin
val yearOrWord = Ptern.compile(
    """
    !substitutable = true
    %Digit * 4 as year | %Alpha * 1..20 as word
    """.trimIndent()
)

yearOrWord.substitute(mapOf("year" to ReplacementValue.Scalar("2026")))
// "2026" — first branch selected because 'year' is provided

yearOrWord.substitute(mapOf("word" to ReplacementValue.Scalar("hello")))
// "hello" — second branch selected because 'word' is provided

yearOrWord.substitute(emptyMap())
// throws PternSubstitutionException (NoMatchingBranch) — neither branch can be satisfied
```

A branch made entirely of literals is always eligible and acts as a fallback. If no branch can succeed, `substitute` throws with `NoMatchingBranch`.

### Repeated captures in substitution

An array of values drives the iteration count for a bounded repetition:

```kotlin
val csv = Ptern.compile(
    """
    !substitutable = true
    field = %Any excluding ',' * 1..100;
    {field} as col (',' {field} as col) * 0..20
    """.trimIndent()
)

csv.substitute(mapOf("col" to ReplacementValue.Array(listOf("name", "age", "city"))))
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

```kotlin
// NOT expressible as a single ptern: at least one lowercase, one uppercase, one digit.
// Use several pterns tested independently:

val hasLower = Ptern.compile("%Lower * 1..?")
val hasUpper = Ptern.compile("%Upper * 1..?")
val hasDigit = Ptern.compile("%Digit * 1..?")
val longEnough = Ptern.compile("%Any * 8..?")

fun isValidPassword(s: String): Boolean =
    hasLower.matchesIn(s) &&
        hasUpper.matchesIn(s) &&
        hasDigit.matchesIn(s) &&
        longEnough.matchesAllOf(s)
```

Simultaneous lookahead requirements are not expressible as a single ptern. Use multiple pterns and combine the results in code. Compile patterns once and keep them as top-level `val`s or fields, not local variables re-created on every call.

---

## Compile Errors

`Ptern.compile(...)` throws `PternCompileException` if the source is invalid. Its `.error: CompileError` property carries the structured error:

```kotlin
import io.ptern.CompileError
import io.ptern.PternCompileException
import io.ptern.Ptern

try {
    Ptern.compile("''")
} catch (e: PternCompileException) {
    when (val err = e.error) {
        is CompileError.LexError -> println("Lex error: ${err.message}")
        is CompileError.ParseError -> println("Parse error: ${err.message}")
        is CompileError.SemanticErrors -> err.errors.forEach { println("Semantic error: $it") }
    }
}
```

`CompileError.SemanticErrors` carries the string representation of each `SemanticError` (e.g. `"EmptyLiteral"`, `"UnusedDefinition(name=foo)"`) rather than a typed variant per error, since `Validator`/`Resolver`/the backtracking checker in this edition report errors as an internal sealed class not exposed publicly. Common semantic error names: `EmptyLiteral`, `UnusedDefinition`, `UndefinedReference`, `CircularDefinition`, `UnknownAnnotation`, `FewestOnExactRepetition`, `AmbiguousRepetitionBody`, `AmbiguousAdjacentRepetition`.

---

## Formatting

`Ptern.format(...)` takes a ptern source string and returns a canonically formatted version. It is useful for normalising hand-written pterns, building editor integrations, and generating readable output from code that produces ptern strings programmatically.

```kotlin
import io.ptern.Ptern
import io.ptern.PternFormatException
import io.ptern.formatter.FormatError
import io.ptern.formatter.FormatOptions

val source = "!case-insensitive=true\nword=%Alpha*1..?;\n{word}"

try {
    val formatted = Ptern.format(source)
    println(formatted)
} catch (e: PternFormatException) {
    when (e.formatError) {
        FormatError.InvalidLineWidth -> println("lineWidth must be >= 40")
        is FormatError.FormatLexError -> println("source has lex errors")
        is FormatError.FormatParseError -> println("source has parse errors")
    }
}
// "!case-insensitive = true\n\nword = %Alpha * 1..? ;\n\n{word}"
```

Formatting succeeds as long as the source lexes and parses — semantic errors (undefined references, circular definitions, etc.) do not prevent it.

### FormatOptions

```kotlin
data class FormatOptions(
    val lineWidth: Int = 80,     // maximum line length; must be >= 40
    val compact: Boolean = false, // strip optional whitespace around operators
    val aligned: Boolean = true,  // align = signs within annotation and definition blocks
    val reordered: Boolean = false, // reorder definitions into dependency order
)
```

`FormatOptions()` (all defaults) is the starting point; override individual fields using Kotlin's named-argument copy constructor or `.copy(...)`:

```kotlin
val opts = FormatOptions(compact = true)
// or, from an existing instance:
val opts2 = FormatOptions().copy(compact = true)
```

### What the formatter does

**Output structure.** The formatter emits sections in this order:

1. Ptern-level doc comment block (followed by a mandatory blank line)
2. Annotation block (annotations sorted lexicographically by name)
3. Blank separator (when annotations and a subsequent section are both present, and `compact = false`)
4. Definition block (in source order, or topological order when `reordered = true`)
5. Blank separator (when definitions and the body are both present, and `compact = false`)
6. Body doc comment block
7. Body expression

**Token normalisation.** String literals are normalised to single-quote delimiters. Double quotes are used only when the literal content contains a single-quote character. Character class names are normalised to title case (`%Alpha`, `%Digit`, etc.).

**Alignment.** When `aligned = true` (the default), the `=` signs within the annotation block are aligned to a common column, and the `=` signs within the definition block are aligned to a separate common column. The column is `(length of longest name in the block) + 2`.

```
// Input (misaligned):
// !case-insensitive = true
// !multiline = true
// !substitutable = true
//
// Formatted (aligned = true):
// !case-insensitive = true
// !multiline        = true
// !substitutable    = true
```

**Line breaking.** Long definition lines are broken using a cascade of rules: first after `=` if the body fits in `lineWidth - 4` characters, then at the rightmost sequence space, then before the rightmost outer `|`. Long body expression lines are broken at the rightmost sequence space, then before the rightmost outer `|`. Lines that cannot be broken within `lineWidth` are emitted at their natural length.

### Compact mode

Setting `compact = true` removes optional whitespace around `*`, `|`, `(`, and `)` operators, and suppresses blank separator lines between blocks and between commented items within a block.

```kotlin
Ptern.format("( 'a' | 'b' ) * 3", FormatOptions(compact = true))
// "('a'|'b')*3"
```

Keyword spacing (`as`, `excluding`) is always one space on each side regardless of `compact`.

### Alignment disabled

```kotlin
val unaligned = FormatOptions(aligned = false)

val source = "word = %Alpha * 1..? ;\ndigit = %Digit * 1..? ;\n{word} {digit}"
Ptern.format(source, unaligned)
// "word = %Alpha * 1..? ;\ndigit = %Digit * 1..? ;\n\n{word} {digit}"
```

(Definitions are still in source order; `unaligned` only changes whether `=` signs are padded.)

### Reordering definitions

When `reordered = true`, definitions are sorted into topological layers — dependencies come before the definitions that reference them — and alphabetically within each layer.

```kotlin
val source = "b = {a} ;\na = 'x' ;\n{b}"
Ptern.format(source, FormatOptions(reordered = true, aligned = false))
// "a = 'x' ;\nb = {a} ;\n\n{b}"
```

Definitions involved in dependency cycles are placed after all successfully sorted definitions, in their original source order.

### Doc comment preservation

Doc comments are preserved verbatim. Item-level comments stay attached to the item they document and move with it when sorting.

```kotlin
val source = "# Match any alphabetic word\n\n# Definition of word\nword = %Alpha * 1..? ;\n{word}"
Ptern.format(source)
// "# Match any alphabetic word\n\n# Definition of word\nword  = %Alpha * 1..? ;\n\n{word}"
```

### Idempotency

Formatting is idempotent: applying `format` to already-formatted output returns the same string.

```kotlin
val once = Ptern.format(source, opts)
val twice = Ptern.format(once, opts)
check(once == twice)  // always true
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
|:-----------------------------------------|:-------:|:--------|
| `!allow-backtracking = true`            | `false` | Suppress all compile-time backtracking safety checks |
| `!case-insensitive = true`              | `false` | Literals and ranges match both cases |
| `!multiline = true`                     | `false` | `@line-start`/`@line-end` match per-line (also set automatically by those assertions); does not affect `matchesAllOf`/`matchStartOf`/`matchEndOf` in this edition (see the `!multiline` section above) |
| `!replacements-ignore-matching = true`  | `false` | No effect in the current Kotlin port — replacement values are never validated against the sub-pattern (see [Validation](#validation)) |
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
