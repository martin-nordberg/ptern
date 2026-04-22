# "Ptern"

Martin Nordberg - 2026-04-04

## What's With the Name?

"PT+ERN" is a "backandforthronym":

* _Backwards_ - *(NRET+P){2}* - *N*ormal *R*egular *E*xpressions *T*ranslate *T*o *T*wo *P*roblems:
*N*otoriously, *R*egular *E*xpressions are *T*hemselves *T*iresomely *T*erse *P*uzzles.[^joke]
* _Forwards_ - *PT+ERN* - *P*attern *T*ext *T*ranslated *T*o *E*asily *R*eadable *N*otation.

[^joke]: Classic computer science joke: "I had a problem. I solved it with a regular expression.
Now I have two problems."

Or, if you prefer a recursive acronym:

* *PT+ERN* - *P*tern's a *T*ext *T*ranslation *T*ool *T*hat *E*nables *R*eading *N*aturally

And note that "ptern" (we pronounce it "turn") could be an out-of-the-ordinary abbreviation
for the word "pattern".

Enough fluff! Show me...

## Ptern By Example

Here is an example Ptern string matching pattern (just a "ptern" from now on):

```
yyyy = %Digit * 4;
mm = '0' '1'..'9' | '1' '0'..'2';
dd = '0' '1'..'9' | '1'..'2' %Digit | '3' '0'..'1';
{yyyy} as year '-' {mm} as month '-' {dd} as day
```

It is way more verbose than the corresponding regular expression, but it is also far more readable.
We think that's true even if you haven't yet learned the Ptern grammar.

Here's how that example ptern can be put to use (shown using the TypeScript API — see [Language Support](#language-support)):

```
isoDate.matchesAllOf("2026-07-04")
// true

isoDate.matchesStartOf("2026-07-04T12:00")
// true

isoDate.matchesEndOf("Independence Day is 2026-07-04")
// true

isoDate.matchesIn("Independence Day 2026-07-04 - the 250th")
// true

isoDate.matchAllOf("2026-07-04")
// { index: 0, length: 10, captures: { year: "2026", month: "07", day: "04" } }

isoDate.matchFirstIn("Independence Day 2026-07-04 - the 250th")
// { index: 17, length: 10, captures: { year: "2026", month: "07", day: "04" } }

isoDate.matchAllIn("2026-07-04 and 2026-12-25")
// [
//   { index: 0,  length: 10, captures: { year: "2026", month: "07", day: "04" } },
//   { index: 15, length: 10, captures: { year: "2026", month: "12", day: "25" } }
// ]

isoDate.replaceFirstIn("Independence Day 2026-07-04 - the 250th", { year: "2027" })
// "Independence Day 2027-07-04 - the 250th"

isoDate.replaceAllIn("2026-07-04 and 2026-12-25", { year: "2027" })
// "2027-07-04 and 2027-12-25"
```

A ptern also offers metadata about the pattern itself. For example:

```
isoDate.maxLength()             
// 10

isoDate.minLength()             
// 10
```

## Overview of Ptern

### Ptern Character Sequences

| Syntax | Meaning | Example |
|--------|---------|---------|
| 'xyz' | Literal text | 'For score and' |
| "abc" | Literal text | "brought forth" |
| _char_.._char_ | Character class range (one character within the inclusive range) | 'a'..'z' |
| %_identifier_ | One character from a Unicode character class or a Posix character class (listed later) | %Digit |

### Escape Sequences (Only Inside Literal Strings)

| Syntax | Meaning | Example |
|--------|---------|---------|
| \a \f \n \r \t \v | The usual whitespace control characters from C | '\t' |
| \\' \\" | Escaped quote characters | 'She said, "He said, \\'this is an inner quotation\\'." ' |
| \\\\ | When you need a literal backslash | "C:\\\\windows\\\\system" |
| \uXXXX | A specific unicode character by code. ('X' is a hexadecimal digit.) | '\u00E9' == 'é' |

### Operators

| Syntax | Meaning | Example |
|--------|---------|---------|
| <ptern1>\ <ptern2> | Sequence of smaller patterns. The space character between is required to enforce readability. | %Alpha %Alnum | 
| <ptern> * <integer> | Fixed repetition count. | '-' * 3 |
| <ptern> * <integer>..<integer> | Bounded repetition count. | '-' * 3..10 |
| <ptern> * <integer>..? | Unbounded repetition (at least N times, no upper limit). | %Digit * 1..? |
| <ptern1> \| <ptern2> | Alternatives. | '0'..'9' \| '1' '0'..'2' |
| ( <ptern> ) | Precedence override.| 'A'..'Z' ('0' \| '1') |
| <ptern>\ as\ <identifier> | Subpattern captured by name during matching. | %Digit * 4 as year |
| <ptern1>\ excluding\ <ptern2> | Set difference: characters in ptern1 but not ptern2. Both sides must be single-character patterns and ptern2 must be a subset of ptern1 (enforced after parsing). | %Digit excluding '8'..'9' |
| <identifier> = <ptern> ; | Definition of a subpattern. | barcode = %Digit * 20; |
| { <identifier> } | If `identifier` names a definition: subpattern interpolation (pattern match). If `identifier` names a capture: backreference — matches the exact text captured at the earlier point, as if it were a literal string. [Also adds implicit surrounding ( ) .] | {barcode} \| "No SKU" |

### Precedence

| Operator | Precedence |
|:--------:|:----------:|
| ( ) | Highest |
| \{ \} | |
| .. | |
| excluding | |
| * | |
| as | |
| [sequence with space character] |  |
| \| | |
| = | Lowest |

### Annotations

Annotations set compilation options for the whole pattern. They are written
`@identifier = value` and must appear at the very top of the ptern, before
any subpattern definitions.

| Annotation          | Values          | Default | Meaning |
|---------------------|-----------------|---------|---------|
| `@case-insensitive` | `true`, `false` | `false` | When `true`, literal strings and character ranges match both uppercase and lowercase. |


## Ptern Language Structure

### The Lexical Tokens of Ptern Defined as Pterns

```
Whitespace            =  (' '|'\t'|'\r'|'\n') * 1..? ;
Comment               =  '#' (%Any excluding ('\r'|'\n')) * 0..? ;
SingleQuotedLiteral   =  "'" (%Any excluding ("'"|'\r'|'\n')) * 1..? "'" ;
DoubleQuotedLiteral   =  '"' (%Any excluding ('"'|'\r'|'\n')) * 1..? '"' ;
CharacterClass        =  '%' 'A'..'Z' %Alpha * 0..31 ;
Integer               =  %Digit * 1..5 ;
RangeOperator         =  '..' ;
LeftBrace             =  '{' ;
RightBrace            =  '}' ;
AlternativeOperator   =  '|' ;
LeftParenthesis       =  '(' ;
RightParenthesis      =  ')' ;
AssignmentOperator    =  '=' ;
Asterisk              =  '*' ;
Semicolon             =  ';' ;
AsKeyword             =  'as' ;
ExcludingKeyword      =  'excluding' ;
TrueKeyword           =  'true' ;
FalseKeyword          =  'false' ;
AtSign                =  '@' ;
QuestionMark          =  '?' ;
Identifier            =  %Alpha (%Alnum | '-') * 0..63 ;

Whitespace
| Comment
| AsKeyword
| AtSign
| ExcludingKeyword
| QuestionMark
| FalseKeyword
| TrueKeyword
| AlternativeOperator
| AssignmentOperator
| Asterisk
| CharacterClass
| DoubleQuotedLiteral
| Identifier
| Integer
| LeftBrace
| LeftParenthesis
| RangeOperator
| RightBrace
| RightParenthesis
| Semicolon
| SingleQuotedLiteral
```

### Character Class Identifiers

#### Special

| Identifier | Meaning |
|------------|---------|
| `%Any`     | Any single character (including newline) |

#### POSIX Character Classes

| Identifier | Meaning |
|------------|---------|
| `%Alnum`   | Alphanumeric ASCII characters (`[A-Za-z0-9]`) |
| `%Alpha`   | ASCII alphabetic characters (`[A-Za-z]`) |
| `%Ascii`   | Any ASCII character (codepoints 0–127) |
| `%Blank`   | Space or tab |
| `%Cntrl`   | ASCII control characters (codepoints 0–31 and 127) |
| `%Digit`   | ASCII decimal digits (`[0-9]`) |
| `%Graph`   | Visible ASCII characters (non-space, non-control) |
| `%Lower`   | ASCII lowercase letters (`[a-z]`) |
| `%Print`   | Printable ASCII characters (graph + space) |
| `%Punct`   | ASCII punctuation and symbol characters |
| `%Space`   | ASCII whitespace (space, tab, newline, carriage return, form feed, vertical tab) |
| `%Upper`   | ASCII uppercase letters (`[A-Z]`) |
| `%Word`    | ASCII word characters (`[A-Za-z0-9_]`) |
| `%Xdigit`  | Hexadecimal digits (`[0-9A-Fa-f]`) |

#### Unicode General Categories

| Identifier | Meaning |
|------------|---------|
| `%C`       | Any "other" character (Cc, Cf, Cn, Co, Cs) |
| `%Cc`      | Control character |
| `%Cf`      | Format character (e.g. zero-width joiner) |
| `%Cn`      | Unassigned codepoint |
| `%Co`      | Private-use character |
| `%Cs`      | Surrogate codepoint |
| `%L`       | Any letter (Ll, Lm, Lo, Lt, Lu) |
| `%Ll`      | Lowercase letter |
| `%Lm`      | Modifier letter |
| `%Lo`      | Other letter (e.g. CJK ideographs) |
| `%Lt`      | Titlecase letter |
| `%Lu`      | Uppercase letter |
| `%M`       | Any mark (Mc, Me, Mn) |
| `%Mc`      | Spacing combining mark |
| `%Me`      | Enclosing mark |
| `%Mn`      | Non-spacing mark |
| `%N`       | Any number (Nd, Nl, No) |
| `%Nd`      | Decimal digit number |
| `%Nl`      | Letter number (e.g. Roman numerals) |
| `%No`      | Other number (e.g. fractions, superscripts) |
| `%P`       | Any punctuation (Pc, Pd, Pe, Pf, Pi, Po, Ps) |
| `%Pc`      | Connector punctuation (e.g. underscore) |
| `%Pd`      | Dash punctuation |
| `%Pe`      | Close punctuation (e.g. `)`, `]`) |
| `%Pf`      | Final quote punctuation |
| `%Pi`      | Initial quote punctuation |
| `%Po`      | Other punctuation |
| `%Ps`      | Open punctuation (e.g. `(`, `[`) |
| `%S`       | Any symbol (Sc, Sk, Sm, So) |
| `%Sc`      | Currency symbol |
| `%Sk`      | Modifier symbol |
| `%Sm`      | Mathematical symbol |
| `%So`      | Other symbol |
| `%Z`       | Any separator (Zl, Zp, Zs) |
| `%Zl`      | Line separator |
| `%Zp`      | Paragraph separator |
| `%Zs`      | Space separator |

#### Unicode General Category Long Names

These are verbose PascalCase aliases for the entries in the table above.

| Identifier               | Short form | Meaning |
|--------------------------|------------|---------|
| `%ClosePunctuation`      | `%Pe`      | Close punctuation (e.g. `)`, `]`) |
| `%ConnectorPunctuation`  | `%Pc`      | Connector punctuation (e.g. underscore) |
| `%Control`               | `%Cc`      | Control character |
| `%CurrencySymbol`        | `%Sc`      | Currency symbol |
| `%DashPunctuation`       | `%Pd`      | Dash punctuation |
| `%DecimalNumber`         | `%Nd`      | Decimal digit number |
| `%EnclosingMark`         | `%Me`      | Enclosing mark |
| `%FinalPunctuation`      | `%Pf`      | Final quote punctuation |
| `%Format`                | `%Cf`      | Format character (e.g. zero-width joiner) |
| `%InitialPunctuation`    | `%Pi`      | Initial quote punctuation |
| `%Letter`                | `%L`       | Any letter (Ll, Lm, Lo, Lt, Lu) |
| `%LetterNumber`          | `%Nl`      | Letter number (e.g. Roman numerals) |
| `%LineSeparator`         | `%Zl`      | Line separator |
| `%LowercaseLetter`       | `%Ll`      | Lowercase letter |
| `%Mark`                  | `%M`       | Any mark (Mc, Me, Mn) |
| `%MathSymbol`            | `%Sm`      | Mathematical symbol |
| `%ModifierLetter`        | `%Lm`      | Modifier letter |
| `%ModifierSymbol`        | `%Sk`      | Modifier symbol |
| `%NonspacingMark`        | `%Mn`      | Non-spacing mark |
| `%Number`                | `%N`       | Any number (Nd, Nl, No) |
| `%OpenPunctuation`       | `%Ps`      | Open punctuation (e.g. `(`, `[`) |
| `%Other`                 | `%C`       | Any "other" character (Cc, Cf, Cn, Co, Cs) |
| `%OtherLetter`           | `%Lo`      | Other letter (e.g. CJK ideographs) |
| `%OtherNumber`           | `%No`      | Other number (e.g. fractions, superscripts) |
| `%OtherPunctuation`      | `%Po`      | Other punctuation |
| `%OtherSymbol`           | `%So`      | Other symbol |
| `%ParagraphSeparator`    | `%Zp`      | Paragraph separator |
| `%PrivateUse`            | `%Co`      | Private-use character |
| `%Punctuation`           | `%P`       | Any punctuation (Pc, Pd, Pe, Pf, Pi, Po, Ps) |
| `%Separator`             | `%Z`       | Any separator (Zl, Zp, Zs) |
| `%SpaceSeparator`        | `%Zs`      | Space separator |
| `%SpacingMark`           | `%Mc`      | Spacing combining mark |
| `%Surrogate`             | `%Cs`      | Surrogate codepoint |
| `%Symbol`                | `%S`       | Any symbol (Sc, Sk, Sm, So) |
| `%TitlecaseLetter`       | `%Lt`      | Titlecase letter |
| `%Unassigned`            | `%Cn`      | Unassigned codepoint |
| `%UppercaseLetter`       | `%Lu`      | Uppercase letter |

### Extended Backus-Naur Grammar

```ebnf
ptern      = ows annotation* definition* expression ows

annotation       = AT-SIGN IDENTIFIER ows ASSIGNMENT-OPERATOR ows annotation-value ows
annotation-value = TRUE-KEYWORD | FALSE-KEYWORD

definition  = IDENTIFIER ows ASSIGNMENT-OPERATOR ows expression ows SEMICOLON ows

expression  = alternation

alternation = sequence ( ows ALTERNATIVE-OPERATOR ows sequence )*

sequence    = capture ( mws capture )*

capture     = repetition ( mws AS-KEYWORD mws IDENTIFIER )?

repetition  = exclusion ( ows ASTERISK ows rep-count )?

rep-count   = INTEGER ( ows RANGE-OPERATOR ows rep-upper )?

rep-upper   = INTEGER | QUESTION-MARK

exclusion   = range-item ( mws EXCLUDING-KEYWORD mws range-item )?

range-item  = atom ( ows RANGE-OPERATOR ows atom )?

atom        = SINGLE-QUOTED-LITERAL
            | DOUBLE-QUOTED-LITERAL
            | CHARACTER-CLASS
            | interpolation
            | group

interpolation = LEFT-BRACE ows IDENTIFIER ows RIGHT-BRACE

group         = LEFT-PARENTHESIS ows expression ows RIGHT-PARENTHESIS

ows           = ( WHITESPACE | COMMENT )*
mws           = ( WHITESPACE | COMMENT )+
```

#### Precedence

Operator precedence is encoded structurally: rules that appear *deeper* in the
hierarchy bind tighter. Terminals written in `SCREAMING-KEBAB-CASE` correspond
to tokens produced by the lexer (matching the PascalCase token names in the
lexer definition above).

#### Whitespace

Whitespace is significant only at the `sequence` level, where `mws` between
two `capture` expressions acts as the concatenation ("followed by") operator.
Whitespace around every other construct — operators, `ASSIGNMENT-OPERATOR`,
`SEMICOLON`, braces, parentheses — is purely cosmetic and absorbed by `ows`.

The potential ambiguity (is a space a sequence separator or just formatting
around an operator?) is resolved by operator precedence. After parsing a
`capture`, the parser looks ahead past any whitespace: if the next
non-whitespace token can begin a new `capture` (i.e. a literal, `%`, `{`,
or `(`) then the whitespace is treated as a sequence separator; otherwise it
is discarded as `ows` belonging to the enclosing rule.

Because `as`, `excluding`, `*`, `|`, and `..` all have higher precedence than
the sequence operator, they are consumed before the sequence rule ever sees the
surrounding whitespace. For example, `%Digit * 4` is a single `repetition`,
not a sequence of `%Digit` and `* 4`: the `ows ASTERISK ows` inside `repetition`
absorbs the spaces.

#### Semantic Post-Processing

The following checks and resolutions are performed after parsing. The grammar
is intentionally permissive in these areas; the semantic pass is responsible
for rejecting ill-formed patterns.

**Name resolution**

- **Undefined reference** — `{identifier}` where `identifier` is neither a
  definition nor a capture in scope is an error.
- **Interpolation vs. backreference** — `{identifier}` resolves to a subpattern
  interpolation (pattern match) if `identifier` names a definition, or to a
  backreference (literal match of the previously captured text) if it names a
  capture. Definition names and capture names must be distinct; using the same
  name for both is an error.
- **Duplicate definition names** — two definitions with the same name
  (e.g. `foo = 'a' ; foo = 'b' ;`) are an error.
- **Duplicate capture names** — the same capture name used more than once in a
  pattern (e.g. `%Digit * 4 as year '-' %Digit * 2 as year`) is an error.
- **Circular definitions** — a definition that references itself directly or
  through a cycle (e.g. `foo = {foo} ;`) would produce an infinite pattern and
  is an error.
- **Forward backreferences** — `{identifier}` used as a backreference must
  appear after the `expression as identifier` that establishes it; a
  backreference before its capture is an error.

**Range and repetition**

- **Single-character constraint on `..`** — both sides of a range operator must
  match exactly one character. The constraint cannot be expressed in the grammar
  (e.g. `'ab'..'z'` is syntactically valid), so it is enforced here.
- **Single-character constraint on `excluding`** — both sides must match exactly
  one character.
- **`excluding` subset violation** — the character set of ptern2 must be wholly
  contained in the character set of ptern1; any character matched by ptern2 that
  is not matched by ptern1 is an error.
- **`excluding` empty result** — if ptern2 covers all characters of ptern1 the
  result matches nothing, which is an error.
- **Inverted repetition bounds** — `* m..n` where `m > n` is an error.

**Captures inside repetition**

- **Capture within `* m..n`** — a capture (`expression as identifier`) that
  appears anywhere inside a repeated sub-pattern is an error.

**Annotations**

- **Unknown annotation name** — an unrecognised annotation (e.g. `@typo = true`)
  is an error.
- **Wrong annotation value type** — a value of the wrong type for an annotation
  (e.g. `@case-insensitive = 42`) is an error.
- **Duplicate annotation** — the same annotation set more than once in a ptern
  is an error.

**String literals**

- **Invalid escape sequence** — the lexer stores raw escape sequences; the
  semantic pass rejects unrecognised escapes (e.g. `'\z'`).
- **Invalid Unicode escape** — `\uXXXX` must be a valid Unicode scalar value.


## Examples

*Identifier (max length 32)*

```
(%L|'_') (%L|%N|'_') * 0..31
```

*Date formatted YYYY-MM-DD*

```
%Digit * 4 as year '-' ('0' '1'..'9' | '1' '0'..'2') as month '-' ('0' '1'..'9' | '1'..'2' %Digit | '3' '0'..'1') as day
```

```
yyyy = %Digit * 4;
mm = '0' '1'..'9' | '1' '0'..'2';
dd = '0' '1'..'9' | '1'..'2' %Digit | '3' '0'..'1';
{yyyy} as year '-' {mm} as month '-' {dd} as day
```

*Double-quoted string*

```
'"' ((%Any excluding ('"'|'\n'|'\r')) | '\\"') * 0..1000 '"'
```

*Floating-point number (optional sign, optional fractional part, optional exponent)*

```
@case-insensitive = true
digits = %Digit * 1..20 ;
exp    = 'e' ('+' | '-') * 0..1 {digits} as exponent ;
('+' | '-') * 0..1 {digits} as integer ('.' {digits} as fraction) * 0..1 {exp} * 0..1
```

*Hexadecimal integer (`0x1A2B`, `0X1a2b`, etc.)*

```
@case-insensitive = true
'0x' %Xdigit * 1..16 as value
```

*Semantic version*

```
num = %Digit * 1..10 ;
{num} as major '.' {num} as minor '.' {num} as patch
```

*Hex colour (`#RRGGBB` or `#RGB`)*

```
h = %Xdigit ;
'#' ( {h} * 2 as red {h} * 2 as green {h} * 2 as blue
    | {h} as red {h} as green {h} as blue )
```

*IPv4 address (simplified — does not range-check octets)*

```
octet = %Digit * 1..3 ;
{octet} as a '.' {octet} as b '.' {octet} as c '.' {octet} as d
```

*IPv4 address (strict — octets validated to 0–255)*

```
octet = %Digit
      | '1'..'9' %Digit
      | '1' %Digit %Digit
      | '2' '0'..'4' %Digit
      | '2' '5' '0'..'5' ;
{octet} as a '.' {octet} as b '.' {octet} as c '.' {octet} as d
```

*U.S. phone number (`(555) 123-4567` or `555-123-4567`)*

```
area     = %Digit * 3 ;
exchange = %Digit * 3 ;
line     = %Digit * 4 ;
('+1' ' ') * 0..1
( '(' {area} as area-code ') ' {exchange} as exchange '-' {line} as line
| {area} as area-code '-' {exchange} as exchange '-' {line} as line )
```

*U.S. ZIP code with optional +4 extension*

```
%Digit * 5 ('-' %Digit * 4) * 0..1
```

*Credit card number (groups of four digits separated by spaces)*

```
group = %Digit * 4 ;
{group} ' ' {group} ' ' {group} ' ' {group}
```

## Language Support

Ptern is designed to be language-independent. The pattern language and its grammar are fully defined in this document; each language binding wraps the same compiled core.

### TypeScript / JavaScript

```typescript
import { ptern } from "./index.ts"

const isoDate = ptern`
  yyyy = %Digit * 4;
  mm = ('0' '1'..'9') | ('1' '0'..'2');
  dd = ('0' '1'..'9') | ('1'..'2' %Digit) | ('3' '0'..'1');
  {yyyy} as year '-' {mm} as month '-' {dd} as day
`

isoDate.matchesAllOf("2026-07-04")     // true
isoDate.matchAllOf("2026-07-04")       // { index: 0, length: 10, captures: { year: "2026", month: "07", day: "04" } }
isoDate.maxLength()                    // 10
```

### Gleam

```gleam
import ptern

let assert Ok(iso_date) = ptern.compile("
  yyyy = %Digit * 4;
  mm = ('0' '1'..'9') | ('1' '0'..'2');
  dd = ('0' '1'..'9') | ('1'..'2' %Digit) | ('3' '0'..'1');
  {yyyy} as year '-' {mm} as month '-' {dd} as day
")

ptern.matches_all_of(iso_date, "2026-07-04")   // True
ptern.match_all_of(iso_date, "2026-07-04")     // Some(MatchOccurrence(index: 0, length: 10, captures: ...))
ptern.max_length(iso_date)              // Some(10)
```

*More language bindings are planned.*

## References

[https://www.regular-expressions.info/posixbrackets.html#:~:text=POSIX%20bracket%20expressions%20are%20a,start%20negates%20the%20bracket%20expression](https://www.regular-expressions.info/posixbrackets.html#:~:text=POSIX%20bracket%20expressions%20are%20a,start%20negates%20the%20bracket%20expression).







