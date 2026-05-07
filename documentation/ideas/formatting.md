# Ptern Source Formatting Specification

**Version:** 0.2 (Draft)  
**Date:** 2026-05-07

---

## 1. Introduction

This document specifies the `format` operation, which accepts a Ptern source string and returns a canonically formatted version of that source. The formatted output is syntactically and semantically equivalent to the input: it produces the same compiled pattern and captures the same language. Doc comments are preserved.

The formatter operates on the parse tree produced by the Ptern lexer and parser. It does not require a semantically valid ptern; semantic errors (undefined references, circular definitions, etc.) do not prevent formatting. Only lex and parse errors cause `format` to fail.

---

## 2. Public API

### 2.1 Types

```gleam
pub type FormatOptions {
  FormatOptions(
    line_width: Int,
    compact: Bool,
    aligned: Bool,
    reordered: Bool,
  )
}

pub fn default_format_options() -> FormatOptions {
  FormatOptions(line_width: 80, compact: False, aligned: True, reordered: False)
}

pub type FormatError {
  FormatLexError(LexError)
  FormatParseError(ParseError)
  InvalidLineWidth
}

pub fn format(source: String, options: FormatOptions) -> Result(String, FormatError)
```

### 2.2 Options

| Option | Type | Default | Constraint | Description |
|--------|------|---------|------------|-------------|
| `line_width` | `Int` | `80` | `>= 40` | Target maximum column width. Lines may exceed this width when no valid break point exists within the limit. |
| `compact` | `Bool` | `False` | — | When `True`, omit optional whitespace around operators and suppress blank separator lines between sections and between commented items within a block. |
| `aligned` | `Bool` | `True` | — | When `True`, vertically align `=` signs within the annotation block and within the definition block independently. `compact` does not override this option. |
| `reordered` | `Bool` | `False` | — | When `True`, sort definitions into topological layers (dependencies before dependents) and then alphabetically within each layer. See §5.1. |

If `line_width < 40`, `format` returns `Error(InvalidLineWidth)` without further processing.

---

## 3. Error Handling

`format` first lexes and parses the source string. If lexing or parsing fails, `format` returns the corresponding `FormatLexError` or `FormatParseError` and produces no output. Semantic errors discovered by the validator or resolver (§7 of the language specification) do not cause `format` to fail; the formatter operates solely on the parse tree.

---

## 4. Doc Comments

Doc comments are stored in the parse tree (`ptern_comments`, `body_comments`, `Annotation.comments`, `Definition.comments`) and are reproduced in the formatted output. Comment content is preserved verbatim — no normalization, trimming, or line-wrapping is applied to the text following `#`.

Each comment line is emitted as `#` followed by the stored content string. No trailing whitespace is emitted on comment lines.

### 4.1 Ptern-Level Comment Block

If `ptern_comments` is non-empty, the ptern-level comment block is emitted first, before all other output. Each string in the list occupies one line (`#` + content). The block is followed by exactly one blank line regardless of the `compact` setting — this blank line is syntactically required to preserve the ptern-level vs. item-level distinction on re-parse.

### 4.2 Item-Level Comments

Each `Annotation`, `Definition`, and the body expression may carry a comment block. When present, item-level comments are emitted immediately above the item they document, with no blank line between the last comment line and the item.

Within the annotation block and within the definition block, a blank line is inserted before an item's comment block whenever a prior item has already been emitted in that same block and `compact = False`. This blank line visually attaches the comment to its item and separates it from the item above. When `compact = True`, no blank lines are inserted within annotation or definition blocks.

---

## 5. Overall Structure

The formatted output consists of the following sections in order, with no leading or trailing blank lines in the output as a whole:

1. **Ptern-level comment block** — if `ptern_comments` is non-empty, as described in §4.1, including its mandatory trailing blank line.
2. **Annotation block** — zero or more annotations, each optionally preceded by item-level comments (§4.2), sorted lexicographically by annotation name.
3. **Blank separator** — exactly one blank line, present if and only if the annotation block is non-empty, at least one subsequent section is non-empty, and `compact = False`.
4. **Definition block** — zero or more definitions, each optionally preceded by item-level comments (§4.2), ordered as specified in §5.1.
5. **Blank separator** — exactly one blank line, present if and only if the definition block is non-empty, the body expression section is non-empty, and `compact = False`.
6. **Body comment block** — if `body_comments` is non-empty, the comment lines emitted directly above the body expression with no blank line between the last comment and the body.
7. **Body expression** — the body expression, which occupies one or more lines.

### 5.1 Definition Ordering

When `reordered = False` (the default), definitions are emitted in the order they appear in the source.

When `reordered = True`, definitions are sorted as follows:

1. **Build the dependency graph.** For each definition *D*, its direct dependencies are the set of identifiers referenced via `{ identifier }` interpolations in its body, restricted to identifiers that are themselves defined as definitions in the same ptern.

2. **Assign layers.** Each definition is assigned a non-negative integer layer number:
   - A definition with no dependencies is in layer 0.
   - A definition whose direct dependencies are all in layers 0..*k*−1 is in layer *k*.
   - Equivalently: layer(*D*) = 0 if *D* has no dependencies; otherwise layer(*D*) = 1 + max(layer(*dep*)) over all direct dependencies of *D*.

3. **Handle cycles.** If the dependency graph contains a cycle, the definitions involved in that cycle cannot be assigned a layer by the above rule. Such definitions are collected and placed after all successfully layered definitions, in their original source order relative to one another. (Cyclic definitions constitute a semantic error that the validator will report; the formatter emits them without reordering to preserve the source faithfully.)

4. **Emit.** Emit definitions in ascending layer order. Within each layer, sort definitions alphabetically by identifier name (Unicode code-point order, i.e., lexicographic on UTF-16 code units, consistent with the JavaScript `<` operator on strings).

---

## 6. Whitespace Rules

### 6.1 General Rules

1. Tab characters (`U+0009`) are not produced in the formatted output.
2. Trailing whitespace is not produced on any output line.
3. Multiple consecutive space characters are reduced to a single space, except for alignment padding (§6.3) and continuation indentation (§8.2, §8.3).

### 6.2 Operator Spacing

The following table specifies the number of space characters placed immediately before and after each token. "Before" means between the preceding token and this one; "after" means between this token and the following token.

| Context | `compact = False` | `compact = True` |
|---------|-------------------|------------------|
| Before and after `..` | 0 | 0 |
| Before and after `*` | 1 | 0 |
| Before and after `\|` | 1 | 0 |
| After `(` | 1 | 0 |
| Before `)` | 1 | 0 |
| Before and after any keyword (`as`, `excluding`) | 1 | 1 |

The `compact` option does not affect spacing around `=`; only the `aligned` option governs that (§6.3).

### 6.3 Alignment of `=`

The `=` token appears in annotations (e.g., `!case-insensitive = true`) and in subpattern definitions (e.g., `word = %Alpha * 1..? ;`).

| Context | `aligned = False` | `aligned = True` |
|---------|-------------------|------------------|
| Before `=` | 1 space | Padded to column *C* (see below) |
| After `=` | 1 space | 1 space |

When `aligned = True`, the alignment column *C* is computed separately for the annotation block and for the definition block:

> *C* = (length of the longest name in the block) + 2

where "name" is the annotation name (the part after `!`) or the definition identifier, and the +2 accounts for the `!` or bare identifier character sequence plus one mandatory trailing space. Every `=` in the block is then placed at column *C*.

Alignment padding applies only to the first line of a definition. Continuation lines of wrapped definitions (§8.2) use continuation indentation instead and do not affect or participate in alignment.

---

## 7. Token Representation

### 7.1 String Literals

String literals are normalized to single-quote delimiters (`'...'`) regardless of the delimiter used in the source. If the literal content contains one or more single-quote characters (`U+0027`), double-quote delimiters (`"..."`) are used instead, since switching to single quotes would require adding escape sequences. No other normalization of literal content is performed.

### 7.2 Character Classes

Character class names are reproduced in the canonical title case defined in §5 of the language specification (e.g., `%Alpha`, `%Digit`, `%Any`).

### 7.3 Annotations

Annotations are reproduced in the form `!name` or `!name = value` as appropriate, using exactly one space before and after `=` when a value is present (subject to §6.3).

---

## 8. Line Breaking

### 8.1 Definitions of Terms

**Mandatory whitespace position**: A position in the token sequence where a space character is emitted in the formatted output because the grammar requires separation between two tokens (i.e., sequence-separating space, and spaces around operators specified in §6.2 with a non-zero count). Positions that emit zero spaces (e.g., before/after `..`) are not mandatory whitespace positions.

**Line length**: The number of characters on a line, not counting the line terminator.

**Break point**: A mandatory whitespace position at which a line break may be inserted. A line break at a break point replaces the space character(s) at that position with a newline.

### 8.2 Definition Lines

Each definition is initially formatted as a single line: `name = body ;` (with spacing per §6.2–§6.3). The following rules are applied in order to bring the line within `line_width`.

**Rule D1 — Break after `=`:** If the line length exceeds `line_width` and the length of the body text (the content after `= ` up to and including ` ;`) is at most `line_width − 4`, insert a line break after `=` and indent the body by 4 spaces. The closing `;` appears on the same line as the body text.

**Rule D2 — Break at rightmost sequence position:** If the line (or the body line after D1) still exceeds `line_width`, find the rightmost mandatory whitespace position that is a sequence-separating space and falls within the first `line_width + 1` characters of the line. Insert a line break at that position. Indent the continuation line to align with the first non-space character of the body on the line above (i.e., the character immediately following `= ` on the first line of the definition, or the indentation established by a previous break).

Rule D2 may be applied repeatedly: after each break, the new continuation line is tested against `line_width` and broken again if necessary, using the same continuation indentation column.

**Rule D3 — Break before alternation `|`:** If the line still exceeds `line_width` after D2 and the body is an alternation, find the rightmost `|` that (a) belongs to the outermost alternation level and (b) falls within the first `line_width + 1` characters of the line. Insert a line break immediately before that `|`. Indent the continuation line so that the `|` aligns with the `(` or `|` that opens the enclosing alternation on the preceding line.

**Rule D4 — No break available:** If none of D1–D3 produces a line within `line_width`, the line is emitted at its natural length without further modification.

### 8.3 Body Expression Lines

The body expression is formatted as a single line and then broken using the following rules, applied in order.

**Rule B1 — Break at rightmost sequence position:** If the line exceeds `line_width`, find the rightmost mandatory whitespace position that is a sequence-separating space and falls within the first `line_width + 1` characters of the line. Insert a line break at that position. Continuation lines are not indented (column 0).

Rule B1 may be applied repeatedly to continuation lines under the same conditions.

**Rule B2 — Break before alternation `|`:** If the line still exceeds `line_width` and the body is an alternation, find the rightmost `|` that (a) belongs to the outermost alternation level and (b) falls within the first `line_width + 1` characters of the line. Insert a line break immediately before that `|`. Continuation lines are not indented (column 0).

**Rule B3 — No break available:** If neither B1 nor B2 produces a line within `line_width`, the line is emitted at its natural length without further modification.

### 8.4 Annotations

Annotations are never broken across lines. An annotation that exceeds `line_width` is emitted on a single line. Because the minimum valid `line_width` is 40 (§2.2) and annotation lines cannot exceed the length of a valid annotation token, this condition is not expected to arise in practice.

### 8.5 Comment Lines

Comment lines are never broken across lines. The text following `#` is emitted verbatim on a single line regardless of `line_width`.

---

## 9. Open Questions

The following questions are not resolved by this version of the specification and must be addressed before implementation:

1. **Annotation reordering and comment attachment** — annotations are sorted lexicographically by name (§5). When annotations are reordered, their attached item-level comments move with them. This is the expected behaviour, but it means the output comment order may differ from the source comment order. No action is required — this is stated here for clarity.
