# Ptern User Guide

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
| @word-start | Zero-width assertion: matches the position at the start of a word (between a non-word and a word character). | @word-start %Alpha * 1..? |
| @word-end | Zero-width assertion: matches the position at the end of a word (between a word and a non-word character). | %Alpha * 1..? @word-end |
| @line-start | Zero-width assertion: matches the position at the start of a line. Automatically enables multiline mode. | @line-start %Alpha * 1..? |
| @line-end | Zero-width assertion: matches the position at the end of a line. Automatically enables multiline mode. | %Alpha * 1..? @line-end |

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
`!identifier = value` and must appear at the very top of the ptern, before
any subpattern definitions.

| Annotation                        | Values          | Default | Meaning |
|-----------------------------------|-----------------|---------|---------|
| `!case-insensitive`               | `true`, `false` | `false` | When `true`, literal strings and character ranges match both uppercase and lowercase. |
| `!multiline`                      | `true`, `false` | `false` | When `true`, enables multiline mode: `@line-start` matches the start of each line and `@line-end` matches the end of each line rather than the start/end of the whole string. Using `@line-start` or `@line-end` anywhere in a pattern also enables this automatically. |
| `!replacements-preserve-matching` | `true`, `false` | `false` | When `true`, each value supplied to a `replace*` call is validated against the capture's own subpattern before substitution. Throws `ReplacementError` if the value would not match. |


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
Bang                  =  '!' ;
PositionAssertion     =  '@' %Alpha (%Alnum | '-') * 0..63 ;
AtSign                =  '@' ;
QuestionMark          =  '?' ;
Identifier            =  %Alpha (%Alnum | '-') * 0..63 ;

Whitespace
| Comment
| AsKeyword
| Bang
| PositionAssertion
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

- **Unknown annotation name** — an unrecognised annotation (e.g. `!typo = true`)
  is an error.
- **Wrong annotation value type** — a value of the wrong type for an annotation
  (e.g. `!case-insensitive = 42`) is an error.
- **Duplicate annotation** — the same annotation set more than once in a ptern
  is an error.

**String literals**

- **Invalid escape sequence** — the lexer stores raw escape sequences; the
  semantic pass rejects unrecognised escapes (e.g. `'\z'`).
- **Invalid Unicode escape** — `\uXXXX` must be a valid Unicode scalar value.


## Examples

### ISO date YYYY-MM-DD

#### Ptern

```
yyyy = %Digit * 4;
mm = '0' '1'..'9' | '1' '0'..'2';
dd = '0' '1'..'9' | '1'..'2' %Digit | '3' '0'..'1';
{yyyy} as year '-' {mm} as month '-' {dd} as day
```

#### Equivalent Regex

`^\d{4}-\d{2}-\d{2}$`

### US date MM/DD/YYYY

#### Ptern

```
mm = '0' '1'..'9' | '1' '0'..'2';
dd = '0' '1'..'9' | '1'..'2' %Digit | '3' '0'..'1';
{mm} '/' {dd} '/' %Digit * 4
```

#### Equivalent Regex

`^(0[1-9]|1[0-2])/(0[1-9]|[12]\d|3[01])/\d{4}$`

### 24-hour time HH:MM[:SS]

#### Ptern

```
hr = '0'..'1' %Digit | '2' '0'..'3';
ms = '0'..'5' %Digit;
{hr} ':' {ms} (':' {ms}) * 0..1
```

#### Equivalent Regex

`^([01]\d|2[0-3]):[0-5]\d(:[0-5]\d)?$`

### 12-hour time with AM/PM

#### Ptern

```
hr  = '1' '0'..'2' | ('0') * 0..1 '1'..'9';
ms  = '0'..'5' %Digit;
{hr} ':' {ms} %Space * 0..1 ('A' | 'P') 'M'
```

#### Equivalent Regex

`^(1[0-2]|0?[1-9]):[0-5]\d\s?[AP]M$`

### Floating-point number

#### Ptern

```
!case-insensitive = true
digits = %Digit * 1..20;
exp    = 'e' ('+' | '-') * 0..1 {digits} as exponent;
('+' | '-') * 0..1 {digits} as integer ('.' {digits}) * 0..1 {exp} * 0..1
```

#### Equivalent Regex

`^[+-]?\d+(\.\d+)?([eE][+-]?\d+)?$`

### Decimal, up to 2 places

#### Ptern

```
%Digit * 1..? ('.' %Digit * 1..2) * 0..1
```

#### Equivalent Regex

`^\d+(\.\d{1,2})?$`

### Hexadecimal integer literal

#### Ptern

```
!case-insensitive = true
'0x' %Xdigit * 1..16 as value
```

#### Equivalent Regex

`^0x[0-9a-fA-F]+$`

### Octal integer literal

#### Ptern

```
'0' '0'..'7' * 1..?
```

#### Equivalent Regex

`^0[0-7]+$`

### Binary integer literal

#### Ptern

```
'0b' ('0' | '1') * 1..?
```

#### Equivalent Regex

`^0b[01]+$`

### Semantic version

#### Ptern

```
num = %Digit * 1..10;
{num} as major '.' {num} as minor '.' {num} as patch
```

#### Equivalent Regex

`^\d+\.\d+\.\d+$`

### Unicode identifier, max 32 chars

#### Ptern

```
(%L | '_') (%L | %N | '_') * 0..31
```

#### Equivalent Regex

`^[_\p{L}][_\p{L}\p{N}]{0,31}$`

### ASCII identifier

#### Ptern

```
%Alpha (%Alnum | '_') * 0..?
```

#### Equivalent Regex

`^[a-zA-Z][a-zA-Z0-9_]*$`

### Username, 3–20 chars

#### Ptern

```
%Lower (%Lower | %Digit | '_' | '-') * 2..19
```

#### Equivalent Regex

`^[a-z][a-z0-9_-]{2,19}$`

### PascalCase identifier

#### Ptern

```
%Upper %Lower * 1..? (%Upper %Lower * 1..?) * 0..?
```

#### Equivalent Regex

`^[A-Z][a-z]+([A-Z][a-z]+)*$`

### camelCase identifier

#### Ptern

```
%Lower * 1..? (%Upper %Lower * 1..?) * 0..?
```

#### Equivalent Regex

`^[a-z]+([A-Z][a-z]+)*$`

### snake_case identifier

#### Ptern

```
%Lower * 1..? ('_' %Lower * 1..?) * 0..?
```

#### Equivalent Regex

`^[a-z]+(_[a-z]+)*$`

### Double-quoted string literal

Allows embedded newlines. Use `%Any excluding '\n'` inside the character class if you want to forbid them.

#### Ptern

```
char = %Any excluding '"';
'"' ({char} | '\\"') * 0..1000 '"'
```

#### Equivalent Regex

`^"([^"\n\r]|\\")*"$`

### Boolean keyword

#### Ptern

```
'true' | 'false'
```

#### Equivalent Regex

`^(true|false)$`

### Null-like keyword

#### Ptern

```
'null' | 'undefined' | 'nil' | 'None'
```

#### Equivalent Regex

`^(null|undefined|nil|None)$`

### Email address

#### Ptern

```
lc = %Alnum | '.' | '_' | '%' | '+' | '-';
dc = %Alnum | '.' | '-';
{lc} * 1..? '@' {dc} * 1..? '.' %Alpha * 2..?
```

#### Equivalent Regex

`^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$`

### HTTP/HTTPS URL

Simplified — multi-character negated classes are not expressible in Ptern.

#### Ptern

```
'http' ('s') * 0..1 '://' (%Any excluding %Space) * 1..?
```

#### Equivalent Regex

`^https?://[^\s]+$`

### IPv4 address (octets not range-checked)

#### Ptern

```
oct = %Digit * 1..3;
({oct} '.') * 3 {oct}
```

#### Equivalent Regex

`^(\d{1,3}\.){3}\d{1,3}$`

### IPv4 address (strictly 0–255)

#### Ptern

```
octet = %Digit
      | '1'..'9' %Digit
      | '1' %Digit %Digit
      | '2' '0'..'4' %Digit
      | '2' '5' '0'..'5';
{octet} as a '.' {octet} as b '.' {octet} as c '.' {octet} as d
```

#### Equivalent Regex

No concise regex equivalent.

### E.164 international phone

#### Ptern

```
('+') * 0..1 '1'..'9' %Digit * 1..14
```

#### Equivalent Regex

`^\+?[1-9]\d{1,14}$`

### US phone number

Matches both `(555) 123-4567` and `555-123-4567`, with optional `+1` prefix.

#### Ptern

```
area     = %Digit * 3;
exchange = %Digit * 3;
line     = %Digit * 4;
('+1 ') * 0..1
( '(' {area} as area-code ') ' {exchange} as exchange '-' {line} as line
| {area} as area-code '-' {exchange} as exchange '-' {line} as line )
```

#### Equivalent Regex

No concise regex equivalent.

### US ZIP code (optional +4)

#### Ptern

```
%Digit * 5 ('-' %Digit * 4) * 0..1
```

#### Equivalent Regex

`^\d{5}(-\d{4})?$`

### UK postcode

#### Ptern

```
%Upper * 1..2 %Digit (%Upper | %Digit) * 0..1 %Space * 0..1 %Digit %Upper * 2
```

#### Equivalent Regex

`^[A-Z]{1,2}\d[A-Z\d]?\s?\d[A-Z]{2}$`

### UUID / GUID

#### Ptern

```
%Xdigit * 8 '-' (%Xdigit * 4 '-') * 3 %Xdigit * 12
```

#### Equivalent Regex

`^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$`

### US Social Security Number

#### Ptern

```
%Digit * 3 '-' %Digit * 2 '-' %Digit * 4
```

#### Equivalent Regex

`^\d{3}-\d{2}-\d{4}$`

### Visa card number

#### Ptern

```
'4' %Digit * 12 (%Digit * 3) * 0..1
```

#### Equivalent Regex

`^4[0-9]{12}(?:[0-9]{3})?$`

### Mastercard number

#### Ptern

```
'5' '1'..'5' %Digit * 14
```

#### Equivalent Regex

`^5[1-5][0-9]{14}$`

### Credit card — four groups of four digits

#### Ptern

```
group = %Digit * 4;
{group} ' ' {group} ' ' {group} ' ' {group}
```

#### Equivalent Regex

`^\d{4}( \d{4}){3}$`

### SHA-1 hex hash

#### Ptern

```
%Xdigit * 40
```

#### Equivalent Regex

`^[a-fA-F0-9]{40}$`

### SHA-256 hex hash

#### Ptern

```
%Xdigit * 64
```

#### Equivalent Regex

`^[a-fA-F0-9]{64}$`

### Password with complexity requirements

#### Ptern

Not expressible — simultaneous requirements (at least one lowercase, one uppercase, one digit) need lookaheads, which Ptern does not support. Use three separate pterns tested independently.

#### Equivalent Regex

`^(?=.*[a-z])(?=.*[A-Z])(?=.*\d).{8,}$`

### CSS hex color (#RGB or #RRGGBB)

#### Ptern

```
'#' (%Xdigit * 6 | %Xdigit * 3)
```

#### Equivalent Regex

`^#([a-fA-F0-9]{6}|[a-fA-F0-9]{3})$`

### CSS rgb() color

#### Ptern

```
'rgb(' %Space * 0..? %Digit * 1..3
  ',' %Space * 0..? %Digit * 1..3
  ',' %Space * 0..? %Digit * 1..3
%Space * 0..? ')'
```

#### Equivalent Regex

`^rgb\(\s*(\d{1,3}),\s*(\d{1,3}),\s*(\d{1,3})\s*\)$`

### CSS length value

#### Ptern

```
%Digit * 1..? ('.' %Digit * 1..?) * 0..1 ('px' | 'em' | 'rem' | '%' | 'vh' | 'vw')
```

#### Equivalent Regex

`^\d+(\.\d+)?(px|em|rem|%|vh|vw)$`

### C-style block comment

Ptern uses greedy matching; for `matchesAllOf` this is equivalent to non-greedy.

#### Ptern

```
'/*' %Any * 0..? '*/'
```

#### Equivalent Regex

`^/\*[\s\S]*?\*/$`

### C-style line comment

#### Ptern

```
'//' (%Any excluding '\n') * 0..?
```

#### Equivalent Regex

`^//.*$`

### HTML comment

Ptern uses greedy matching; for `matchesAllOf` this is equivalent to non-greedy.

#### Ptern

```
'<!--' %Any * 0..? '-->'
```

#### Equivalent Regex

`^<!--[\s\S]*?-->$`

### HTML tag with matching close tag

#### Ptern

Not expressible — matching open and close tag names requires a backreference, which Ptern does not support.

#### Equivalent Regex

`<([a-zA-Z][a-zA-Z0-9]*)\b[^>]*>(.*?)<\/\1>`

### Blank or whitespace-only line

#### Ptern

```
%Space * 0..?
```

#### Equivalent Regex

`^\s*$`

### Duplicate word in string

#### Ptern

Not expressible — detecting a repeated earlier match requires a lookahead and a backreference, which Ptern does not support.

#### Equivalent Regex

`\b\w+\b(?=.*\b\1\b)`


## References

[https://www.regular-expressions.info/posixbrackets.html#:~:text=POSIX%20bracket%20expressions%20are%20a,start%20negates%20the%20bracket%20expression](https://www.regular-expressions.info/posixbrackets.html#:~:text=POSIX%20bracket%20expressions%20are%20a,start%20negates%20the%20bracket%20expression).







