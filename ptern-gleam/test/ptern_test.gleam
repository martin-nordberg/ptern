import gleam/dict
import gleam/list
import gleam/option.{None, Some}
import gleeunit
import gleeunit/should
import lexer/token
import parser/ast
import ptern
import semantic/error

pub fn main() {
  gleeunit.main()
}

// ---------------------------------------------------------------------------
// Helper
// ---------------------------------------------------------------------------

fn has_semantic_error(
  result: Result(ptern.Ptern, ptern.CompileError),
  expected: error.SemanticError,
) -> Bool {
  case result {
    Error(ptern.SemanticErrors(errors)) -> list.contains(errors, expected)
    _ -> False
  }
}

// ---------------------------------------------------------------------------
// Compile — success cases
// ---------------------------------------------------------------------------

pub fn compile_simple_literal_test() {
  ptern.compile("'hello'") |> should.be_ok
}

pub fn compile_charclass_test() {
  ptern.compile("%Digit") |> should.be_ok
}

pub fn compile_range_test() {
  ptern.compile("'a'..'z'") |> should.be_ok
}

pub fn compile_alternation_test() {
  ptern.compile("'foo' | 'bar'") |> should.be_ok
}

pub fn compile_named_capture_test() {
  ptern.compile("%Digit * 4 as year") |> should.be_ok
}

pub fn compile_definition_and_interpolation_test() {
  ptern.compile("d = %Digit * 4; {d}") |> should.be_ok
}

pub fn compile_valid_escape_sequences_test() {
  ptern.compile("'\\n\\t\\r\\\\'") |> should.be_ok
}

pub fn compile_excluding_test() {
  ptern.compile("'a'..'z' excluding 'q'") |> should.be_ok
}

// ---------------------------------------------------------------------------
// matches / starts / ends / contained_in
// ---------------------------------------------------------------------------

pub fn matches_exact_test() {
  let assert Ok(p) = ptern.compile("'hello'")
  ptern.matches(p, "hello") |> should.be_true
}

pub fn matches_rejects_partial_test() {
  let assert Ok(p) = ptern.compile("'hello'")
  ptern.matches(p, "hello world") |> should.be_false
}

pub fn starts_test() {
  let assert Ok(p) = ptern.compile("'hello'")
  ptern.starts(p, "hello world") |> should.be_true
}

pub fn starts_rejects_non_prefix_test() {
  let assert Ok(p) = ptern.compile("'hello'")
  ptern.starts(p, "say hello") |> should.be_false
}

pub fn ends_test() {
  let assert Ok(p) = ptern.compile("'hello'")
  ptern.ends(p, "say hello") |> should.be_true
}

pub fn ends_rejects_non_suffix_test() {
  let assert Ok(p) = ptern.compile("'hello'")
  ptern.ends(p, "hello world") |> should.be_false
}

pub fn contained_in_test() {
  let assert Ok(p) = ptern.compile("'hello'")
  ptern.contained_in(p, "say hello world") |> should.be_true
}

pub fn contained_in_rejects_absent_test() {
  let assert Ok(p) = ptern.compile("'hello'")
  ptern.contained_in(p, "goodbye world") |> should.be_false
}

pub fn case_insensitive_matches_test() {
  let assert Ok(p) = ptern.compile("@case-insensitive = true\n'hello'")
  ptern.matches(p, "HELLO") |> should.be_true
}

pub fn digit_pattern_matches_test() {
  let assert Ok(p) = ptern.compile("%Digit * 4")
  ptern.matches(p, "2026") |> should.be_true
}

pub fn digit_pattern_rejects_letters_test() {
  let assert Ok(p) = ptern.compile("%Digit * 4")
  ptern.matches(p, "abcd") |> should.be_false
}

pub fn alternation_matches_either_test() {
  let assert Ok(p) = ptern.compile("'cat' | 'dog'")
  ptern.matches(p, "cat") |> should.be_true
  ptern.matches(p, "dog") |> should.be_true
  ptern.matches(p, "fish") |> should.be_false
}

// ---------------------------------------------------------------------------
// match (named captures)
// ---------------------------------------------------------------------------

pub fn match_returns_none_on_no_match_test() {
  let assert Ok(p) = ptern.compile("'hello'")
  ptern.match(p, "goodbye") |> should.equal(None)
}

pub fn match_returns_some_on_match_test() {
  let assert Ok(p) = ptern.compile("'hello'")
  ptern.match(p, "hello") |> should.not_equal(None)
}

pub fn match_returns_named_captures_test() {
  let assert Ok(p) = ptern.compile("%Digit * 4 as year")
  let assert Some(groups) = ptern.match(p, "2026")
  dict.get(groups, "year") |> should.equal(Ok("2026"))
}

pub fn match_iso_date_captures_test() {
  let src =
    "yyyy = %Digit * 4;\n"
    <> "mm = ('0' '1'..'9') | ('1' '0'..'2');\n"
    <> "dd = ('0' '1'..'9') | ('1'..'2' %Digit) | ('3' '0'..'1');\n"
    <> "{yyyy} as year '-' {mm} as month '-' {dd} as day"
  let assert Ok(p) = ptern.compile(src)
  let assert Some(groups) = ptern.match(p, "2026-07-04")
  dict.get(groups, "year") |> should.equal(Ok("2026"))
  dict.get(groups, "month") |> should.equal(Ok("07"))
  dict.get(groups, "day") |> should.equal(Ok("04"))
}

// ---------------------------------------------------------------------------
// Length bounds
// ---------------------------------------------------------------------------

pub fn min_length_literal_test() {
  let assert Ok(p) = ptern.compile("'hello'")
  ptern.min_length(p) |> should.equal(5)
}

pub fn max_length_literal_test() {
  let assert Ok(p) = ptern.compile("'hello'")
  ptern.max_length(p) |> should.equal(Some(5))
}

pub fn min_length_digit_test() {
  let assert Ok(p) = ptern.compile("%Digit")
  ptern.min_length(p) |> should.equal(1)
}

pub fn max_length_digit_test() {
  let assert Ok(p) = ptern.compile("%Digit")
  ptern.max_length(p) |> should.equal(Some(1))
}

pub fn min_length_exact_repetition_test() {
  let assert Ok(p) = ptern.compile("%Digit * 4")
  ptern.min_length(p) |> should.equal(4)
}

pub fn max_length_exact_repetition_test() {
  let assert Ok(p) = ptern.compile("%Digit * 4")
  ptern.max_length(p) |> should.equal(Some(4))
}

pub fn min_length_bounded_repetition_test() {
  let assert Ok(p) = ptern.compile("%Digit * 2..5")
  ptern.min_length(p) |> should.equal(2)
}

pub fn max_length_bounded_repetition_test() {
  let assert Ok(p) = ptern.compile("%Digit * 2..5")
  ptern.max_length(p) |> should.equal(Some(5))
}

pub fn max_length_unbounded_repetition_test() {
  let assert Ok(p) = ptern.compile("%Digit * 1..?")
  ptern.max_length(p) |> should.equal(None)
}

pub fn min_length_unbounded_repetition_test() {
  let assert Ok(p) = ptern.compile("%Digit * 1..?")
  ptern.min_length(p) |> should.equal(1)
}

pub fn min_length_optional_is_zero_test() {
  let assert Ok(p) = ptern.compile("%Digit * 0..1")
  ptern.min_length(p) |> should.equal(0)
}

pub fn max_length_optional_is_one_test() {
  let assert Ok(p) = ptern.compile("%Digit * 0..1")
  ptern.max_length(p) |> should.equal(Some(1))
}

pub fn min_length_sequence_test() {
  let assert Ok(p) = ptern.compile("'ab' %Digit")
  ptern.min_length(p) |> should.equal(3)
}

pub fn max_length_sequence_test() {
  let assert Ok(p) = ptern.compile("'ab' %Digit")
  ptern.max_length(p) |> should.equal(Some(3))
}

pub fn min_length_alternation_test() {
  let assert Ok(p) = ptern.compile("'a' | 'bcd'")
  ptern.min_length(p) |> should.equal(1)
}

pub fn max_length_alternation_test() {
  let assert Ok(p) = ptern.compile("'a' | 'bcd'")
  ptern.max_length(p) |> should.equal(Some(3))
}

pub fn max_length_alternation_with_unbounded_test() {
  let assert Ok(p) = ptern.compile("'a' | %Digit * 1..?")
  ptern.max_length(p) |> should.equal(None)
}

pub fn min_length_definition_interpolation_test() {
  let assert Ok(p) = ptern.compile("d = %Digit * 4; {d}")
  ptern.min_length(p) |> should.equal(4)
}

pub fn max_length_definition_interpolation_test() {
  let assert Ok(p) = ptern.compile("d = %Digit * 4; {d}")
  ptern.max_length(p) |> should.equal(Some(4))
}

// ---------------------------------------------------------------------------
// Lex errors
// ---------------------------------------------------------------------------

pub fn lex_error_unterminated_single_quote_test() {
  case ptern.compile("'hello") {
    Error(ptern.LexError(token.UnterminatedString)) -> Nil
    _ -> should.fail()
  }
}

pub fn lex_error_unterminated_double_quote_test() {
  case ptern.compile("\"world") {
    Error(ptern.LexError(token.UnterminatedString)) -> Nil
    _ -> should.fail()
  }
}

pub fn lex_error_unexpected_character_test() {
  case ptern.compile("~") {
    Error(ptern.LexError(token.UnexpectedCharacter(_))) -> Nil
    _ -> should.fail()
  }
}

pub fn lex_error_unexpected_character_dollar_test() {
  case ptern.compile("$") {
    Error(ptern.LexError(token.UnexpectedCharacter(_))) -> Nil
    _ -> should.fail()
  }
}

// ---------------------------------------------------------------------------
// Parse errors
// ---------------------------------------------------------------------------

pub fn parse_error_empty_input_test() {
  case ptern.compile("") {
    Error(ptern.ParseError(ast.UnexpectedEndOfInput)) -> Nil
    _ -> should.fail()
  }
}

pub fn parse_error_unclosed_group_test() {
  case ptern.compile("('a'") {
    Error(ptern.ParseError(_)) -> Nil
    _ -> should.fail()
  }
}

pub fn parse_error_missing_semicolon_test() {
  case ptern.compile("d = %Digit") {
    Error(ptern.ParseError(_)) -> Nil
    _ -> should.fail()
  }
}

pub fn parse_error_stray_token_test() {
  case ptern.compile("'a' )") {
    Error(ptern.ParseError(ast.UnexpectedToken(_, _))) -> Nil
    _ -> should.fail()
  }
}

pub fn parse_error_missing_rep_count_test() {
  case ptern.compile("%Digit *") {
    Error(ptern.ParseError(_)) -> Nil
    _ -> should.fail()
  }
}

pub fn parse_error_missing_upper_bound_test() {
  case ptern.compile("%Digit * 1..") {
    Error(ptern.ParseError(_)) -> Nil
    _ -> should.fail()
  }
}

pub fn parse_error_unclosed_interpolation_test() {
  case ptern.compile("{name") {
    Error(ptern.ParseError(_)) -> Nil
    _ -> should.fail()
  }
}

// ---------------------------------------------------------------------------
// Semantic — annotation errors
// ---------------------------------------------------------------------------

pub fn unknown_annotation_test() {
  ptern.compile("@typo = true\n'x'")
  |> has_semantic_error(error.UnknownAnnotation("typo"))
  |> should.be_true
}

pub fn unknown_annotation_wrong_case_test() {
  ptern.compile("@Case-Insensitive = true\n'x'")
  |> has_semantic_error(error.UnknownAnnotation("Case-Insensitive"))
  |> should.be_true
}

pub fn duplicate_annotation_test() {
  ptern.compile("@case-insensitive = true\n@case-insensitive = false\n'x'")
  |> has_semantic_error(error.DuplicateAnnotation("case-insensitive"))
  |> should.be_true
}

// ---------------------------------------------------------------------------
// Semantic — escape sequence errors
// ---------------------------------------------------------------------------

pub fn invalid_escape_sequence_test() {
  ptern.compile("'\\z'")
  |> has_semantic_error(error.InvalidEscapeSequence("\\z"))
  |> should.be_true
}

pub fn invalid_escape_sequence_x_test() {
  ptern.compile("'\\x41'")
  |> has_semantic_error(error.InvalidEscapeSequence("\\x"))
  |> should.be_true
}

// ---------------------------------------------------------------------------
// Semantic — repetition errors
// ---------------------------------------------------------------------------

pub fn inverted_repetition_bounds_test() {
  ptern.compile("%Digit * 5..2")
  |> has_semantic_error(error.InvertedRepetitionBounds(5, 2))
  |> should.be_true
}

pub fn inverted_repetition_bounds_large_test() {
  ptern.compile("'a' * 100..1")
  |> has_semantic_error(error.InvertedRepetitionBounds(100, 1))
  |> should.be_true
}

pub fn capture_in_repetition_test() {
  ptern.compile("('a' as x) * 3")
  |> has_semantic_error(error.CaptureInRepetition("x"))
  |> should.be_true
}

pub fn capture_in_bounded_repetition_test() {
  ptern.compile("('a' as val) * 1..5")
  |> has_semantic_error(error.CaptureInRepetition("val"))
  |> should.be_true
}

pub fn capture_in_optional_repetition_test() {
  ptern.compile("('a' as opt) * 0..1")
  |> has_semantic_error(error.CaptureInRepetition("opt"))
  |> should.be_true
}

pub fn capture_in_unbounded_repetition_test() {
  ptern.compile("(%Digit as d) * 1..?")
  |> has_semantic_error(error.CaptureInRepetition("d"))
  |> should.be_true
}

// ---------------------------------------------------------------------------
// Semantic — range and exclusion errors
// ---------------------------------------------------------------------------

pub fn invalid_range_endpoint_multi_char_left_test() {
  ptern.compile("'ab'..'z'")
  |> has_semantic_error(error.InvalidRangeEndpoint("ab"))
  |> should.be_true
}

pub fn invalid_range_endpoint_multi_char_right_test() {
  ptern.compile("'a'..'yz'")
  |> has_semantic_error(error.InvalidRangeEndpoint("yz"))
  |> should.be_true
}

pub fn inverted_range_test() {
  ptern.compile("'z'..'a'")
  |> has_semantic_error(error.InvertedRange("z", "a"))
  |> should.be_true
}

pub fn inverted_range_digits_test() {
  ptern.compile("'9'..'0'")
  |> has_semantic_error(error.InvertedRange("9", "0"))
  |> should.be_true
}

pub fn invalid_exclusion_operand_group_test() {
  ptern.compile("'a'..'z' excluding ('x')")
  |> has_semantic_error(error.InvalidExclusionOperand)
  |> should.be_true
}

// ---------------------------------------------------------------------------
// Semantic — reference and definition errors
// ---------------------------------------------------------------------------

pub fn undefined_reference_test() {
  ptern.compile("{missing}")
  |> has_semantic_error(error.UndefinedReference("missing"))
  |> should.be_true
}

pub fn undefined_reference_in_definition_test() {
  ptern.compile("a = {undefined}; {a}")
  |> has_semantic_error(error.UndefinedReference("undefined"))
  |> should.be_true
}

pub fn duplicate_definition_test() {
  ptern.compile("a = 'x'; a = 'y'; {a}")
  |> has_semantic_error(error.DuplicateDefinition("a"))
  |> should.be_true
}

pub fn duplicate_definition_triple_test() {
  ptern.compile("d = '1'; d = '2'; d = '3'; {d}")
  |> has_semantic_error(error.DuplicateDefinition("d"))
  |> should.be_true
}

pub fn circular_definition_self_test() {
  ptern.compile("a = {a}; {a}")
  |> has_semantic_error(error.CircularDefinition(["a"]))
  |> should.be_true
}

pub fn circular_definition_two_node_test() {
  ptern.compile("a = {b}; b = {a}; {a}")
  |> has_semantic_error(error.CircularDefinition(["a", "b"]))
  |> should.be_true
}

pub fn duplicate_capture_test() {
  ptern.compile("'a' as x '-' 'b' as x")
  |> has_semantic_error(error.DuplicateCapture("x"))
  |> should.be_true
}

pub fn duplicate_capture_three_uses_test() {
  ptern.compile("'a' as v '-' 'b' as v '-' 'c' as v")
  |> has_semantic_error(error.DuplicateCapture("v"))
  |> should.be_true
}

pub fn capture_definition_conflict_test() {
  ptern.compile("d = 'x'; 'a' as d")
  |> has_semantic_error(error.CaptureDefinitionConflict("d"))
  |> should.be_true
}

pub fn capture_definition_conflict_named_test() {
  ptern.compile("year = %Digit * 4; %Digit * 4 as year")
  |> has_semantic_error(error.CaptureDefinitionConflict("year"))
  |> should.be_true
}
