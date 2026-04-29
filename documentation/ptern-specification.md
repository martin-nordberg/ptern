# Ptern Language Specification

**Version:** 1.0  
**Date:** 2026-04-27

---

## Table of Contents

1. [Introduction](#1-introduction)
2. [Source Text](#2-source-text)
3. [Lexical Grammar](#3-lexical-grammar)
4. [Syntactic Grammar](#4-syntactic-grammar)
5. [Character Classes](#5-character-classes)
6. [Annotations](#6-annotations)
7. [Compile-Time Constraints](#7-compile-time-constraints)
8. [Matching Semantics](#8-matching-semantics)
9. [Compiled Pattern Operations](#9-compiled-pattern-operations)
10. [Replacement](#10-replacement)
11. [Substitution](#11-substitution)
12. [Examples](#12-examples)

---

## 1. Introduction

Ptern (pronounced "turn") is a pattern language that compiles to regular expressions. Its purpose is to express text patterns in a form that is both unambiguous and readable by people who are not experts in regular expression syntax.

### 1.1 Design Goals

- **Readability**: Every construct has a clear English-adjacent meaning. Operators are keywords (`as`, `excluding`) or punctuation that carries no legacy baggage from POSIX or PCRE.
- **Composition**: Named subpatterns (`identifier = pattern ;`) allow a complex pattern to be built from named, tested pieces.
- **Captures**: Named captures (`pattern as name`) integrate matching, replacement, and substitution into a single coherent model.
- **No hidden power**: Features that require lookahead, lookahead-behind, atomic groups, or possessive quantifiers are intentionally absent. Ptern compiles to a plain, portable regular expression.

### 1.2 Compilation Target

Ptern compiles to a JavaScript ECMAScript `v`-mode regular expression (Unicode sets mode, ES2024). The compiled output consists of a regex source string and a flags string; callers construct `new RegExp(source, flags)`. The `d` flag (`hasIndices`) is always included in compiled patterns to support replacement operations.

### 1.3 Scope of This Document

This document specifies the Ptern source language: its lexical structure, grammar, compile-time constraints, and operational semantics for matching, replacement, and substitution. It does not specify the runtime environment, memory model, or language-specific binding APIs beyond the abstract operation signatures in §9–§11.

---

## 2. Source Text

A Ptern source string is a sequence of Unicode scalar values. No byte-order mark is required or interpreted. Line endings may be LF (`U+000A`), CR (`U+000D`), or CR+LF.

### 2.1 Structure of a Ptern

A Ptern source string consists of zero or more **annotations**, followed by zero or more **subpattern definitions**, followed by exactly one **body expression**:

```
ptern = annotation* definition* body-expression
```

Annotations must appear before all definitions. Definitions must appear before the body expression. Whitespace and comments may appear freely between all elements.

---

## 3. Lexical Grammar

The lexer scans left to right, longest match. Whitespace and comments are silently discarded except at the sequence level (see §4.3).

### 3.1 Whitespace and Comments

```
Whitespace   = (' ' | '\t' | '\r' | '\n') * 1..?
Comment      = '#' (%Any excluding ('\r' | '\n')) * 0..?
```

Comments run from `#` to the end of the line. They are treated identically to whitespace by the parser.

### 3.2 String Literals

```
SingleQuotedLiteral  = "'" (%Any excluding ("'" | '\r' | '\n')) * 1..? "'"
DoubleQuotedLiteral  = '"' (%Any excluding ('"' | '\r' | '\n')) * 1..? '"'
```

Both forms are interchangeable; the surrounding quote character is not part of the literal text. A literal may contain any character except the enclosing quote and unescaped newlines. Escape sequences are recognised (see §3.3).

### 3.3 Escape Sequences

The following escape sequences are recognised inside string literals. Any other `\X` sequence is a compile-time error (§7.1).

| Sequence     | Meaning                                          |
|:------------:|:------------------------------------------------|
| `\a`         | Alert / bell (U+0007)                           |
| `\f`         | Form feed (U+000C)                              |
| `\n`         | Line feed / newline (U+000A)                    |
| `\r`         | Carriage return (U+000D)                        |
| `\t`         | Horizontal tab (U+0009)                         |
| `\v`         | Vertical tab (U+000B)                           |
| `\'`         | Single quote (U+0027)                           |
| `\"`         | Double quote (U+0022)                           |
| `\\`         | Backslash (U+005C)                              |
| `\uXXXX`     | Unicode scalar value (four hex digits)          |

### 3.4 Tokens

```
CharacterClass       = '%' 'A'..'Z' %Alpha * 0..31
Integer              = %Digit * 1..5
Identifier           = %Alpha (%Alnum | '-') * 0..63
PositionAssertionTok = '@' %Alpha (%Alnum | '-') * 0..63
RangeOperator        = '..'
Bang                 = '!'
AlternativeOp        = '|'
Asterisk             = '*'
AssignmentOp         = '='
Semicolon            = ';'
LeftParen            = '('
RightParen           = ')'
LeftBrace            = '{'
RightBrace           = '}'
QuestionMark         = '?'
AsKeyword            = 'as'          (followed by non-Alnum)
ExcludingKeyword     = 'excluding'   (followed by non-Alnum)
TrueKeyword          = 'true'        (followed by non-Alnum)
FalseKeyword         = 'false'       (followed by non-Alnum)
```

Keywords (`as`, `excluding`, `true`, `false`) are matched only when not followed by an alphanumeric character or `-`, preventing them from consuming a prefix of an identifier. All remaining characters that do not match any token are a lexical error.

---

## 4. Syntactic Grammar

### 4.1 EBNF

Terminals in `SCREAMING-KEBAB-CASE` are token types from §3. Non-terminals are in lowercase. `ows` is optional whitespace/comments; `mws` is mandatory whitespace/comments.

```ebnf
ptern        = ows annotation* definition* expression ows

annotation       = BANG IDENTIFIER ows ASSIGNMENT-OP ows annotation-value ows
annotation-value = TRUE-KEYWORD | FALSE-KEYWORD

definition   = IDENTIFIER ows ASSIGNMENT-OP ows expression ows SEMICOLON ows

expression   = alternation

alternation  = sequence ( ows ALTERNATIVE-OP ows sequence )*

sequence     = capture ( mws capture )*

capture      = repetition ( mws AS-KEYWORD mws IDENTIFIER )?

repetition   = exclusion ( ows ASTERISK ows rep-count )?

rep-count    = INTEGER ( ows RANGE-OPERATOR ows rep-upper )?

rep-upper    = INTEGER | QUESTION-MARK

exclusion    = range-item ( mws EXCLUDING-KEYWORD mws range-item )?

range-item   = atom ( ows RANGE-OPERATOR ows atom )?

atom         = SINGLE-QUOTED-LITERAL
             | DOUBLE-QUOTED-LITERAL
             | CHARACTER-CLASS
             | POSITION-ASSERTION-TOK
             | interpolation
             | group

interpolation = LEFT-BRACE ows IDENTIFIER ows RIGHT-BRACE

group         = LEFT-PAREN ows expression ows RIGHT-PAREN

ows           = ( WHITESPACE | COMMENT )*
mws           = ( WHITESPACE | COMMENT )+
```

### 4.2 Operator Precedence

Operators that appear deeper in the grammar hierarchy bind more tightly. From tightest to loosest:

| Level | Operator / construct |
|------:|:---------------------|
| 1 (tightest) | `( )` grouping, `{ }` interpolation |
| 2 | `..` character range |
| 3 | `excluding` set difference |
| 4 | `*` repetition |
| 5 | `as` capture |
| 6 | sequence (mandatory whitespace) |
| 7 (loosest in expression) | `\|` alternation |
| — | `=` definition (statement level, not an operator) |

### 4.3 Whitespace Significance

Whitespace is significant only at the `sequence` level, where mandatory whitespace (`mws`) between two `capture` non-terminals acts as the concatenation ("followed by") operator. Whitespace around all other constructs — operators, assignment, semicolons, braces, parentheses — is purely cosmetic and absorbed by `ows`.

Parsing resolves the potential ambiguity between "whitespace as separator" and "whitespace as formatting" by operator precedence. After successfully parsing a `capture`, the parser looks ahead past any whitespace: if the next non-whitespace token can begin a new `capture` (i.e. a literal, `%`, `{`, `(`, or `@`) then the whitespace is treated as a sequence separator; otherwise it is discarded as `ows` belonging to the enclosing rule.

Because `as`, `excluding`, `*`, `|`, and `..` have higher precedence than the sequence operator, they are consumed before the sequence rule sees the surrounding whitespace. For example, `%Digit * 4` is a single `repetition`, not a sequence of `%Digit` and `* 4`: the `ows ASTERISK ows` inside `repetition` absorbs those spaces.

### 4.4 Annotation Syntax

Annotations appear before all definitions. Each annotation is:

```
! identifier = true | false
```

The `!` (bang) character immediately precedes the annotation name with no intervening whitespace. The annotation name is an identifier (alphanumeric with hyphens). The value is the literal keyword `true` or `false`.

### 4.5 Repetition Count Forms

| Syntax      | Meaning                               |
|:-----------:|:--------------------------------------|
| `* n`       | Exactly `n` repetitions              |
| `* n..m`    | Between `n` and `m` repetitions (inclusive) |
| `* n..?`    | At least `n` repetitions, no upper bound |

`n` and `m` are unsigned decimal integers with at most 5 digits. The special upper bound `?` means unbounded (compiled to `*` or `+` as appropriate). `* 0..1` is the idiomatic "optional" form.

---

## 5. Character Classes

Character classes are written `%Identifier` where `Identifier` begins with an uppercase letter. They match exactly one character.

### 5.1 Special

| Identifier | Meaning                                |
|:----------:|:---------------------------------------|
| `%Any`     | Any single character (including newline) |

### 5.2 POSIX Character Classes

| Identifier | Meaning                                          |
|:----------:|:-------------------------------------------------|
| `%Alnum`   | Alphanumeric ASCII characters (`[A-Za-z0-9]`)   |
| `%Alpha`   | ASCII alphabetic characters (`[A-Za-z]`)         |
| `%Ascii`   | Any ASCII character (codepoints 0–127)           |
| `%Blank`   | Space or tab                                     |
| `%Cntrl`   | ASCII control characters (codepoints 0–31 and 127) |
| `%Digit`   | ASCII decimal digits (`[0-9]`)                   |
| `%Graph`   | Visible ASCII characters (non-space, non-control)|
| `%Lower`   | ASCII lowercase letters (`[a-z]`)                |
| `%Print`   | Printable ASCII characters (graph + space)       |
| `%Punct`   | ASCII punctuation and symbol characters          |
| `%Space`   | ASCII whitespace (space, tab, newline, CR, FF, VT)|
| `%Upper`   | ASCII uppercase letters (`[A-Z]`)                |
| `%Word`    | ASCII word characters (`[A-Za-z0-9_]`)           |
| `%Xdigit`  | Hexadecimal digits (`[0-9A-Fa-f]`)               |

### 5.3 Unicode General Categories (Short Names)

| Identifier | Meaning                                          |
|:----------:|:-------------------------------------------------|
| `%C`       | Any "other" character (Cc, Cf, Cn, Co, Cs)      |
| `%Cc`      | Control character                                |
| `%Cf`      | Format character (e.g. zero-width joiner)        |
| `%Cn`      | Unassigned codepoint                             |
| `%Co`      | Private-use character                            |
| `%Cs`      | Surrogate codepoint                              |
| `%L`       | Any letter (Ll, Lm, Lo, Lt, Lu)                 |
| `%Ll`      | Lowercase letter                                 |
| `%Lm`      | Modifier letter                                  |
| `%Lo`      | Other letter (e.g. CJK ideographs)              |
| `%Lt`      | Titlecase letter                                 |
| `%Lu`      | Uppercase letter                                 |
| `%M`       | Any mark (Mc, Me, Mn)                           |
| `%Mc`      | Spacing combining mark                           |
| `%Me`      | Enclosing mark                                   |
| `%Mn`      | Non-spacing mark                                 |
| `%N`       | Any number (Nd, Nl, No)                         |
| `%Nd`      | Decimal digit number                             |
| `%Nl`      | Letter number (e.g. Roman numerals)             |
| `%No`      | Other number (e.g. fractions, superscripts)     |
| `%P`       | Any punctuation (Pc, Pd, Pe, Pf, Pi, Po, Ps)   |
| `%Pc`      | Connector punctuation (e.g. underscore)         |
| `%Pd`      | Dash punctuation                                 |
| `%Pe`      | Close punctuation (e.g. `)`, `]`)               |
| `%Pf`      | Final quote punctuation                          |
| `%Pi`      | Initial quote punctuation                        |
| `%Po`      | Other punctuation                                |
| `%Ps`      | Open punctuation (e.g. `(`, `[`)                |
| `%S`       | Any symbol (Sc, Sk, Sm, So)                     |
| `%Sc`      | Currency symbol                                  |
| `%Sk`      | Modifier symbol                                  |
| `%Sm`      | Mathematical symbol                              |
| `%So`      | Other symbol                                     |
| `%Z`       | Any separator (Zl, Zp, Zs)                      |
| `%Zl`      | Line separator                                   |
| `%Zp`      | Paragraph separator                              |
| `%Zs`      | Space separator                                  |

### 5.4 Unicode General Category Long Names

These PascalCase identifiers are aliases for the short forms above.

| Long name                 | Short | Long name                 | Short |
|:--------------------------|:-----:|:--------------------------|:-----:|
| `%ClosePunctuation`       | `%Pe` | `%OpenPunctuation`        | `%Ps` |
| `%ConnectorPunctuation`   | `%Pc` | `%Other`                  | `%C`  |
| `%Control`                | `%Cc` | `%OtherLetter`            | `%Lo` |
| `%CurrencySymbol`         | `%Sc` | `%OtherNumber`            | `%No` |
| `%DashPunctuation`        | `%Pd` | `%OtherPunctuation`       | `%Po` |
| `%DecimalNumber`          | `%Nd` | `%OtherSymbol`            | `%So` |
| `%EnclosingMark`          | `%Me` | `%ParagraphSeparator`     | `%Zp` |
| `%FinalPunctuation`       | `%Pf` | `%PrivateUse`             | `%Co` |
| `%Format`                 | `%Cf` | `%Punctuation`            | `%P`  |
| `%InitialPunctuation`     | `%Pi` | `%Separator`              | `%Z`  |
| `%Letter`                 | `%L`  | `%SpaceSeparator`         | `%Zs` |
| `%LetterNumber`           | `%Nl` | `%SpacingMark`            | `%Mc` |
| `%LineSeparator`          | `%Zl` | `%Surrogate`              | `%Cs` |
| `%LowercaseLetter`        | `%Ll` | `%Symbol`                 | `%S`  |
| `%Mark`                   | `%M`  | `%TitlecaseLetter`        | `%Lt` |
| `%MathSymbol`             | `%Sm` | `%Unassigned`             | `%Cn` |
| `%ModifierLetter`         | `%Lm` | `%UppercaseLetter`        | `%Lu` |
| `%ModifierSymbol`         | `%Sk` | `%Number`                 | `%N`  |
| `%NonspacingMark`         | `%Mn` | `%Word`                   | `%Word` |

---

## 6. Annotations

Annotations configure compilation options for the entire pattern. They must all appear before any subpattern definitions, in any order. Each annotation may be set at most once.

| Annotation                         | Values          | Default | Meaning |
|:-----------------------------------|:---------------:|:-------:|:--------|
| `!case-insensitive`                | `true`/`false`  | `false` | Causes literal strings and character ranges to match both uppercase and lowercase characters. Compiles to the `i` regex flag. |
| `!multiline`                       | `true`/`false`  | `false` | Enables multiline mode: `@line-start` and `@line-end` match at the start and end of each line rather than the whole string. Also causes `matchesAllOf`, `matchesStartOf`, and `matchesEndOf` to operate at line boundaries rather than string boundaries (see §9.1). Also enabled automatically when `@line-start` or `@line-end` appears anywhere in the pattern. Compiles to the `m` regex flag. |
| `!replacements-ignore-matching`    | `true`/`false`  | `false` | When `true`, replacement values are not validated against their capture subpatterns. See §10. Has no effect on `substitute()`. |
| `!substitutable`                   | `true`/`false`  | `false` | Declares that the pattern is substitutable (§11). Triggers a compile-time structural check. Required before `substitute()` may be called at runtime. |
| `!substitutions-ignore-matching`   | `true`/`false`  | `false` | When `true`, capture values passed to `substitute()` are not validated against their subpatterns. See §11. Has no effect on replacement operations. Setting this annotation without also setting `!substitutable = true` is a compile-time error. |

---

## 7. Compile-Time Constraints

The following constraints are checked after parsing. A ptern that violates any constraint fails to compile; the error is reported before any pattern is available for use.

### 7.1 String Literal Constraints

**Empty literal** — An empty string literal `''` or `""` is an error. Every literal must contain at least one character.

**Invalid escape sequence** — A string literal containing `\X` where `X` is not one of the recognised escape characters from §3.3 is an error.

**Invalid Unicode escape** — `\uXXXX` must form a valid Unicode scalar value (U+0000–U+D7FF or U+E000–U+10FFFF expressed as exactly four hex digits).

### 7.2 Character Range Constraints

**Single-character endpoints** — Both sides of a `..` range must match exactly one character. A multi-character literal such as `'ab'..'z'` is an error; a character class such as `%Digit` is an error as a range endpoint.

**Non-inverted range** — A range `'a'..'z'` requires that the Unicode code point of `a` is ≤ the code point of `z`. An inverted range such as `'z'..'a'` is an error. Equal endpoints (`'a'..'a'`) are valid and match exactly that one character.

### 7.3 Exclusion Constraints

**Single-character operands** — Both sides of `excluding` must match exactly one character. A group `(...)` or an interpolation `{...}` on either side of `excluding` is an error.

**Non-empty result** — When both operands are structurally identical (e.g. `%Digit excluding %Digit` or `'x' excluding 'x'` or `'a'..'z' excluding 'a'..'z'`), the resulting character class can never match any character and is a compile-time error.

Note: ptern's static analysis is structural — it only catches cases where the two sides are textually the same expression. Semantically equivalent but textually distinct pairs such as `%Digit excluding '0'..'9'` are not detected as empty.

### 7.4 Repetition Bound Constraints

**Non-inverted bounds** — For `E * n..m`, `n` must be ≤ `m`. `* 10..3` is an error. Equal bounds (`* 3..3`) are valid and equivalent to `* 3`.

### 7.5 Subpattern Definition Constraints

**Unique definition names** — Two definitions sharing the same name (e.g. `foo = 'a' ; foo = 'b' ;`) is an error.

**No circular definitions** — A definition that references itself directly or through a cycle (e.g. `foo = {foo} ;` or `foo = {bar} ; bar = {foo} ;`) is an error.

**Definitions reference only definitions** — Inside a definition body, `{identifier}` may only reference other definition names, not capture names from the body expression.

### 7.6 Name Resolution Constraints

**No undefined references** — `{identifier}` in the body expression where `identifier` is neither a definition name nor a capture name already established earlier in the body is an error.

**Capture–definition conflict** — Using the same name for both a definition (`name = ...;`) and a capture (`... as name`) is an error.

### 7.7 Capture Name Constraints

**Multiple occurrences are allowed** — The same capture name may appear at more than one position in the body expression. All occurrences bind to the same capture slot. During matching, the last matched value is returned. During replacement and substitution, the same provided value applies to every occurrence (see §10 and §11).

### 7.8 Interpolation Semantics

`{identifier}` resolves according to which namespace `identifier` belongs:

- If `identifier` is a **definition name**: the interpolation is a **subpattern interpolation** — it expands to the compiled pattern of the definition body, enclosed in a non-capturing group. This is purely a pattern-matching construct: it matches the same strings as the definition would.
- If `identifier` is a **capture name** (established by a prior `expression as identifier` in the same body): the interpolation is a **backreference** — it matches the exact text captured at the earlier position, as if it were the literal string that was captured.

A definition name and a capture name may not be the same (§7.6).

### 7.9 Position Assertion Constraints

The recognised position assertion names are:

| Name          | Zero-width assertion matched            |
|:--------------|:----------------------------------------|
| `@word-start` | Boundary between a non-word and a word character (equivalent to `\b` at the leading edge) |
| `@word-end`   | Boundary between a word and a non-word character (equivalent to `\b` at the trailing edge) |
| `@line-start` | Start of a line (enables multiline mode automatically) |
| `@line-end`   | End of a line (enables multiline mode automatically) |

**Unknown position assertion** — `@name` where `name` is not in the table above is an error.

**Position assertion in repetition** — Applying a repetition count (`* n` or `* n..m`) directly to a position assertion (e.g. `@word-start * 3`) is an error. A position assertion is zero-width and cannot be meaningfully repeated.

### 7.10 Annotation Constraints

**Unknown annotation** — An annotation with a name not in the table in §6 is an error.

**Duplicate annotation** — The same annotation set more than once in a single ptern is an error.

**`!substitutions-ignore-matching` requires `!substitutable`** — Setting `!substitutions-ignore-matching = true` without also setting `!substitutable = true` is an error.

### 7.11 Substitutability Constraints

When `!substitutable = true` is set, the compiler verifies that the body expression is *substitutable* according to the rules in §11.2. If the body fails the check, the ptern does not compile.

---

## 8. Matching Semantics

### 8.1 Character Sequences

Each construct defines the set of strings it matches:

| Construct                         | Matches                                                  |
|:----------------------------------|:---------------------------------------------------------|
| `'text'` or `"text"`             | Exactly the literal string `text`                        |
| `%Class`                          | Any single character in the named class (§5)            |
| `'a'..'z'`                        | Any single character whose code point is in the range   |
| `E excluding F`                   | Any single character matched by `E` but not by `F`      |
| `E1 E2 ... En` (sequence)        | A string that is the concatenation of strings matching each `Ei` in order |
| `E1 \| E2 \| ... \| En` (alternation) | A string matched by any one of the `Ei`; leftmost matching branch is selected |
| `(E)` (group)                     | Same as `E`; used to override precedence                |
| `E * n`                           | Exactly `n` consecutive matches of `E` concatenated     |
| `E * n..m`                        | Between `n` and `m` consecutive matches of `E` concatenated (greedy: prefers maximum) |
| `E * n..?`                        | At least `n` consecutive matches of `E` concatenated (greedy) |
| `E as name`                       | Same strings as `E`; also records the matched text as capture `name` |
| `{id}` (definition interpolation) | Same as the body of definition `id`                     |
| `{id}` (backreference)            | Exactly the text previously captured by `name = id`     |
| `@word-start`                     | Zero-width: position at start of a word                 |
| `@word-end`                       | Zero-width: position at end of a word                   |
| `@line-start`                     | Zero-width: position at start of a line                 |
| `@line-end`                       | Zero-width: position at end of a line                   |

### 8.2 Named Captures

`E as name` records the substring of the input matched by `E` under the name `name`. When the same name appears at multiple positions in the body, the capture slot holds the value from the **last** position that participated in the match (JavaScript named-group semantics: later matches overwrite earlier ones).

In patterns with repeated subpatterns (`E * n` or `E * n..m`), a capture `name` inside `E` is overwritten on each iteration; the capture slot holds the last iteration's value after the match completes.

### 8.3 Length Bounds

The compiler computes the minimum and maximum matched length for the body expression:

| Construct          | Min length                 | Max length                     |
|:-------------------|:---------------------------|:-------------------------------|
| Literal `'text'`  | `len(text)`               | `len(text)`                    |
| `%Class`, `'a'..'z'`, `E excluding F` | 1 | 1                  |
| `E1 E2 ... En`    | `sum(min(Ei))`             | `sum(max(Ei))`                 |
| `E1 \| ... \| En` | `min(min(Ei))`             | `max(max(Ei))`                 |
| `(E)`              | `min(E)`                   | `max(E)`                       |
| `E * n`            | `n × min(E)`               | `n × max(E)`                   |
| `E * n..m`         | `n × min(E)`               | `m × max(E)`                   |
| `E * n..?`         | `n × min(E)`               | unbounded                      |
| `E as name`        | `min(E)`                   | `max(E)`                       |
| `{id}`             | `min(body of id)`          | `max(body of id)`              |
| Position assertion | 0                          | 0                              |

When the maximum length is unbounded, `maxLength()` returns null / `None`.

---

## 9. Compiled Pattern Operations

A successfully compiled ptern supports the following operations. In all cases the comparison ignores the `^`/`$` anchoring internally applied by each operation.

### 9.1 Boolean Tests

| Operation          | Returns `true` if…                                          |
|:-------------------|:------------------------------------------------------------|
| `matchesAllOf(s)`  | The pattern matches the entire string `s`                   |
| `matchesStartOf(s)`| The pattern matches a prefix of `s` starting at index 0    |
| `matchesEndOf(s)`  | The pattern matches a suffix of `s` ending at `len(s)`     |
| `matchesIn(s)`     | The pattern matches some substring of `s`                   |

When `!multiline = true` is set (or auto-enabled by `@line-start`/`@line-end`), `matchesAllOf`, `matchesStartOf`, and `matchesEndOf` operate at **line** boundaries rather than string boundaries: `matchesAllOf` returns `true` if any complete line in `s` is a full match, `matchesStartOf` returns `true` if a match begins at the start of any line, and `matchesEndOf` returns `true` if a match ends at the end of any line. `matchesIn` is unaffected.

### 9.2 Match Occurrences

A **match occurrence** is a triple:

```
MatchOccurrence {
  index:    non-negative integer — start position in the input string
  length:   non-negative integer — length of the matched substring
  captures: dictionary mapping capture names to their matched strings
}
```

The `captures` dictionary contains one entry per distinct capture name defined in the pattern, populated with the value from the last matching position for each name (§8.2). Synthetic internal names (those beginning with `__`) are not exposed.

| Operation                      | Returns                                                                 |
|:-------------------------------|:------------------------------------------------------------------------|
| `matchAllOf(s)`                | `MatchOccurrence` if the whole string matches, else null/None           |
| `matchStartOf(s)`              | `MatchOccurrence` for the prefix match, else null/None                  |
| `matchEndOf(s)`                | `MatchOccurrence` for the suffix match, else null/None                  |
| `matchFirstIn(s)`              | `MatchOccurrence` for the first occurrence anywhere in `s`, else null/None |
| `matchNextIn(s, startIndex)`   | `MatchOccurrence` for the first occurrence at or after `startIndex`, else null/None |
| `matchAllIn(s)`                | List of `MatchOccurrence` for every non-overlapping occurrence in `s`, in order |

### 9.3 Length Metadata

| Operation      | Returns                                                   |
|:---------------|:----------------------------------------------------------|
| `minLength()`  | The minimum length matched by the pattern (integer ≥ 0)  |
| `maxLength()`  | The maximum length matched, or null/None if unbounded    |

---

## 10. Replacement

Replacement modifies a string by substituting provided values for named captures within a match, leaving all other text unchanged. An original input string provides the baseline: any capture not given a replacement retains its originally matched text.

### 10.1 Concepts

**Capture-values dict** — A dictionary mapping capture names to replacement values. Each value is either a `string` (scalar) or a `string[]` (array). Arrays are used to replace per-iteration values of captures inside repetitions (§10.4).

**Replacement point** — A `E as name` expression is a replacement point. If `name` appears in the captures dict, the provided value is used instead of the original matched text. If absent, the original matched text passes through unchanged.

**Short-circuit rule** — When a replacement value is provided for `name`, the inner expression `E` is not evaluated. Any inner captures within `E` that are also in the captures dict are silently ignored; only `name`'s value is substituted.

### 10.2 Scalar Replacement Semantics

**`replace(E, captures, original, span) → string`** is the recursive function applied to a single match. `original` is the full input string; `span = (start, end)` is the region matched by `E`.

```
replace('text', captures, original, span)
  = original[span.start .. span.end]   // original matched text

replace(%Class, captures, original, span)
  = original[span.start .. span.end]   // original matched character

replace(E as name, captures, original, span):
  if name ∈ captures and captures[name] is string:
    validate captures[name] against E's regex  (unless !replacements-ignore-matching)
    return captures[name]
  if name ∈ captures and captures[name] is string[]:
    error: WrongReplacementType(name)   // scalar context
  if name ∉ captures:
    return replace(E, captures, original, span_of_E)

replace(E1 E2 ... En, captures, original, span)
  = replace(E1, ..., span_of_E1) + replace(E2, ..., span_of_E2) + ... + replace(En, ..., span_of_En)

replace(E1 | ... | En, captures, original, span)
  = replace(Ei, ..., span_of_Ei)    // where Ei is the branch that matched

replace((E), captures, original, span)
  = replace(E, captures, original, span)

replace(E * n, captures, original, span)
  = replace(E, ..., span_of_iter_1) + ... + replace(E, ..., span_of_iter_n)

replace(E * n..m, captures, original, span)
  = replace(E, ..., span_of_iter_1) + ... + replace(E, ..., span_of_iter_k)
    where k is the actual iteration count from the match (n ≤ k ≤ m)
```

### 10.3 Multiple Occurrences of a Capture Name

When a capture name appears at more than one position in the pattern, the same scalar replacement value applies uniformly to every occurrence. Each occurrence is an independent replacement point and is patched independently using its own matched span.

### 10.4 Array-Valued Replacement (Captures Inside Repetitions)

A capture `name` inside a repeated sub-pattern `E * n..m` may be provided as a `string[]` in the captures dict, with one element per iteration:

- `captures[name][i]` replaces the matched value of `name` in iteration `i` (0-indexed).
- The array length must equal `k`, the actual iteration count from the original match. A mismatch is a runtime error: `ArrayLengthMismatch(name, provided, actual)`.
- A `string` (scalar) may also be provided for a capture inside a repetition; the same value is applied to every iteration (broadcast).

When a capture name appears in both a non-repeated position and a repeated position (e.g. `{field} as col (',' {field} as col) * 0..20`), and an array value is provided, the first element of the array is consumed by the non-repeated occurrence and the remaining elements are consumed by the repetition iterations. The array length must therefore equal `1 + k`, where `k` is the iteration count.

A `string[]` provided for a capture that does not appear inside any repetition is a runtime error: `WrongReplacementType(name)`.

A `string[]` provided for a capture that appears inside two or more distinct repetitions is a runtime error: `DuplicateRepetitionCapture(name)`.

### 10.5 Runtime Errors

| Error                                  | Condition                                                                   |
|:---------------------------------------|:----------------------------------------------------------------------------|
| `InvalidReplacementValue(name, value)` | `value` does not match the sub-pattern for `name`; only when `!replacements-ignore-matching = false` |
| `WrongReplacementType(name)`           | A `string[]` provided for a capture not inside any repetition               |
| `ArrayLengthMismatch(name, n, k)`      | Array length `n` ≠ actual iteration count `k`                              |
| `DuplicateRepetitionCapture(name)`     | A `string[]` provided for a capture appearing in two or more distinct repetitions |

A missing capture is never an error; the original matched text is always a valid fallback.

### 10.6 Operations

Each replace operation returns the modified input string, or the original input unchanged if the pattern does not match.

| Operation                                 | Match region                             |
|:------------------------------------------|:-----------------------------------------|
| `replaceAllOf(input, replacements)`       | The whole string (requires full match)   |
| `replaceStartOf(input, replacements)`     | A prefix of the string                   |
| `replaceEndOf(input, replacements)`       | A suffix of the string                   |
| `replaceFirstIn(input, replacements)`     | The first occurrence anywhere            |
| `replaceNextIn(input, startIndex, replacements)` | The first occurrence at or after `startIndex` |
| `replaceAllIn(input, replacements)`       | All non-overlapping occurrences, left-to-right; the same `replacements` dict is applied to each match |

Extra keys in `replacements` that do not correspond to any named capture (including captures from unmatched alternation branches) are silently ignored.

---

## 11. Substitution

Substitution assembles a string from a ptern and a dictionary of named capture values, without an original input string. It is the inverse of matching: where `match*` extracts named captures from a string, `substitute` constructs a string from named capture values.

Substitution requires `!substitutable = true` (§6). Calling `substitute()` on a ptern without this annotation is a runtime error.

### 11.1 Concepts

**Substitution point** — A `E as name` expression is a substitution point. If `name` is provided in the captures dict, it short-circuits evaluation of `E`. If absent, evaluation falls through into `E`, which must itself be substitutable.

**Substitutable expression** — An expression is *substitutable* if `evaluate(E, captures)` (§11.3) can always succeed from a captures dict alone, without an original input string. This is a compile-time property (§11.2).

### 11.2 Substitutability Rules

The compiler checks substitutability when `!substitutable = true` is set. The check is recursive:

| Expression                     | Substitutable?                                                  |
|:-------------------------------|:----------------------------------------------------------------|
| `'text'`                       | Yes — produces its text unconditionally                         |
| `%Class`, `'a'..'z'`, `E excluding F` | No — matches a set of characters but does not determine a unique output |
| `(E)`                          | Same as `E`                                                     |
| `E1 E2 ... En` (sequence)      | Yes iff every `Ei` is substitutable                             |
| `E1 \| ... \| En` (alternation)| Yes iff every `Ei` is substitutable                             |
| `E * n` (fixed repetition)     | Yes iff `E` is substitutable                                    |
| `E * n..m` (bounded repetition)| Yes iff `E` contains at least one named capture (array length drives the iteration count) |
| `E as name`                    | Always yes — `name` is a direct substitution point regardless of `E` |
| `{id}` (definition interpolation) | Same as the substitutability of the body of `id`             |

A bounded repetition `E * n..m` with no named capture inside `E` is a compile-time error when `!substitutable = true` is set: `BoundedRepetitionNeedsCapture`.

### 11.3 Substitution Semantics

**`evaluate(E, captures) → string | error`**

```
evaluate('text', captures) = "text"

evaluate(E as name, captures):
  if name ∈ captures:
    if captures[name] is not a string: error — scalar required
    validate captures[name] against E's regex  (unless !substitutions-ignore-matching)
    return captures[name]   // inner E is not evaluated; inner captures silently ignored
  if name ∉ captures and E is substitutable:
    return evaluate(E, captures)
  if name ∉ captures and E is not substitutable:
    error: MissingCapture(name)

evaluate(E1 E2 ... En, captures)
  = evaluate(E1, captures) + evaluate(E2, captures) + ... + evaluate(En, captures)
    (error propagates immediately from any Ei)

evaluate(E1 | ... | En, captures):
  try each Ei in order:
    if evaluate(Ei, captures) succeeds: return that result
  if all branches fail: error: NoMatchingBranch
  (a branch fails only when a required capture is absent and the branch cannot proceed
   without it; a validation failure on a provided value propagates immediately)

evaluate((E), captures) = evaluate(E, captures)

evaluate(E * n, captures)
  = evaluate(E, captures) repeated n times and concatenated

evaluate(E * n..m, captures):
  let array-captures = { name : captures[name] | captures[name] is string[] }
  let len = common length of all arrays in array-captures
  (error if any two arrays differ in length)
  (error if no array and no fixed-n source for the count)
  for i in 0..len-1:
    evaluate E with each array-valued capture replaced by its i-th element

evaluate({id}, captures) = evaluate(definition_of(id), captures)
```

### 11.4 Multiple Occurrences of a Capture Name

When the same capture name appears in both a non-repeated and a repeated position, the array of provided values is split: the first element is consumed by the first (non-repeated) occurrence; the remainder is consumed by the repetition. The array length must therefore be `1 + k`, where `k` is the iteration count. All provided array values within the same repetition must have the same length.

### 11.5 Runtime Errors

| Error                                   | Condition                                                               |
|:----------------------------------------|:------------------------------------------------------------------------|
| `NotSubstitutable`                      | `substitute()` called on a ptern without `!substitutable = true`        |
| `MissingCapture(name)`                  | A required capture is absent and its expression is not substitutable    |
| `CaptureMismatch(name, value)`          | `value` does not match the sub-pattern for `name`; only when `!substitutions-ignore-matching = false` |
| `WrongCaptureType(name)`                | `string[]` provided where `string` is required, or vice versa           |
| `ArrayLengthError(name, length, min, max)` | Array length outside the repetition bounds `[n, m]`, or two arrays within the same repetition differ in length |
| `NoMatchingBranch`                      | All branches of an alternation fail                                     |

### 11.6 Operation

```
substitute(captures: dict<string, string | string[]>) → string | error
```

Returns the assembled string, or an error. Extra keys in `captures` that do not correspond to any named capture are silently ignored.

---

## 12. Examples

### 12.1 ISO Date YYYY-MM-DD

```
yyyy = %Digit * 4;
mm = '0' '1'..'9' | '1' '0'..'2';
dd = '0' '1'..'9' | '1'..'2' %Digit | '3' '0'..'1';
{yyyy} as year '-' {mm} as month '-' {dd} as day
```

Equivalent regex: `\d{4}-(0[1-9]|1[0-2])-(0[1-9]|[12]\d|3[01])`

### 12.2 24-Hour Time HH:MM[:SS]

```
hr = '0'..'1' %Digit | '2' '0'..'3';
ms = '0'..'5' %Digit;
{hr} ':' {ms} (':' {ms}) * 0..1
```

Equivalent regex: `([01]\d|2[0-3]):[0-5]\d(:[0-5]\d)?`

### 12.3 Semantic Version

```
num = %Digit * 1..10;
{num} as major '.' {num} as minor '.' {num} as patch
```

Equivalent regex: `\d+\.\d+\.\d+`

### 12.4 IPv4 Address (Strictly 0–255)

No concise regex equivalent.

```
octet = %Digit
      | '1'..'9' %Digit
      | '1' %Digit %Digit
      | '2' '0'..'4' %Digit
      | '2' '5' '0'..'5';
{octet} as a '.' {octet} as b '.' {octet} as c '.' {octet} as d
```

### 12.5 UUID / GUID

```
%Xdigit * 8 '-' (%Xdigit * 4 '-') * 3 %Xdigit * 12
```

Equivalent regex: `[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}`

### 12.6 CSV with Named Captures and Substitution

```
!substitutable = true
field = %Any * 1..100;
{field} as col (',' {field} as col) * 0..20
```

```
csv.substitute({ col: ["name", "age", "city"] })
// "name,age,city"

csv.replaceFirstIn("name,age,city", { col: ["NAME", "AGE", "CITY"] })
// "NAME,AGE,CITY"

csv.replaceFirstIn("name,age,city", { col: "X" })
// "X,X,X"  (scalar broadcast)
```

### 12.7 HTML-Like Tag with Matching Attribute

```
!substitutable = true
word = %Alpha * 1..20;
'<' {word} as tag '>' {word} as body '</' {word} as tag '>'
```

```
tagged.matchFirstIn("<em>hello</em>")
// { index: 0, length: 14, captures: { tag: "em", body: "hello" } }

tagged.substitute({ tag: "em", body: "hello" })
// "<em>hello</em>"

tagged.replaceFirstIn("<em>hello</em>", { tag: "strong", body: "world" })
// "<strong>world</strong>"
```

### 12.8 Case-Insensitive Hex Color

```
!case-insensitive = true
'#' (%Xdigit * 6 | %Xdigit * 3)
```

Equivalent regex: `#([a-fA-F0-9]{6}|[a-fA-F0-9]{3})` with `i` flag.

### 12.9 Floating-Point Number

```
!case-insensitive = true
digits = %Digit * 1..20;
exp    = 'e' ('+' | '-') * 0..1 {digits} as exponent;
('+' | '-') * 0..1 {digits} as integer ('.' {digits}) * 0..1 {exp} * 0..1
```

Equivalent regex: `[+-]?\d+(\.\d+)?([eE][+-]?\d+)?`

### 12.10 Word Boundary Matching

```
@word-start %Alpha * 1..? @word-end
```

Matches a complete alphabetic word (no partial matches within a larger word).

---

*End of Ptern Language Specification*
