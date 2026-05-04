# Ptern User Guide — Gleam API

Ptern is a pattern language that compiles to regular expressions. It is designed to be readable first — every construct is either a plain keyword or punctuation that carries an obvious meaning. You should be able to read a ptern aloud and have it make sense.

This guide builds up the language from scratch, introducing each concept with working examples. The formal specification (`ptern-specification.md`) is the complete reference; this guide is the on-ramp.

All examples assume the following imports:

```gleam
import gleam/dict
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import ptern
```

---

## A First Taste

Here is a ptern that matches an ISO date:

```
%Digit * 4 as year '-' %Digit * 2 as month '-' %Digit * 2 as day
```

Read it aloud: "four digits captured as year, a dash, two digits captured as month, a dash, two digits captured as day." It is longer than the equivalent regular expression (`\d{4}-\d{2}-\d{2}`) but leaves nothing to interpret.

With the Gleam API:

```gleam
let assert Ok(iso_date) = ptern.compile(
  "%Digit * 4 as year '-' %Digit * 2 as month '-' %Digit * 2 as day",
)
```

**Boolean test:**

```gleam
ptern.matches_all_of(iso_date, "2026-07-04")                    // True
ptern.matches_all_of(iso_date, "2026-7-4")                      // False — single-digit month/day
ptern.matches_in(iso_date, "Event on 2026-07-04 at noon")       // True
```

**Occurrence match:**

```gleam
ptern.match_first_in(iso_date, "Event on 2026-07-04 at noon")
// Some(MatchOccurrence(
//   index: 9, length: 10,
//   captures: dict.from_list([#("year", "2026"), #("month", "07"), #("day", "04")])
// ))
```

**Replacement:**

```gleam
ptern.replace_first_in(
  iso_date,
  "Event on 2026-07-04 at noon",
  dict.from_list([#("year", ptern.ScalarReplacement("2027"))]),
)
// Ok("Event on 2027-07-04 at noon")
// month and day are untouched because they were not in the replacements dict
```

**Substitution** (assembling a string from scratch):

```gleam
let assert Ok(iso_date_sub) = ptern.compile(
  "!substitutable = true
  %Digit * 4 as year '-' %Digit * 2 as month '-' %Digit * 2 as day",
)

ptern.substitute(iso_date_sub, dict.from_list([
  #("year",  ptern.ScalarReplacement("2026")),
  #("month", ptern.ScalarReplacement("07")),
  #("day",   ptern.ScalarReplacement("04")),
]))
// Ok("2026-07-04")
```

These four operations — boolean test, occurrence match, replacement, substitution — are the core of what ptern does. The rest of this guide explains how to write patterns that drive them.

---

## Literals

The simplest pattern is a literal string:

```gleam
let assert Ok(hello) = ptern.compile("'hello'")

ptern.matches_all_of(hello, "hello")   // True
ptern.matches_all_of(hello, "Hello")   // False — case matters by default
ptern.matches_all_of(hello, "hello!")  // False — exact match required for matches_all_of
ptern.matches_in(hello, "say hello")   // True — matches_in finds it anywhere
```

Literals can use either single or double quotes. The two forms are identical:

```gleam
ptern.compile("'hello'")    // same as
ptern.compile("\"hello\"")
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

```gleam
ptern.compile("'\\t'")        // ptern for a tab character
ptern.compile("'can\\'t'")    // ptern matching "can't"
ptern.compile("'é'")          // ptern matching 'é'
```

---

## Sequences

Place two patterns side by side (with a space between them) to match one followed by the other:

```gleam
let assert Ok(greeting) = ptern.compile("'hello' ' ' 'world'")

ptern.matches_all_of(greeting, "hello world")   // True
ptern.matches_all_of(greeting, "helloworld")    // False — space is required
```

**The space between patterns is the sequence operator.** It is not just formatting; it is what makes one pattern follow another. This is intentional: it forces you to write patterns that are easy to read by preventing everything from running together.

You can sequence as many pieces as you like:

```gleam
let assert Ok(date_with_slashes) = ptern.compile(
  "%Digit * 2 '/' %Digit * 2 '/' %Digit * 4",
)

ptern.matches_all_of(date_with_slashes, "04/28/2026")   // True
```

---

## Alternatives

Use `|` to match any one of several options:

```gleam
let assert Ok(yes_or_no) = ptern.compile("'yes' | 'no'")

ptern.matches_all_of(yes_or_no, "yes")    // True
ptern.matches_all_of(yes_or_no, "no")     // True
ptern.matches_all_of(yes_or_no, "maybe")  // False
```

Alternatives can themselves contain sequences:

```gleam
let assert Ok(http_or_https) = ptern.compile("'http' '://' | 'https' '://'")

ptern.matches_start_of(http_or_https, "https://example.com")  // True
ptern.matches_start_of(http_or_https, "ftp://example.com")    // False
```

When a pattern matches, the **first** matching alternative (left to right) is selected. This matters when alternatives overlap.

---

## Grouping

Parentheses `( )` override precedence and let you treat a compound expression as a single unit:

```gleam
// Without grouping: three separate alternatives
ptern.compile("'a' | 'b' | 'c'")

// With grouping: one of 'a', 'b', or 'c', followed by a digit
ptern.compile("('a' | 'b' | 'c') %Digit")
```

```gleam
let assert Ok(color_keyword) = ptern.compile("'color' | 'colour'")    // two full alternatives
let assert Ok(colour_alt)    = ptern.compile("'colo' ('u') * 0..1 'r'")  // optional 'u'
```

Grouping is also how you apply repetition to a multi-element pattern (see Repetition below).

---

## Character Classes

A character class matches any **single character** from a named set. They are written with a `%` prefix:

```gleam
let assert Ok(digit)    = ptern.compile("%Digit")  // matches any of 0–9
let assert Ok(letter)   = ptern.compile("%Alpha")  // matches any of a–z or A–Z
let assert Ok(alnum)    = ptern.compile("%Alnum")  // matches any letter or digit
let assert Ok(any_char) = ptern.compile("%Any")    // matches any single character including newline
let assert Ok(word_ch)  = ptern.compile("%Word")   // matches a–z, A–Z, 0–9, _
```

```gleam
ptern.matches_all_of(digit,    "7")    // True
ptern.matches_all_of(digit,    "a")    // False
ptern.matches_all_of(letter,   "Q")    // True
ptern.matches_all_of(any_char, "\n")   // True
```

Character classes pair naturally with repetition:

```gleam
let assert Ok(word)  = ptern.compile("%Alpha * 1..?")          // one or more letters
let assert Ok(ident) = ptern.compile("%Alpha %Alnum * 0..?")   // letter then letters-or-digits
```

For matching Unicode text beyond ASCII, use Unicode category classes:

```gleam
ptern.compile("%L * 1..?")   // one or more Unicode letters (any script)
ptern.compile("%N * 1..?")   // one or more Unicode numbers
ptern.compile("%Lu")         // one uppercase Unicode letter
ptern.compile("%Ll")         // one lowercase Unicode letter
```

A full list of all character class names is in [Appendix A](#appendix-a-character-class-reference).

---

## Character Ranges

Match any single character within an inclusive range using `..`:

```gleam
let assert Ok(lower_letter)   = ptern.compile("'a'..'z'")
let assert Ok(upper_letter)   = ptern.compile("'A'..'Z'")
let assert Ok(single_digit)   = ptern.compile("'0'..'9'")
let assert Ok(hex_digit_part) = ptern.compile("'a'..'f'")
```

```gleam
ptern.matches_all_of(lower_letter, "m")    // True
ptern.matches_all_of(lower_letter, "M")    // False
ptern.matches_all_of(lower_letter, "mm")   // False — exactly one character
```

Both endpoints must be single characters. The range must not be inverted (`'z'..'a'` is an error).

Ranges compose with sequences and repetition just like any other expression:

```gleam
// A hexadecimal digit
let assert Ok(hex_digit) = ptern.compile("'0'..'9' | 'a'..'f' | 'A'..'F'")

// An octal number
let assert Ok(octal) = ptern.compile("'0' '0'..'7' * 1..?")
```

---

## Set Difference

`excluding` removes characters from a single-character set:

```gleam
// Any character except a double quote
let assert Ok(non_quote)     = ptern.compile("%Any excluding '\"'")

// Any digit except 0
let assert Ok(non_zero_digit) = ptern.compile("%Digit excluding '0'")

// Any digit except 8 or 9
let assert Ok(octal_digit)    = ptern.compile("%Digit excluding '8'..'9'")
```

Both sides of `excluding` must match exactly one character. When both sides are the same expression — `%Digit excluding %Digit`, `'x' excluding 'x'`, or `'a'..'z' excluding 'a'..'z'` — the result would be an empty character class, so the compiler rejects the pattern. Semantically equivalent but textually distinct pairs (e.g. `%Digit excluding '0'..'9'`) are not caught at compile time.

A practical use: matching the contents of a quoted string without letting a closing quote slip through:

```gleam
let assert Ok(quoted_string) = ptern.compile("'\"' (%Any excluding '\"') * 0..? '\"'")

ptern.matches_all_of(quoted_string, "\"hello world\"")   // True
ptern.matches_all_of(quoted_string, "\"say \\\"hi\\\"\"")  // False
```

---

## Repetition

Repeat a pattern with `*`:

### Fixed count

```gleam
let assert Ok(four_digits)   = ptern.compile("%Digit * 4")   // exactly 4
let assert Ok(three_letters) = ptern.compile("%Alpha * 3")   // exactly 3

ptern.matches_all_of(four_digits, "2026")    // True
ptern.matches_all_of(four_digits, "202")     // False
ptern.matches_all_of(four_digits, "20261")   // False
```

### Bounded range

```gleam
let assert Ok(two_to_four) = ptern.compile("%Digit * 2..4")   // 2, 3, or 4 digits

ptern.matches_all_of(two_to_four, "12")      // True
ptern.matches_all_of(two_to_four, "1234")    // True
ptern.matches_all_of(two_to_four, "1")       // False
ptern.matches_all_of(two_to_four, "12345")   // False
```

### Optional (zero or one)

`* 0..1` is the idiomatic "maybe once" form:

```gleam
let assert Ok(optional_sign) = ptern.compile("('+' | '-') * 0..1 %Digit * 1..?")

ptern.matches_all_of(optional_sign, "42")     // True
ptern.matches_all_of(optional_sign, "+42")    // True
ptern.matches_all_of(optional_sign, "-42")    // True
ptern.matches_all_of(optional_sign, "+-42")   // False
```

### Unbounded (at least N)

`* n..?` means "n or more":

```gleam
let assert Ok(one_or_more)  = ptern.compile("%Digit * 1..?")   // at least one
let assert Ok(zero_or_more) = ptern.compile("%Digit * 0..?")   // any number
```

### Repeating a group

Apply `*` to a grouped expression to repeat a multi-element sequence:

```gleam
// Three groups of four digits separated by dashes
let assert Ok(credit_card) = ptern.compile("%Digit * 4 ('-' %Digit * 4) * 3")

ptern.matches_all_of(credit_card, "1234-5678-9012-3456")  // True
```

### Lazy repetition: `fewest`

By default, repetition is **greedy** — it consumes as many iterations as possible while still allowing the overall pattern to match. Add `fewest` after any variable-count repetition to make it **lazy**: prefer the fewest iterations that still allow the pattern to match.

```gleam
// Greedy — %Any * 1..? swallows as far as possible before stopping at '</'
let assert Ok(greedy) = ptern.compile("'<' %Alpha * 1..? '>' %Any * 1..? '</'")
ptern.match_first_in(greedy, "<b>hello</b><em>world</em>")
// index 0, length 22 — runs all the way to the last '</'

// Lazy — stops at the first '</'
let assert Ok(lazy_p) = ptern.compile("'<' %Alpha * 1..? '>' %Any * 1..? fewest '</'")
ptern.match_first_in(lazy_p, "<b>hello</b><em>world</em>")
// index 0, length 11 — stops at the first '</'
```

`fewest` works with any variable-count form:

```
%Any * 1..? fewest      // one or more, fewest first
%Any * 0..? fewest      // zero or more, fewest first
%Any * 0..1 fewest      // optional, prefer not to match
%Any * 3..10 fewest     // 3 to 10, prefer 3
```

Applying `fewest` to an exact count is a compile-time error — there is nothing to minimise when the count is fixed:

```gleam
ptern.compile("%Any * 3 fewest")
// Error(SemanticErrors([FewestOnExactRepetition]))
```

**`fewest` vs `excluding`:** For patterns bounded by a single-character delimiter, `excluding` is the better choice — it prevents the delimiter from being consumed at all, eliminating backtracking entirely. Use `fewest` when the end delimiter is more than one character and `excluding` cannot help:

```gleam
// Single-char delimiter — use excluding (no backtracking)
let assert Ok(quoted) = ptern.compile("'\"' %Any excluding '\"' * 0..? '\"'")

// Multi-char end delimiter — use fewest
let assert Ok(bold) = ptern.compile("'<b>' %Any * 0..? fewest '</b>'")
```

Lazy repetition is still subject to the same compile-time backtracking safety checks as greedy repetition. A `fewest` quantifier on a structurally ambiguous pattern still requires `!allow-backtracking = true`.

---

## Named Captures

Add `as name` to any expression to capture the matched text under that name:

```gleam
let assert Ok(year_p) = ptern.compile("%Digit * 4 as year")

ptern.match_first_in(year_p, "The year is 2026")
// Some(MatchOccurrence(
//   index: 11, length: 4,
//   captures: dict.from_list([#("year", "2026")])
// ))
```

The `captures` dict in the result maps each capture name to the text that was matched at that position. Names that did not participate in the match (e.g. an unmatched branch of an alternation) are absent.

A capture can wrap any expression, not just atomic ones:

```gleam
let assert Ok(iso_date) = ptern.compile(
  "%Digit * 4 as year '-' %Digit * 2 as month '-' %Digit * 2 as day",
)

ptern.match_first_in(iso_date, "Published 2026-04-28")
// Some(MatchOccurrence(
//   index: 10, length: 10,
//   captures: dict.from_list([#("year", "2026"), #("month", "04"), #("day", "28")])
// ))
```

### Using captures for replacement

Pass a subset of captures in a replacements dict to `replace_*` functions. Any capture not mentioned retains its original matched value:

```gleam
ptern.replace_first_in(
  iso_date,
  "Published 2026-04-28",
  dict.from_list([#("year", ptern.ScalarReplacement("2027"))]),
)
// Ok("Published 2027-04-28")   — month and day unchanged

ptern.replace_all_in(
  iso_date,
  "2026-01-01 and 2026-06-15",
  dict.from_list([#("year", ptern.ScalarReplacement("2027"))]),
)
// Ok("2027-01-01 and 2027-06-15")
```

### The same name in multiple places

You can reuse a capture name at more than one position in a pattern. The same replacement value is applied to every occurrence:

```gleam
let assert Ok(tagged) = ptern.compile(
  "'<' %Alpha * 1..? as tag '>'
  %Any * 0..? as body
  '</' %Alpha * 1..? as tag '>'",
)

ptern.replace_first_in(
  tagged,
  "<em>hello</em>",
  dict.from_list([#("tag", ptern.ScalarReplacement("strong"))]),
)
// Ok("<strong>hello</strong>")   — both occurrences of `tag` replaced
```

During matching, `captures` holds the value from the **last** matched position for each name (the closing tag in this example).

---

## Subpattern Definitions

For anything beyond a trivial pattern, define named sub-expressions at the top and interpolate them with `{ }`. This is the main readability tool:

```gleam
let assert Ok(iso_date) = ptern.compile(
  "yyyy = %Digit * 4;
  mm   = '0' '1'..'9' | '1' '0'..'2';
  dd   = '0' '1'..'9' | '1'..'2' %Digit | '3' '0'..'1';
  {yyyy} as year '-' {mm} as month '-' {dd} as day",
)
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

```gleam
let assert Ok(keyword) = ptern.compile(
  "!case-insensitive = true
  'select' | 'from' | 'where'",
)

ptern.matches_all_of(keyword, "SELECT")   // True
ptern.matches_all_of(keyword, "From")     // True
ptern.matches_all_of(keyword, "WHERE")    // True
```

### `!multiline = true`

Makes `@line-start` and `@line-end` match at the boundary of each line instead of the whole string. It also causes `matches_all_of`, `matches_start_of`, and `matches_end_of` to operate at line boundaries rather than string boundaries: for example, `matches_all_of` returns `True` if any complete line in the input is a full match. The annotation is also enabled automatically whenever `@line-start` or `@line-end` appears in the pattern (see Position Assertions below).

### `!replacements-ignore-matching = true`

By default, replacement validates each provided value against the sub-pattern for that capture:

```gleam
let assert Ok(p) = ptern.compile("%Digit * 4 as year")

ptern.replace_first_in(
  p,
  "2026",
  dict.from_list([#("year", ptern.ScalarReplacement("abc"))]),
)
// Error(InvalidReplacementValue("year", "abc"))
```

Set `!replacements-ignore-matching = true` to skip validation and accept any string as a replacement value. Useful when the replacement is intentionally different in kind from the matched text (e.g. replacing a year with a placeholder like `"YYYY"`):

```gleam
let assert Ok(p) = ptern.compile(
  "!replacements-ignore-matching = true
  %Digit * 4 as year",
)

ptern.replace_first_in(
  p,
  "2026",
  dict.from_list([#("year", ptern.ScalarReplacement("YYYY"))]),
)
// Ok("YYYY")
```

### `!allow-backtracking = true`

By default, the compiler rejects patterns that could cause catastrophic backtracking in the JavaScript regex engine. Three checks are run on any pattern that contains variable-count repetitions (`* n..m` with `n < m`, or `* n..?`); exact-count repetitions (`* n`) are exempt.

**Overlapping alternation branches in a repetition** — if two branches of an alternation share characters at the boundary between iterations, `AmbiguousRepetitionAdjacency` is reported:

```gleam
// Error: 'a' and 'ab' both start with 'a' — engine cannot tell them apart
ptern.compile("('a' | 'ab') * 1..?")

// OK: %Alpha and '_' are disjoint
ptern.compile("(%Alpha | '_') * 1..?")

// OK: %Alpha and %Digit are disjoint
ptern.compile("(%Alpha | %Digit) * 1..?")
```

**Variable-length body that overlaps itself** — if the body of a variable-count repetition is variable-length and its last and first character sets overlap, `AmbiguousRepetitionBody` is reported. A fixed-length body is never flagged:

```gleam
// Error: inner repetition is variable-length; %Alpha∩%Alpha ≠ ∅
ptern.compile("(%Alpha * 1..?) * 1..?")

// OK: last=%Digit, first='x' — disjoint
ptern.compile("('x' %Digit * 1..?) * 1..?")

// OK: body %Digit is fixed length 1
ptern.compile("(%Digit) * 1..?")
```

**Adjacent unbounded repetitions** — two directly adjacent unbounded repetitions with overlapping character sets produce `AmbiguousAdjacentRepetition`. A bounded repetition (`* n..m`) on either side avoids the check:

```gleam
// Error: both unbounded, %Digit∩%Digit ≠ ∅
ptern.compile("%Digit * 1..? %Digit * 1..?")

// OK: literal '-' separates them
ptern.compile("%Digit * 1..? '-' %Digit * 1..?")

// OK: first repetition is bounded (* 1..5)
ptern.compile("%Alpha * 1..5 %Alpha * 1..?")
```

When a pattern is structurally safe but the static analysis cannot prove it, set `!allow-backtracking = true` to opt out. A real example is a double-quoted string that allows escaped quotes:

```gleam
let assert Ok(dq_string) = ptern.compile(
  "!allow-backtracking = true
  char = %Any excluding '\"';
  '\"' ({char} | '\\\"') * 0..1000 '\"'",
)

ptern.matches_all_of(dq_string, "\"hello\"")           // True
ptern.matches_all_of(dq_string, "\"say \\\"hi\\\"\"")  // True — escaped inner quotes
```

The body `({char} | '\\\"')` has branches of different lengths: `{char}` matches one character, and `'\\\"'` matches two (`\` then `"`). This makes the body variable-length, and `AmbiguousRepetitionBody` fires because the last character of one iteration can be `"` (from `'\\\"'`), which overlaps with the first character of the next. In practice the pattern is safe — the outer `'"'` terminates the string and cannot be confused with the `"` inside `'\\\"'` — but the static check cannot see that structural guarantee.

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

```gleam
let assert Ok(whole_word) = ptern.compile("@word-start %Alpha * 1..? @word-end")

ptern.matches_in(whole_word, "say hello there")  // True  — "hello" is a whole word
ptern.matches_in(whole_word, "123")              // False — no alphabetic word
```

Without the word boundaries, `%Alpha * 1..?` would match the alphabetic portion of `"hello123"`. With them, only a standalone word matches:

```gleam
let assert Ok(un) = ptern.compile("@word-start 'un'")

ptern.matches_in(un, "undo")   // True  — "un" is at a word start
ptern.matches_in(un, "fun")    // False — "un" is mid-word
```

For line-anchored patterns, `@line-start` and `@line-end` work across multiple lines when multiline mode is active:

```gleam
let assert Ok(line_number) = ptern.compile("@line-start %Digit * 1..?")

ptern.match_all_in(line_number, "1 first\n2 second\n3 third")
// three occurrences: index 0, index 8, index 17
```

---

## All Match Operations

Every ptern exposes the same set of matching operations. They differ only in where they anchor the match:

| Function                              | Where it looks                       | Returns |
|:--------------------------------------|:-------------------------------------|:--------|
| `matches_all_of(p, s)`               | Must cover the whole string          | `Bool` |
| `matches_start_of(p, s)`             | Must start at index 0                | `Bool` |
| `matches_end_of(p, s)`               | Must end at `string.length(s)`       | `Bool` |
| `matches_in(p, s)`                   | Anywhere in the string               | `Bool` |
| `match_all_of(p, s)`                 | Must cover the whole string          | `Option(MatchOccurrence)` |
| `match_start_of(p, s)`               | Must start at index 0                | `Option(MatchOccurrence)` |
| `match_end_of(p, s)`                 | Must end at `string.length(s)`       | `Option(MatchOccurrence)` |
| `match_first_in(p, s)`               | First occurrence anywhere            | `Option(MatchOccurrence)` |
| `match_next_in(p, s, start)`         | First occurrence at or after `start` | `Option(MatchOccurrence)` |
| `match_all_in(p, s)`                 | Every non-overlapping occurrence     | `List(MatchOccurrence)` |

A `MatchOccurrence` carries:
- `index` — start position in the string
- `length` — length of the matched substring
- `captures` — `Dict(String, String)` mapping capture names to their matched strings

```gleam
let assert Ok(version) = ptern.compile(
  "num = %Digit * 1..10;
  {num} as major '.' {num} as minor '.' {num} as patch",
)

ptern.match_first_in(version, "Using package v1.23.456 in production")
// Some(MatchOccurrence(
//   index: 14, length: 8,
//   captures: dict.from_list([#("major", "1"), #("minor", "23"), #("patch", "456")])
// ))

ptern.match_all_in(version, "v1.0.0 and v2.3.4")
// [
//   MatchOccurrence(index: 1,  length: 5, captures: dict.from_list([#("major","1"), #("minor","0"), #("patch","0")])),
//   MatchOccurrence(index: 11, length: 5, captures: dict.from_list([#("major","2"), #("minor","3"), #("patch","4")]))
// ]
```

`match_next_in` is useful for iterating through matches manually. In Gleam, this is expressed as a recursive function:

```gleam
fn collect_captures(
  p: ptern.Ptern,
  input: String,
  pos: Int,
  key: String,
) -> List(String) {
  case ptern.match_next_in(p, input, pos) {
    None -> []
    Some(m) ->
      case dict.get(m.captures, key) {
        Ok(v) -> [v, ..collect_captures(p, input, m.index + m.length, key)]
        Error(_) -> collect_captures(p, input, m.index + m.length, key)
      }
  }
}

let assert Ok(num) = ptern.compile("%Digit * 1..? as n")
collect_captures(num, "a1b22c333", 0, "n")
// ["1", "22", "333"]
```

For the common case of collecting all matches, `match_all_in` is more concise:

```gleam
ptern.match_all_in(num, "a1b22c333")
|> list.filter_map(fn(m) { result.ok(dict.get(m.captures, "n")) })
// ["1", "22", "333"]
```

---

## Length Metadata

`min_length` and `max_length` return the shortest and longest string the pattern can match, computed at compile time:

```gleam
let assert Ok(p) = ptern.compile("%Digit * 2..4")
ptern.min_length(p)   // 2
ptern.max_length(p)   // Some(4)

let assert Ok(q) = ptern.compile("%Digit * 1..?")
ptern.min_length(q)   // 1
ptern.max_length(q)   // None — unbounded
```

Position assertions contribute zero to both bounds. This lets you use ptern as a quick validity check — if an input string's length is already outside `[min, max]`, you can skip the regex entirely.

---

## Replacement in Depth

Replacement modifies a string by substituting new text at the positions of named captures, leaving everything else unchanged.

### Validation

By default, each replacement value is validated against the sub-pattern for its capture. A value that would not have matched the original pattern is rejected:

```gleam
let assert Ok(p) = ptern.compile("%Digit * 4 as year")

ptern.replace_first_in(p, "2026", dict.from_list([#("year", ptern.ScalarReplacement("2027"))]))
// Ok("2027") — valid

ptern.replace_first_in(p, "2026", dict.from_list([#("year", ptern.ScalarReplacement("20"))]))
// Error(InvalidReplacementValue("year", "20")) — too short

ptern.replace_first_in(p, "2026", dict.from_list([#("year", ptern.ScalarReplacement("abc"))]))
// Error(InvalidReplacementValue("year", "abc")) — not digits
```

Set `!replacements-ignore-matching = true` to disable validation for the whole pattern.

### Multiple captures

Any subset of captures may appear in the replacements dict. Omitted captures retain their original values:

```gleam
let assert Ok(iso_date) = ptern.compile(
  "yyyy = %Digit * 4;
  mm   = '0' '1'..'9' | '1' '0'..'2';
  dd   = '0' '1'..'9' | '1'..'2' %Digit | '3' '0'..'1';
  {yyyy} as year '-' {mm} as month '-' {dd} as day",
)

ptern.replace_first_in(
  iso_date,
  "2026-07-04",
  dict.from_list([#("month", ptern.ScalarReplacement("12"))]),
)
// Ok("2026-12-04")   — year and day unchanged
```

### Round-trip consistency

If you match a string and pass the captured values back as replacements, you get the original string:

```gleam
let assert Some(m) = ptern.match_first_in(iso_date, "2026-07-04")
let replacements = dict.map_values(m.captures, fn(_, v) { ptern.ScalarReplacement(v) })
ptern.replace_all_of(iso_date, "2026-07-04", replacements)
// Ok("2026-07-04") — identity
```

### Captures inside repetitions

When a named capture appears inside a repeated sub-pattern, you can provide a `List(String)` via `ArrayReplacement` to replace each iteration independently:

```gleam
let assert Ok(csv) = ptern.compile(
  "!replacements-ignore-matching = true
  %Any excluding ',' * 1..100 as col (',' %Any excluding ',' * 1..100 as col) * 0..20",
)

ptern.replace_first_in(
  csv,
  "alice,bob,carol",
  dict.from_list([#("col", ptern.ArrayReplacement(["ALICE", "BOB", "CAROL"]))]),
)
// Ok("ALICE,BOB,CAROL")
```

The array length must equal the number of iterations in the actual match. Providing the wrong length returns `Error(ArrayLengthMismatch(...))`.

A scalar value inside a repetition is **broadcast** — it replaces every iteration with the same value:

```gleam
ptern.replace_first_in(
  csv,
  "alice,bob,carol",
  dict.from_list([#("col", ptern.ScalarReplacement("X"))]),
)
// Ok("X,X,X")
```

If the same capture name appears both inside and outside a repetition, the array's first element fills the non-repeated occurrence and the remaining elements fill the iterations.

### All six replace functions

Each replace function targets a different region of the input. They return `Ok(modified_string)`, or `Ok(original)` if the pattern does not match that region, or `Error(...)` when a replacement value is invalid.

```gleam
ptern.replace_all_of(p, input, replacements)              // whole string
ptern.replace_start_of(p, input, replacements)            // prefix
ptern.replace_end_of(p, input, replacements)              // suffix
ptern.replace_first_in(p, input, replacements)            // first occurrence
ptern.replace_next_in(p, input, start_index, replacements) // first at/after start_index
ptern.replace_all_in(p, input, replacements)              // all occurrences
```

---

## Substitution

Substitution is the inverse of matching: instead of extracting captures from a string, you provide capture values and assemble a new string from scratch. No original input string is needed.

To enable substitution, add `!substitutable = true`:

```gleam
let assert Ok(iso_date) = ptern.compile(
  "!substitutable = true
  yyyy = %Digit * 4;
  mm   = '0' '1'..'9' | '1' '0'..'2';
  dd   = '0' '1'..'9' | '1'..'2' %Digit | '3' '0'..'1';
  {yyyy} as year '-' {mm} as month '-' {dd} as day",
)

ptern.substitute(iso_date, dict.from_list([
  #("year",  ptern.ScalarReplacement("2026")),
  #("month", ptern.ScalarReplacement("07")),
  #("day",   ptern.ScalarReplacement("04")),
]))
// Ok("2026-07-04")
```

`substitute` returns `Result(String, SubstitutionError)`. Error variants include:

| Error | Meaning |
|:------|:--------|
| `NotSubstitutable` | Pattern was compiled without `!substitutable = true` |
| `MissingCapture(name)` | A required capture name was not provided |
| `CaptureMismatch(name, value)` | Provided value does not match the capture's sub-pattern |
| `NoMatchingBranch` | No alternation branch could be satisfied |
| `ArrayLengthError(name, len, min, max)` | Array length is outside the repetition bounds |

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

```gleam
let assert Ok(year_or_word) = ptern.compile(
  "!substitutable = true
  %Digit * 4 as year | %Alpha * 1..20 as word",
)

ptern.substitute(year_or_word, dict.from_list([
  #("year", ptern.ScalarReplacement("2026")),
]))
// Ok("2026") — first branch selected because 'year' is provided

ptern.substitute(year_or_word, dict.from_list([
  #("word", ptern.ScalarReplacement("hello")),
]))
// Ok("hello") — second branch selected because 'word' is provided

ptern.substitute(year_or_word, dict.new())
// Error(NoMatchingBranch) — neither branch can be satisfied
```

A branch made entirely of literals is always eligible and acts as a fallback. If no branch can succeed, `substitute` returns `Error(NoMatchingBranch)`.

### Repeated captures in substitution

An array of values drives the iteration count for a bounded repetition:

```gleam
let assert Ok(csv) = ptern.compile(
  "!substitutable = true
  field = %Any excluding ',' * 1..100;
  {field} as col (',' {field} as col) * 0..20",
)

ptern.substitute(csv, dict.from_list([
  #("col", ptern.ArrayReplacement(["name", "age", "city"])),
]))
// Ok("name,age,city")
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

```gleam
// NOT expressible as a single ptern: at least one lowercase, one uppercase, one digit.
// Use several pterns tested independently:

fn is_valid_password(s: String) -> Bool {
  let assert Ok(has_lower)   = ptern.compile("%Lower * 1..?")
  let assert Ok(has_upper)   = ptern.compile("%Upper * 1..?")
  let assert Ok(has_digit)   = ptern.compile("%Digit * 1..?")
  let assert Ok(long_enough) = ptern.compile("%Any * 8..?")
  ptern.matches_in(has_lower, s)
  && ptern.matches_in(has_upper, s)
  && ptern.matches_in(has_digit, s)
  && ptern.matches_all_of(long_enough, s)
}
```

Simultaneous lookahead requirements are not expressible as a single ptern. Use multiple pterns and combine the results in code. In practice, compile patterns once (outside the function) and pass them in as arguments or store them in an application context.

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

| Annotation                         | Default | Meaning |
|:-----------------------------------|:-------:|:--------|
| `!allow-backtracking = true`       | `false` | Suppress all compile-time backtracking safety checks (§7.12 of the spec) |
| `!case-insensitive = true`         | `false` | Literals and ranges match both cases |
| `!multiline = true`                | `false` | `@line-start`/`@line-end` match per-line (also set automatically by those assertions) |
| `!replacements-ignore-matching`    | `false` | Skip validation of replacement values |
| `!substitutable = true`            | `false` | Enable `substitute` and check substitutability at compile time |
| `!substitutions-ignore-matching`   | `false` | Skip validation in `substitute` (requires `!substitutable = true`) |

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
