import gleeunit/should
import lexer/lexer
import lexer/token.{
  As, Asterisk, Bang, CharacterClass, Comment, DoubleQuotedLiteral, Equals,
  Excluding, FalseKeyword, Fewest, Identifier, InlineComment, Integer,
  LeftBrace, LeftParen, AlternativeOperator, QuestionMark, RangeOperator,
  RightBrace, RightParen, Semicolon, SingleQuotedLiteral, TrueKeyword,
  Whitespace,
}

pub fn lex_empty_test() {
  lexer.lex("") |> should.equal(Ok([]))
}

pub fn lex_single_quoted_literal_test() {
  lexer.lex("'hello'")
  |> should.equal(Ok([SingleQuotedLiteral("hello")]))
}

pub fn lex_double_quoted_literal_test() {
  lexer.lex("\"world\"")
  |> should.equal(Ok([DoubleQuotedLiteral("world")]))
}

pub fn lex_string_with_escape_test() {
  lexer.lex("'it\\'s'")
  |> should.equal(Ok([SingleQuotedLiteral("it\\'s")]))
}

pub fn lex_string_with_unicode_escape_test() {
  lexer.lex("'\\u0041'")
  |> should.equal(Ok([SingleQuotedLiteral("\\u0041")]))
}

pub fn lex_single_quoted_unicode_test() {
  lexer.lex("'café'")
  |> should.equal(Ok([SingleQuotedLiteral("café")]))
}

pub fn lex_double_quoted_unicode_test() {
  lexer.lex("\"naïve\"")
  |> should.equal(Ok([DoubleQuotedLiteral("naïve")]))
}

pub fn lex_single_quoted_cjk_test() {
  lexer.lex("'日本語'")
  |> should.equal(Ok([SingleQuotedLiteral("日本語")]))
}

pub fn lex_single_quoted_emoji_test() {
  lexer.lex("'🎉'")
  |> should.equal(Ok([SingleQuotedLiteral("🎉")]))
}

pub fn lex_single_quoted_mixed_unicode_test() {
  lexer.lex("'abc défg'")
  |> should.equal(Ok([SingleQuotedLiteral("abc défg")]))
}

pub fn lex_character_class_test() {
  lexer.lex("%Digit")
  |> should.equal(Ok([CharacterClass("Digit")]))
}

pub fn lex_character_class_single_char_test() {
  lexer.lex("%L")
  |> should.equal(Ok([CharacterClass("L")]))
}

pub fn lex_integer_test() {
  lexer.lex("42")
  |> should.equal(Ok([Integer(42)]))
}

pub fn lex_range_operator_test() {
  lexer.lex("..")
  |> should.equal(Ok([RangeOperator]))
}

pub fn lex_operators_test() {
  lexer.lex("*|=;{}()")
  |> should.equal(
    Ok([
      Asterisk,
      AlternativeOperator,
      Equals,
      Semicolon,
      LeftBrace,
      RightBrace,
      LeftParen,
      RightParen,
    ]),
  )
}

pub fn lex_as_keyword_test() {
  lexer.lex("as")
  |> should.equal(Ok([As]))
}

pub fn lex_excluding_keyword_test() {
  lexer.lex("excluding")
  |> should.equal(Ok([Excluding]))
}

pub fn lex_fewest_keyword_test() {
  lexer.lex("fewest")
  |> should.equal(Ok([Fewest]))
}

pub fn lex_fewest_not_consumed_as_prefix_of_identifier_test() {
  lexer.lex("fewest-more")
  |> should.equal(Ok([Identifier("fewest-more")]))
}

pub fn lex_identifier_test() {
  lexer.lex("my-pattern")
  |> should.equal(Ok([Identifier("my-pattern")]))
}

pub fn lex_whitespace_collapses_run_test() {
  lexer.lex("a   b")
  |> should.equal(Ok([Identifier("a"), Whitespace(False), Identifier("b")]))
}

// ---------------------------------------------------------------------------
// Comments
// ---------------------------------------------------------------------------

pub fn lex_comment_test() {
  lexer.lex("# a comment\n'x'")
  |> should.equal(
    Ok([Comment(" a comment"), Whitespace(False), SingleQuotedLiteral("x")]),
  )
}

pub fn lex_comment_at_end_of_input_test() {
  lexer.lex("# no newline")
  |> should.equal(Ok([Comment(" no newline")]))
}

pub fn lex_inline_comment_is_error_test() {
  lexer.lex("'x' # inline comment")
  |> should.equal(Error(InlineComment))
}

pub fn lex_inline_comment_mid_expression_is_error_test() {
  lexer.lex("%Digit # not allowed here")
  |> should.equal(Error(InlineComment))
}

// ---------------------------------------------------------------------------
// Whitespace blank-line detection
// ---------------------------------------------------------------------------

pub fn lex_single_newline_has_no_blank_line_test() {
  lexer.lex("'a'\n'b'")
  |> should.equal(
    Ok([SingleQuotedLiteral("a"), Whitespace(False), SingleQuotedLiteral("b")]),
  )
}

pub fn lex_blank_line_sets_has_blank_line_test() {
  lexer.lex("'a'\n\n'b'")
  |> should.equal(
    Ok([SingleQuotedLiteral("a"), Whitespace(True), SingleQuotedLiteral("b")]),
  )
}

pub fn lex_blank_line_with_spaces_sets_has_blank_line_test() {
  lexer.lex("'a'\n   \n'b'")
  |> should.equal(
    Ok([SingleQuotedLiteral("a"), Whitespace(True), SingleQuotedLiteral("b")]),
  )
}

pub fn lex_comment_at_start_of_file_test() {
  lexer.lex("# ptern doc\n'x'")
  |> should.equal(
    Ok([Comment(" ptern doc"), Whitespace(False), SingleQuotedLiteral("x")]),
  )
}

pub fn lex_comment_after_blank_line_at_top_test() {
  lexer.lex("# ptern doc\n\n'x'")
  |> should.equal(
    Ok([Comment(" ptern doc"), Whitespace(True), SingleQuotedLiteral("x")]),
  )
}

// ---------------------------------------------------------------------------
// Existing token tests
// ---------------------------------------------------------------------------

pub fn lex_repetition_expression_test() {
  lexer.lex("%Digit * 4")
  |> should.equal(
    Ok([
      CharacterClass("Digit"),
      Whitespace(False),
      Asterisk,
      Whitespace(False),
      Integer(4),
    ]),
  )
}

pub fn lex_question_mark_test() {
  lexer.lex("?")
  |> should.equal(Ok([QuestionMark]))
}

pub fn lex_unbounded_repetition_test() {
  lexer.lex("%Digit * 1..?")
  |> should.equal(
    Ok([
      CharacterClass("Digit"),
      Whitespace(False),
      Asterisk,
      Whitespace(False),
      Integer(1),
      RangeOperator,
      QuestionMark,
    ]),
  )
}

pub fn lex_bounded_repetition_test() {
  lexer.lex("'*' * 3..10")
  |> should.equal(
    Ok([
      SingleQuotedLiteral("*"),
      Whitespace(False),
      Asterisk,
      Whitespace(False),
      Integer(3),
      RangeOperator,
      Integer(10),
    ]),
  )
}

pub fn lex_iso_date_pattern_test() {
  let input =
    "\n  yyyy = %Digit * 4;\n  mm = '0' '1'..'9' | '1' '0'..'2';\n  dd = '0' '1'..'9' | '1'..'2' %Digit | '3' '0'..'1';\n  {yyyy} as year '-' {mm} as month '-' {dd} as day\n"

  lexer.lex(input)
  |> should.equal(
    Ok([
      // leading newline + spaces
      Whitespace(False),
      // yyyy = %Digit * 4;
      Identifier("yyyy"),
      Whitespace(False),
      Equals,
      Whitespace(False),
      CharacterClass("Digit"),
      Whitespace(False),
      Asterisk,
      Whitespace(False),
      Integer(4),
      Semicolon,
      // mm = '0' '1'..'9' | '1' '0'..'2';
      Whitespace(False),
      Identifier("mm"),
      Whitespace(False),
      Equals,
      Whitespace(False),
      SingleQuotedLiteral("0"),
      Whitespace(False),
      SingleQuotedLiteral("1"),
      RangeOperator,
      SingleQuotedLiteral("9"),
      Whitespace(False),
      AlternativeOperator,
      Whitespace(False),
      SingleQuotedLiteral("1"),
      Whitespace(False),
      SingleQuotedLiteral("0"),
      RangeOperator,
      SingleQuotedLiteral("2"),
      Semicolon,
      // dd = ...
      Whitespace(False),
      Identifier("dd"),
      Whitespace(False),
      Equals,
      Whitespace(False),
      SingleQuotedLiteral("0"),
      Whitespace(False),
      SingleQuotedLiteral("1"),
      RangeOperator,
      SingleQuotedLiteral("9"),
      Whitespace(False),
      AlternativeOperator,
      Whitespace(False),
      SingleQuotedLiteral("1"),
      RangeOperator,
      SingleQuotedLiteral("2"),
      Whitespace(False),
      CharacterClass("Digit"),
      Whitespace(False),
      AlternativeOperator,
      Whitespace(False),
      SingleQuotedLiteral("3"),
      Whitespace(False),
      SingleQuotedLiteral("0"),
      RangeOperator,
      SingleQuotedLiteral("1"),
      Semicolon,
      // {yyyy} as year '-' {mm} as month '-' {dd} as day
      Whitespace(False),
      LeftBrace,
      Identifier("yyyy"),
      RightBrace,
      Whitespace(False),
      As,
      Whitespace(False),
      Identifier("year"),
      Whitespace(False),
      SingleQuotedLiteral("-"),
      Whitespace(False),
      LeftBrace,
      Identifier("mm"),
      RightBrace,
      Whitespace(False),
      As,
      Whitespace(False),
      Identifier("month"),
      Whitespace(False),
      SingleQuotedLiteral("-"),
      Whitespace(False),
      LeftBrace,
      Identifier("dd"),
      RightBrace,
      Whitespace(False),
      As,
      Whitespace(False),
      Identifier("day"),
      Whitespace(False),
    ]),
  )
}

pub fn lex_definition_test() {
  lexer.lex("yyyy = %Digit * 4;")
  |> should.equal(
    Ok([
      Identifier("yyyy"),
      Whitespace(False),
      Equals,
      Whitespace(False),
      CharacterClass("Digit"),
      Whitespace(False),
      Asterisk,
      Whitespace(False),
      Integer(4),
      Semicolon,
    ]),
  )
}

pub fn lex_alternatives_test() {
  lexer.lex("'a' | 'b'")
  |> should.equal(
    Ok([
      SingleQuotedLiteral("a"),
      Whitespace(False),
      AlternativeOperator,
      Whitespace(False),
      SingleQuotedLiteral("b"),
    ]),
  )
}

pub fn lex_bang_test() {
  lexer.lex("!")
  |> should.equal(Ok([Bang]))
}

pub fn lex_true_keyword_test() {
  lexer.lex("true")
  |> should.equal(Ok([TrueKeyword]))
}

pub fn lex_false_keyword_test() {
  lexer.lex("false")
  |> should.equal(Ok([FalseKeyword]))
}

pub fn lex_annotation_test() {
  lexer.lex("!case-insensitive = true")
  |> should.equal(
    Ok([
      Bang,
      Identifier("case-insensitive"),
      Whitespace(False),
      Equals,
      Whitespace(False),
      TrueKeyword,
    ]),
  )
}

pub fn lex_excluding_expression_test() {
  lexer.lex("%Digit excluding '8'..'9'")
  |> should.equal(
    Ok([
      CharacterClass("Digit"),
      Whitespace(False),
      Excluding,
      Whitespace(False),
      SingleQuotedLiteral("8"),
      RangeOperator,
      SingleQuotedLiteral("9"),
    ]),
  )
}

// ---------------------------------------------------------------------------
// Position assertions
// ---------------------------------------------------------------------------

pub fn lex_position_assertion_word_start_test() {
  lexer.lex("@word-start")
  |> should.equal(Ok([token.PositionAssertion("word-start")]))
}

pub fn lex_position_assertion_word_end_test() {
  lexer.lex("@word-end")
  |> should.equal(Ok([token.PositionAssertion("word-end")]))
}

pub fn lex_position_assertion_line_start_test() {
  lexer.lex("@line-start")
  |> should.equal(Ok([token.PositionAssertion("line-start")]))
}

pub fn lex_position_assertion_line_end_test() {
  lexer.lex("@line-end")
  |> should.equal(Ok([token.PositionAssertion("line-end")]))
}

pub fn lex_bare_at_sign_is_error_test() {
  lexer.lex("@")
  |> should.be_error
}

pub fn lex_position_assertion_in_sequence_test() {
  lexer.lex("@word-start %Alpha @word-end")
  |> should.equal(
    Ok([
      token.PositionAssertion("word-start"),
      Whitespace(False),
      CharacterClass("Alpha"),
      Whitespace(False),
      token.PositionAssertion("word-end"),
    ]),
  )
}
