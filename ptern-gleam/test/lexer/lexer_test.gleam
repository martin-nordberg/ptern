import gleeunit/should
import lexer/lexer
import lexer/token.{
  As, At, Asterisk, Bang, CharacterClass, Comment, DoubleQuotedLiteral, Equals,
  Excluding, FalseKeyword, Identifier, Integer, LeftBrace, LeftParen,
  AlternativeOperator, QuestionMark, RangeOperator, RightBrace, RightParen,
  Semicolon, SingleQuotedLiteral, TrueKeyword, Whitespace,
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

pub fn lex_identifier_test() {
  lexer.lex("my-pattern")
  |> should.equal(Ok([Identifier("my-pattern")]))
}

pub fn lex_whitespace_collapses_run_test() {
  lexer.lex("a   b")
  |> should.equal(Ok([Identifier("a"), Whitespace, Identifier("b")]))
}

pub fn lex_comment_test() {
  lexer.lex("# a comment\n'x'")
  |> should.equal(
    Ok([Comment(" a comment"), Whitespace, SingleQuotedLiteral("x")]),
  )
}

pub fn lex_comment_at_end_of_input_test() {
  lexer.lex("# no newline")
  |> should.equal(Ok([Comment(" no newline")]))
}

pub fn lex_repetition_expression_test() {
  lexer.lex("%Digit * 4")
  |> should.equal(
    Ok([CharacterClass("Digit"), Whitespace, Asterisk, Whitespace, Integer(4)]),
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
      Whitespace,
      Asterisk,
      Whitespace,
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
      Whitespace,
      Asterisk,
      Whitespace,
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
      // yyyy = %Digit * 4;
      Whitespace,
      Identifier("yyyy"),
      Whitespace,
      Equals,
      Whitespace,
      CharacterClass("Digit"),
      Whitespace,
      Asterisk,
      Whitespace,
      Integer(4),
      Semicolon,
      // mm = '0' '1'..'9' | '1' '0'..'2';
      Whitespace,
      Identifier("mm"),
      Whitespace,
      Equals,
      Whitespace,
      SingleQuotedLiteral("0"),
      Whitespace,
      SingleQuotedLiteral("1"),
      RangeOperator,
      SingleQuotedLiteral("9"),
      Whitespace,
      AlternativeOperator,
      Whitespace,
      SingleQuotedLiteral("1"),
      Whitespace,
      SingleQuotedLiteral("0"),
      RangeOperator,
      SingleQuotedLiteral("2"),
      Semicolon,
      // dd = '0' '1'..'9' | '1'..'2' %Digit | '3' '0'..'1';
      Whitespace,
      Identifier("dd"),
      Whitespace,
      Equals,
      Whitespace,
      SingleQuotedLiteral("0"),
      Whitespace,
      SingleQuotedLiteral("1"),
      RangeOperator,
      SingleQuotedLiteral("9"),
      Whitespace,
      AlternativeOperator,
      Whitespace,
      SingleQuotedLiteral("1"),
      RangeOperator,
      SingleQuotedLiteral("2"),
      Whitespace,
      CharacterClass("Digit"),
      Whitespace,
      AlternativeOperator,
      Whitespace,
      SingleQuotedLiteral("3"),
      Whitespace,
      SingleQuotedLiteral("0"),
      RangeOperator,
      SingleQuotedLiteral("1"),
      Semicolon,
      // {yyyy} as year '-' {mm} as month '-' {dd} as day
      Whitespace,
      LeftBrace,
      Identifier("yyyy"),
      RightBrace,
      Whitespace,
      As,
      Whitespace,
      Identifier("year"),
      Whitespace,
      SingleQuotedLiteral("-"),
      Whitespace,
      LeftBrace,
      Identifier("mm"),
      RightBrace,
      Whitespace,
      As,
      Whitespace,
      Identifier("month"),
      Whitespace,
      SingleQuotedLiteral("-"),
      Whitespace,
      LeftBrace,
      Identifier("dd"),
      RightBrace,
      Whitespace,
      As,
      Whitespace,
      Identifier("day"),
      Whitespace,
    ]),
  )
}

pub fn lex_definition_test() {
  lexer.lex("yyyy = %Digit * 4;")
  |> should.equal(
    Ok([
      Identifier("yyyy"),
      Whitespace,
      Equals,
      Whitespace,
      CharacterClass("Digit"),
      Whitespace,
      Asterisk,
      Whitespace,
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
      Whitespace,
      AlternativeOperator,
      Whitespace,
      SingleQuotedLiteral("b"),
    ]),
  )
}

pub fn lex_bang_test() {
  lexer.lex("!")
  |> should.equal(Ok([Bang]))
}

pub fn lex_at_sign_test() {
  lexer.lex("@")
  |> should.equal(Ok([At]))
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
      Whitespace,
      Equals,
      Whitespace,
      TrueKeyword,
    ]),
  )
}

pub fn lex_excluding_expression_test() {
  lexer.lex("%Digit excluding '8'..'9'")
  |> should.equal(
    Ok([
      CharacterClass("Digit"),
      Whitespace,
      Excluding,
      Whitespace,
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

pub fn lex_bare_at_sign_still_produces_at_test() {
  lexer.lex("@")
  |> should.equal(Ok([At]))
}

pub fn lex_position_assertion_in_sequence_test() {
  lexer.lex("@word-start %Alpha @word-end")
  |> should.equal(
    Ok([
      token.PositionAssertion("word-start"),
      Whitespace,
      CharacterClass("Alpha"),
      Whitespace,
      token.PositionAssertion("word-end"),
    ]),
  )
}
