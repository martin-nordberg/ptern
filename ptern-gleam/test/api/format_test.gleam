import formatter/formatter.{
  type FormatOptions,
  FormatOptions,
  InvalidLineWidth,
  default_format_options,
}
import gleam/string
import gleeunit/should

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn fmt(source: String) -> String {
  let assert Ok(result) = formatter.format(source, default_format_options())
  result
}

fn fmt_opts(source: String, opts: FormatOptions) -> String {
  let assert Ok(result) = formatter.format(source, opts)
  result
}

fn opts(
  line_width line_width: Int,
  compact compact: Bool,
  aligned aligned: Bool,
  reordered reordered: Bool,
) -> FormatOptions {
  FormatOptions(
    line_width: line_width,
    compact: compact,
    aligned: aligned,
    reordered: reordered,
  )
}

// ---------------------------------------------------------------------------
// Error cases
// ---------------------------------------------------------------------------

pub fn invalid_line_width_test() {
  formatter.format(
    "'x'",
    opts(line_width: 39, compact: False, aligned: True, reordered: False),
  )
  |> should.equal(Error(InvalidLineWidth))
}

pub fn invalid_line_width_exactly_40_ok_test() {
  formatter.format(
    "'x'",
    opts(line_width: 40, compact: False, aligned: True, reordered: False),
  )
  |> should.be_ok
}

pub fn lex_error_propagated_test() {
  formatter.format("'unterminated", default_format_options())
  |> should.be_error
}

pub fn parse_error_propagated_test() {
  formatter.format("* 3", default_format_options())
  |> should.be_error
}

// ---------------------------------------------------------------------------
// Token normalisation
// ---------------------------------------------------------------------------

pub fn literal_single_quote_test() {
  fmt("\"hello\"") |> should.equal("'hello'")
}

pub fn literal_double_quote_preserved_when_contains_single_test() {
  fmt("\"it's\"") |> should.equal("\"it's\"")
}

pub fn char_class_preserved_test() {
  fmt("%Alpha") |> should.equal("%Alpha")
}

pub fn interpolation_braces_normalised_test() {
  // {word} with no surrounding whitespace
  fmt("{ word }") |> should.equal("{word}")
}

pub fn position_assertion_test() {
  fmt("@word-start %Alpha * 1..? @word-end")
  |> should.equal("@word-start %Alpha * 1..? @word-end")
}

// ---------------------------------------------------------------------------
// Body expression — basic normalisation
// ---------------------------------------------------------------------------

pub fn sequence_test() {
  fmt("'a' 'b' 'c'") |> should.equal("'a' 'b' 'c'")
}

pub fn alternation_spacing_test() {
  fmt("'a'|'b'|'c'") |> should.equal("'a' | 'b' | 'c'")
}

pub fn repetition_exact_test() {
  fmt("%Digit*4") |> should.equal("%Digit * 4")
}

pub fn repetition_range_test() {
  fmt("%Alpha*1..?") |> should.equal("%Alpha * 1..?")
}

pub fn repetition_bounded_test() {
  fmt("%Digit*3..10") |> should.equal("%Digit * 3..10")
}

pub fn repetition_lazy_test() {
  fmt("%Digit*1..? fewest") |> should.equal("%Digit * 1..? fewest")
}

pub fn capture_test() {
  fmt("%Digit*4 as year") |> should.equal("%Digit * 4 as year")
}

pub fn exclusion_test() {
  fmt("%Alpha excluding 'q'") |> should.equal("%Alpha excluding 'q'")
}

pub fn char_range_test() {
  fmt("'a'..'z'") |> should.equal("'a'..'z'")
}

pub fn group_non_compact_test() {
  fmt("('a'|'b')") |> should.equal("( 'a' | 'b' )")
}

// ---------------------------------------------------------------------------
// Annotations
// ---------------------------------------------------------------------------

pub fn annotation_true_test() {
  // Single annotation: "multiline" = 9 chars, col = 11
  // "!multiline" = 10 chars → 1 space before =
  fmt("!multiline = true\n'x'")
  |> should.equal("!multiline = true\n\n'x'")
}

pub fn annotation_false_test() {
  fmt("!multiline = false\n'x'")
  |> should.equal("!multiline = false\n\n'x'")
}

pub fn annotations_sorted_test() {
  // Sorted: case-insensitive (16 chars) before multiline (9 chars)
  // col = 16 + 2 = 18
  // "!case-insensitive" = 17 chars → 1 space before =
  // "!multiline" = 10 chars → 8 spaces before =
  fmt("!multiline = true\n!case-insensitive = true\n'x'")
  |> should.equal(
    "!case-insensitive = true\n!multiline        = true\n\n'x'",
  )
}

pub fn annotation_two_aligned_test() {
  // "substitutable" = 13 chars, "multiline" = 9 chars, max = 13, col = 15
  // "!substitutable" = 14 chars → 15 - 14 = 1 space before =
  // "!multiline" = 10 chars → 15 - 10 = 5 spaces before =
  fmt("!substitutable = true\n!multiline = true\n'x'")
  |> should.equal("!multiline     = true\n!substitutable = true\n\n'x'")
}

pub fn annotation_not_aligned_test() {
  fmt_opts(
    "!substitutable = true\n!multiline = true\n'x'",
    opts(line_width: 80, compact: False, aligned: False, reordered: False),
  )
  |> should.equal("!multiline = true\n!substitutable = true\n\n'x'")
}

// ---------------------------------------------------------------------------
// Definitions
// ---------------------------------------------------------------------------

pub fn definition_simple_test() {
  // Single definition "word" (4 chars) → col = 6, spacing = 2
  fmt("word = %Alpha * 1..? ;\n{word}")
  |> should.equal("word  = %Alpha * 1..? ;\n\n{word}")
}

pub fn definition_alignment_two_test() {
  // "word" (4 chars), "digit" (5 chars) → col = 7
  // "word": 7-4=3 spaces → "word   ="
  // "digit": 7-5=2 spaces → "digit  ="
  // Source order: word, digit
  fmt("word = %Alpha * 1..? ;\ndigit = %Digit * 1..? ;\n{word} {digit}")
  |> should.equal(
    "word   = %Alpha * 1..? ;\ndigit  = %Digit * 1..? ;\n\n{word} {digit}",
  )
}

pub fn definition_not_aligned_test() {
  // No alignment → 1 space before =, source order preserved
  fmt_opts(
    "word = %Alpha * 1..? ;\ndigit = %Digit * 1..? ;\n{word} {digit}",
    opts(line_width: 80, compact: False, aligned: False, reordered: False),
  )
  |> should.equal(
    "word = %Alpha * 1..? ;\ndigit = %Digit * 1..? ;\n\n{word} {digit}",
  )
}

// ---------------------------------------------------------------------------
// Definition line breaking — D1
// ---------------------------------------------------------------------------

pub fn def_d1_break_test() {
  // aligned=False → prefix = "word = " (7 chars)
  // body = "%Digit * 4 %Alpha * 4 %Digit * 4" (32 chars)
  // body_with_semi = 34 chars ≤ line_width(40) - 4 = 36 → D1 applies
  // full_line = 7 + 34 = 41 > 40 → triggers breaking
  fmt_opts(
    "word = %Digit * 4 %Alpha * 4 %Digit * 4 ;\n{word}",
    opts(line_width: 40, compact: False, aligned: False, reordered: False),
  )
  |> should.equal("word =\n    %Digit * 4 %Alpha * 4 %Digit * 4 ;\n\n{word}")
}

// ---------------------------------------------------------------------------
// Definition line breaking — D2
// ---------------------------------------------------------------------------

pub fn def_d2_break_test() {
  // aligned=False → prefix = "word = " (7 chars), col = 7
  // Each 6-char token: 'aaaaaa' = 8 chars (with quotes)
  // body = "'aaaaaa' 'bbbbbb' 'cccccc' 'dddddd' 'eeeeee'" = 8*5 + 4 = 44 chars
  // body_with_semi = 46 > line_width(40) - 4 = 36 → D1 NOT applicable
  // full_line = 7 + 46 = 53 > 40 → D2
  // limit = 40 - 7 = 33; seq spaces at pos 8, 17, 26, 35
  // Rightmost ≤ 33: pos 26 (idx 5)
  // Line 1: "word = 'aaaaaa' 'bbbbbb' 'cccccc'" (33 chars ≤ 40)
  // Line 2: "       'dddddd' 'eeeeee' ;" (26 chars ≤ 40)
  fmt_opts(
    "word = 'aaaaaa' 'bbbbbb' 'cccccc' 'dddddd' 'eeeeee' ;\n{word}",
    opts(line_width: 40, compact: False, aligned: False, reordered: False),
  )
  |> should.equal(
    "word = 'aaaaaa' 'bbbbbb' 'cccccc'\n       'dddddd' 'eeeeee' ;\n\n{word}",
  )
}

// ---------------------------------------------------------------------------
// Body expression line breaking — B1
// ---------------------------------------------------------------------------

pub fn body_b1_break_test() {
  // line_width=40, body = "'aaaaaa' 'bbbbbb' 'cccccc' 'dddddd' 'eeeeee'" = 44 chars
  // PSeqSpace positions: 8, 17, 26, 35; rightmost ≤ 40 is 35
  // Line 1: "'aaaaaa' 'bbbbbb' 'cccccc' 'dddddd'" (35 chars)
  // Line 2: "'eeeeee'" (8 chars)
  fmt_opts(
    "'aaaaaa' 'bbbbbb' 'cccccc' 'dddddd' 'eeeeee'",
    opts(line_width: 40, compact: False, aligned: False, reordered: False),
  )
  |> should.equal("'aaaaaa' 'bbbbbb' 'cccccc' 'dddddd'\n'eeeeee'")
}

pub fn body_b1_repeated_test() {
  // Three-line break: each continuation is tested and broken again if needed
  // "'aa' 'bb' 'cc' 'dd' 'ee' 'ff'" = 30 chars with line_width=12
  // Wait, line_width >= 40. Let me use a longer example with width=40.
  // "'aaaaaaaaaa' 'bbbbbbbbbb' 'cccccccccc' 'dddddddddd'" =
  //   12 + 1 + 12 + 1 + 12 + 1 + 12 = 51 chars > 40
  // PSeqSpace at pos 12, 25, 38; rightmost ≤ 40 is 38
  // Line 1: "'aaaaaaaaaa' 'bbbbbbbbbb' 'cccccccccc'" (38 chars) → break at 38
  // Wait, 38 ≤ 40 ✓. Line 2: "'dddddddddd'" (12 chars ≤ 40) done.
  // Let me make it break twice: add one more item
  // "'aaaaaaaaaa' 'bbbbbbbbbb' 'cccccccccc' 'dddddddddd' 'eeeeeeeeee'"
  //   = 12+1+12+1+12+1+12+1+12 = 63 chars > 40
  // PSeqSpace at 12, 25, 38, 51; rightmost ≤ 40 is 38
  // Line 1: "'aaaaaaaaaa' 'bbbbbbbbbb' 'cccccccccc'" (38 chars)
  // Recurse on remaining: "'dddddddddd' 'eeeeeeeeee'" = 25 chars ≤ 40 ✓
  // So only 2 lines.
  fmt_opts(
    "'aaaaaaaaaa' 'bbbbbbbbbb' 'cccccccccc' 'dddddddddd' 'eeeeeeeeee'",
    opts(line_width: 40, compact: False, aligned: False, reordered: False),
  )
  |> should.equal(
    "'aaaaaaaaaa' 'bbbbbbbbbb' 'cccccccccc'\n'dddddddddd' 'eeeeeeeeee'",
  )
}

// ---------------------------------------------------------------------------
// Body expression line breaking — B2
// ---------------------------------------------------------------------------

pub fn body_b2_break_test() {
  // line_width=40, body = "'alpha-bravo' | 'charlie-delta' | 'echo-foxtrot'"
  // = 13 + 3 + 15 + 3 + 14 = 48 chars > 40
  // No seq spaces → B2
  // PAlt pipes at pos 14 and 32; both ≤ 40 → rightmost is 32
  // Line 1: "'alpha-bravo' | 'charlie-delta'" (31 chars)
  // Line 2: "| 'echo-foxtrot'" (16 chars)
  fmt_opts(
    "'alpha-bravo' | 'charlie-delta' | 'echo-foxtrot'",
    opts(line_width: 40, compact: False, aligned: False, reordered: False),
  )
  |> should.equal("'alpha-bravo' | 'charlie-delta'\n| 'echo-foxtrot'")
}

// ---------------------------------------------------------------------------
// B3 — no break available
// ---------------------------------------------------------------------------

pub fn body_b3_no_break_test() {
  let long_literal = "'" <> string.repeat("x", 50) <> "'"
  fmt_opts(
    long_literal,
    opts(line_width: 40, compact: False, aligned: False, reordered: False),
  )
  |> should.equal(long_literal)
}

// ---------------------------------------------------------------------------
// Compact mode
// ---------------------------------------------------------------------------

pub fn compact_alternation_test() {
  fmt_opts(
    "'a' | 'b' | 'c'",
    opts(line_width: 80, compact: True, aligned: True, reordered: False),
  )
  |> should.equal("'a'|'b'|'c'")
}

pub fn compact_repetition_test() {
  fmt_opts(
    "%Alpha * 1..?",
    opts(line_width: 80, compact: True, aligned: True, reordered: False),
  )
  |> should.equal("%Alpha*1..?")
}

pub fn compact_group_test() {
  fmt_opts(
    "( 'a' | 'b' )",
    opts(line_width: 80, compact: True, aligned: True, reordered: False),
  )
  |> should.equal("('a'|'b')")
}

pub fn compact_no_blank_lines_between_sections_test() {
  // compact=True suppresses blank separators between sections
  // aligned=True: "word" (4 chars) → col=6, spacing=2 → "word  ="
  fmt_opts(
    "!multiline = true\nword = %Alpha * 1..? ;\n{word}",
    opts(line_width: 80, compact: True, aligned: True, reordered: False),
  )
  |> should.equal("!multiline = true\nword  = %Alpha*1..? ;\n{word}")
}

pub fn compact_sequence_space_preserved_test() {
  // Sequence space is always 1 space (not an operator — compact doesn't affect it)
  fmt_opts(
    "'a' 'b' 'c'",
    opts(line_width: 80, compact: True, aligned: True, reordered: False),
  )
  |> should.equal("'a' 'b' 'c'")
}

// ---------------------------------------------------------------------------
// Doc comments
// ---------------------------------------------------------------------------

pub fn ptern_level_comment_test() {
  // §4.1: ptern-level comment block followed by exactly one blank line
  fmt("# top comment\n\n'x'") |> should.equal("# top comment\n\n'x'")
}

pub fn body_comment_test() {
  fmt("# describes the body\n'x'") |> should.equal("# describes the body\n'x'")
}

pub fn annotation_comment_test() {
  fmt("# flag\n!multiline = true\n'x'")
  |> should.equal("# flag\n!multiline = true\n\n'x'")
}

pub fn definition_comment_test() {
  // "word" → col=6, 2 spaces before =
  fmt("# about body\n'hello'")
  |> should.equal("# about body\n'hello'")
}

pub fn definition_with_comment_test() {
  // Definition has a comment above it
  fmt("# about word\nword = %Alpha * 1..? ;\n{word}")
  |> should.equal("# about word\nword  = %Alpha * 1..? ;\n\n{word}")
}

pub fn definition_comment_blank_separator_test() {
  // §4.2: blank line inserted before commented item (when not first and compact=False)
  // "a" (1 char), "b" (1 char) → col=3, spacing=2 → "a  =" and "b  ="
  fmt("a = 'x' ;\n# about b\nb = 'y' ;\n{a} {b}")
  |> should.equal("a  = 'x' ;\n\n# about b\nb  = 'y' ;\n\n{a} {b}")
}

pub fn comment_content_verbatim_test() {
  fmt("#  two spaces  and trailing  \n'x'")
  |> should.equal("#  two spaces  and trailing  \n'x'")
}

pub fn compact_no_blank_before_commented_item_test() {
  // compact=True: no blank line before commented items within a block
  // aligned=True: "a","b" → col=3, spacing=2
  fmt_opts(
    "a = 'x' ;\n# about b\nb = 'y' ;\n{a} {b}",
    opts(line_width: 80, compact: True, aligned: True, reordered: False),
  )
  |> should.equal("a  = 'x' ;\n# about b\nb  = 'y' ;\n{a} {b}")
}

// ---------------------------------------------------------------------------
// Reordering
// ---------------------------------------------------------------------------

pub fn reorder_deps_before_dependents_test() {
  // b depends on a → reordered: a (layer 0) before b (layer 1)
  fmt_opts(
    "b = {a} ;\na = 'x' ;\n{b}",
    opts(line_width: 80, compact: False, aligned: False, reordered: True),
  )
  |> should.equal("a = 'x' ;\nb = {a} ;\n\n{b}")
}

pub fn reorder_alpha_within_layer_test() {
  // c and a are both leaf (layer 0) → sorted alphabetically
  fmt_opts(
    "c = 'z' ;\na = 'x' ;\n{a} {c}",
    opts(line_width: 80, compact: False, aligned: False, reordered: True),
  )
  |> should.equal("a = 'x' ;\nc = 'z' ;\n\n{a} {c}")
}

pub fn reorder_false_preserves_source_order_test() {
  fmt_opts(
    "b = {a} ;\na = 'x' ;\n{b}",
    opts(line_width: 80, compact: False, aligned: False, reordered: False),
  )
  |> should.equal("b = {a} ;\na = 'x' ;\n\n{b}")
}

// ---------------------------------------------------------------------------
// Idempotency
// ---------------------------------------------------------------------------

pub fn idempotent_simple_test() {
  let source = "'hello' 'world'"
  let first = fmt(source)
  let second = fmt(first)
  first |> should.equal(second)
}

pub fn idempotent_with_annotations_and_defs_test() {
  let source =
    "!case-insensitive = true\n!multiline = false\n\nword = %Alpha * 1..? ;\n\n{word}"
  let first = fmt(source)
  let second = fmt(first)
  first |> should.equal(second)
}

pub fn idempotent_with_comments_test() {
  let source = "# comment\n\n# about body\n'x'"
  let first = fmt(source)
  let second = fmt(first)
  first |> should.equal(second)
}
