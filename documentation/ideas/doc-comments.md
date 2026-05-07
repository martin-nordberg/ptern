# Doc Comments — Design & Implementation Plan

## Overview

Comments in Ptern become "doc comments": structured, whole-line annotations that
attach to a specific top-level element (annotation, definition, or body) or to
the ptern as a whole. They are no longer silently discarded — they become part
of the AST, which is necessary for a lossless formatter.

---

## Resolved Design Decisions

### Placement rules (new)

1. A comment line must occupy a full line. The `#` must be the first non-whitespace
   character on its line. An inline `#` (after code on the same line) is a lex error.

2. Comments may appear in two positions only:
   - **Ptern-level block**: a group of consecutive comment lines at the very top of
     the source, separated from the rest of the file by at least one blank line.
   - **Item-level block**: a group of consecutive comment lines immediately above a
     single annotation, definition, or the body expression, with no blank line
     between the last comment line and the item.

3. No blank line is allowed between an item-level comment block and the item it
   documents. A blank line breaks the association and makes the comments orphaned
   (→ `ParseError`).

4. Comments are not permitted after the body expression.

### Blank-line semantics

A "blank line" is a line that contains only whitespace (spaces/tabs and then a
newline). The lexer detects this during whitespace collapsing and emits
`Whitespace(has_blank_line: Bool)` so the parser can distinguish the two
comment positions without reparsing raw source.

---

## Implementation Plan

### Step 1 — Lexer changes

**1a. Track `at_line_start` state.**

Add a `Bool` argument to `do_lex` / `lex_whitespace` indicating whether the
lexer is currently at the start of a line. It starts `True`, flips to `False`
the moment any non-whitespace character is consumed, and resets to `True` when
a `\n` or `\r` is consumed.

When `#` is encountered:
- `at_line_start == True`  → lex the comment normally (emit `Comment(content)`)
- `at_line_start == False` → `Error(InlineComment)`

**1b. Change `Whitespace` to carry a blank-line flag.**

Rename the current `Whitespace` token constructor to `Whitespace(has_blank_line: Bool)`.

During `lex_whitespace`, set `has_blank_line = True` if a second `\n` is seen
after the first (i.e. at least one `\n` followed by optional spaces/tabs and
then another `\n`). A single `\n` (or spaces only) gives `has_blank_line = False`.

No other token types change.

**New `LexError` variant:**
```gleam
InlineComment  // '#' appeared after non-whitespace on the same line
```

### Step 2 — Token / Stream layer: rename and split `skip_trivia`

`skip_trivia` is a misleading name now that comments are structural. Replace the
single function with two:

- **`skip_whitespace(stream) -> Stream`** — drops only `Whitespace(_)` tokens.
  Used everywhere inside constructs (annotation body, definition body, repetition,
  exclusion, group, etc.) — i.e. all existing `skip_trivia` call-sites _except_
  the top-level collectors.
- **`skip_blank_lines(stream) -> Stream`** — drops `Whitespace(has_blank_line: True)`
  tokens only. Used by the top-level comment collector to advance past the
  separator blank line after the ptern-level comment block.

Update all ~15 `skip_trivia` call-sites in `parser.gleam` to `skip_whitespace`.
Update `stream.gleam` to remove the old `skip_trivia`, add the two new functions,
and remove `Comment` from `peek_after_trivia` (it is no longer trivia).

Also update `peek` (the non-trivia peek) to skip only `Whitespace`, not `Comment`.

### Step 3 — AST changes

**`token.gleam`** — `Whitespace` becomes `Whitespace(has_blank_line: Bool)`.

**`ast.gleam`** — three structural changes:

```gleam
pub type ParsedPtern {
  ParsedPtern(
    ptern_comments: List(String),      // top-of-file block (may be empty)
    annotations: List(Annotation),
    definitions: List(Definition),
    body_comments: List(String),       // immediately above the body (may be empty)
    body: Expression,
  )
}

pub type Annotation {
  Annotation(comments: List(String), name: String, value: Bool)
}

pub type Definition {
  Definition(comments: List(String), name: String, body: Expression)
}
```

Comment strings are the raw content after `# ` (or `#` with no space), as
produced by the existing lexer. The `# ` prefix itself is not stored.

### Step 4 — Parser changes

**`parse_ptern`** becomes:

```
1. Collect leading comments (a run of Comment tokens with only
   non-blank-line Whitespace between them).
2. If the next whitespace token has `has_blank_line = True`:
      → these are ptern_comments; advance past the blank line.
   Else if next token is Bang / Identifier / starts-body:
      → these comments belong to the first item (carry forward).
   Else if stream is empty after comments:
      → orphaned comments → ParseError(OrphanedComment).
3. parse_annotations  (each call to parse_annotation collects its own
   leading comment block first; blank line before item → ParseError)
4. parse_definitions  (same pattern)
5. collect body_comments  (same single-block collection, no blank line allowed)
6. parse_expression
7. Verify stream is empty; any remaining Comment → ParseError(TrailingComment).
```

Add a helper `collect_item_comments(s) -> Result(#(List(String), Stream), ParseError)`:
- Collects consecutive `Comment` tokens separated only by `Whitespace(has_blank_line: False)`.
- Stops at `Whitespace(has_blank_line: True)`, a non-comment / non-whitespace token,
  or end of input.

**New `ParseError` variants:**
```gleam
OrphanedComment   // comment block not immediately followed by an item
TrailingComment   // comment appears after the body expression
```

The existing `looks_like_definition` lookahead and `drop_trivia_tokens` helper
are updated to not drop `Comment` tokens (they're no longer trivia at that level).

### Step 5 — Downstream pass updates

All passes that pattern-match on `ParsedPtern`, `Annotation`, or `Definition`
must be updated to handle the new fields. The new fields are purely additive
for `validator`, `resolver`, `codegen`, `bounds` — they can ignore the comment
strings. Update each constructor pattern match to include `comments: _` /
`ptern_comments: _` / `body_comments: _`.

Affected files: `semantic/validator.gleam`, `semantic/resolver.gleam`,
`semantic/bounds.gleam`, `codegen/codegen.gleam`, `codegen/substitution.gleam`.

### Step 6 — Tests

**Lexer tests (`test/lexer/lexer_test.gleam`):**
- Update `Whitespace` literal uses to `Whitespace(False)` / `Whitespace(True)`.
- Update `lex_comment_test` to confirm the token is unchanged.
- Add: inline `#` → `Error(InlineComment)`.
- Add: blank line produces `Whitespace(True)`.

**Parser tests (`test/parser/parser_test.gleam`):**
- Update `parse_comment_is_ignored_test` — comments are no longer ignored;
  update expected AST to carry comment strings.
- Add: ptern-level comment block (blank line after → `ptern_comments`).
- Add: item-level comment attaches to annotation / definition / body.
- Add: blank line between comment and item → `OrphanedComment` error.
- Add: comment after body → `TrailingComment` error.
- Add: inline `#` → lex error propagates through `parse`.

### Step 7 — Spec update (`documentation/ptern-specification.md`)

- **§2.1 Structure of a Ptern**: Replace "Whitespace and comments may appear
  freely between all elements" with a description of the two permitted comment
  positions and the blank-line rule.
- **§3.1 Whitespace and Comments**: Replace the current grammar rule with the
  doc-comment grammar; add the inline-comment prohibition; document the
  blank-line token behaviour.
- Add a new **§3.x Doc Comments** section covering:
  - Ptern-level block (top of file, followed by blank line).
  - Item-level block (immediately above annotation / definition / body, no
    blank line).
  - Both positions produce AST nodes rather than being discarded.

### Step 8 — User guide update (`ptern-gleam/doc/user-guide.md`)

Add a **Comments** section (after the introduction, before or within the
"Writing Pterns" section) covering:

- Basic syntax: `# text` on its own line.
- Inline comments are not allowed.
- **Ptern-level doc comment**: a block at the top of the source, separated
  from the first annotation / definition / body by a blank line. Documents
  the pattern as a whole. Example:

  ```ptern
  # Matches an ISO 8601 date in YYYY-MM-DD format.
  # The year must be four digits; month and day are zero-padded.

  !substitutable = true
  year  = %Digit * 4 ;
  month = %Digit * 2 ;
  day   = %Digit * 2 ;
  {year} '-' {month} '-' {day}
  ```

- **Item-level doc comment**: a block immediately above an annotation,
  definition, or the body expression (no blank line between comment and item).
  Example:

  ```ptern
  # When true, the year/month/day captures can be used with substitute().
  !substitutable = true

  # The four-digit calendar year.
  year = %Digit * 4 ;

  # Compose a date string from captured year, month, and day values.
  {year} '-' {month} '-' {day}
  ```

- Blank line between a comment block and its item is an error.
- Comments after the body expression are not permitted.

---

## Implementation Notes

**`OrphanedComment` scope**: A comment block at the very top of the file that is
followed by a blank line is always treated as the ptern-level comment, not an
orphaned comment. `OrphanedComment` can only fire after at least one item
(annotation or definition) has already been parsed, i.e. for comment blocks that
appear between items.

**Gleam guard limitation**: Gleam does not allow function calls in `case` guards.
All `!list.is_empty(x)` checks were replaced with nested `case list.is_empty(x)`
expressions in `parser.gleam`.
