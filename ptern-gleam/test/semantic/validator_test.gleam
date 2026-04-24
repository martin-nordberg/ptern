import gleeunit/should
import lexer/lexer
import parser/parser
import semantic/error.{
  CaptureInRepetition, DuplicateAnnotation, InvalidEscapeSequence,
  InvalidExclusionOperand, InvalidRangeEndpoint, InvertedRange,
  InvertedRepetitionBounds, UnknownAnnotation,
}
import semantic/validator

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn validate(input: String) -> List(error.SemanticError) {
  let assert Ok(tokens) = lexer.lex(input)
  let assert Ok(ptern) = parser.parse(tokens)
  validator.validate(ptern)
}

fn has_error(errs: List(error.SemanticError), target: error.SemanticError) -> Bool {
  case errs {
    [] -> False
    [e, ..rest] -> e == target || has_error(rest, target)
  }
}

// ---------------------------------------------------------------------------
// No errors
// ---------------------------------------------------------------------------

pub fn valid_literal_test() {
  validate("'hello'")
  |> should.equal([])
}

pub fn valid_char_class_test() {
  validate("%Digit")
  |> should.equal([])
}

pub fn valid_range_test() {
  validate("'a'..'z'")
  |> should.equal([])
}

pub fn valid_repetition_exact_test() {
  validate("%Digit * 4")
  |> should.equal([])
}

pub fn valid_repetition_bounded_test() {
  validate("%Digit * 1..10")
  |> should.equal([])
}

pub fn valid_repetition_unbounded_test() {
  validate("%Digit * 1..?")
  |> should.equal([])
}

pub fn valid_exclusion_test() {
  validate("%Digit excluding '8'..'9'")
  |> should.equal([])
}

pub fn valid_capture_test() {
  validate("%Digit * 4 as year")
  |> should.equal([])
}

pub fn valid_annotation_test() {
  validate("!case-insensitive = true\n'x'")
  |> should.equal([])
}

pub fn valid_escape_sequences_test() {
  validate("'\\n\\t\\r\\'\\\"'")
  |> should.equal([])
}

pub fn valid_unicode_escape_test() {
  validate("'\\u0041'")
  |> should.equal([])
}

// ---------------------------------------------------------------------------
// Escape sequence errors
// ---------------------------------------------------------------------------

pub fn invalid_escape_sequence_test() {
  validate("'\\z'")
  |> should.equal([InvalidEscapeSequence("\\z")])
}

pub fn invalid_escape_multiple_test() {
  let errs = validate("'\\q\\p'")
  errs |> has_error(InvalidEscapeSequence("\\q")) |> should.be_true
  errs |> has_error(InvalidEscapeSequence("\\p")) |> should.be_true
}

// ---------------------------------------------------------------------------
// Range endpoint errors
// ---------------------------------------------------------------------------

pub fn invalid_range_endpoint_multi_char_test() {
  let errs = validate("'ab'..'z'")
  errs |> has_error(InvalidRangeEndpoint("ab")) |> should.be_true
}

pub fn invalid_range_endpoint_non_literal_test() {
  // CharClass as range endpoint is not a literal
  let errs = validate("'a'..%Digit")
  errs |> should.not_equal([])
}

pub fn inverted_range_test() {
  validate("'z'..'a'")
  |> should.equal([InvertedRange("z", "a")])
}

pub fn equal_range_is_valid_test() {
  validate("'a'..'a'")
  |> should.equal([])
}

// ---------------------------------------------------------------------------
// Repetition bound errors
// ---------------------------------------------------------------------------

pub fn inverted_repetition_bounds_test() {
  validate("%Digit * 10..3")
  |> should.equal([InvertedRepetitionBounds(10, 3)])
}

pub fn equal_repetition_bounds_valid_test() {
  validate("%Digit * 3..3")
  |> should.equal([])
}

// ---------------------------------------------------------------------------
// Exclusion operand errors
// ---------------------------------------------------------------------------

pub fn invalid_exclusion_group_operand_test() {
  let errs = validate("'a'..'z' excluding ('a')")
  errs |> has_error(InvalidExclusionOperand) |> should.be_true
}

pub fn invalid_exclusion_interpolation_operand_test() {
  // {x} on the right of excluding is not a char-set
  let errs = validate("d = 'a'; %Alpha excluding {d}")
  errs |> has_error(InvalidExclusionOperand) |> should.be_true
}

// ---------------------------------------------------------------------------
// Annotation errors
// ---------------------------------------------------------------------------

pub fn unknown_annotation_test() {
  let errs = validate("!typo = true\n'x'")
  errs |> should.equal([UnknownAnnotation("typo")])
}

pub fn replacements_preserve_matching_annotation_accepted_test() {
  validate("!replacements-preserve-matching = true\n'x'")
  |> should.equal([])
}

pub fn duplicate_annotation_test() {
  let errs = validate("!case-insensitive = true\n!case-insensitive = false\n'x'")
  errs |> should.equal([DuplicateAnnotation("case-insensitive")])
}

// ---------------------------------------------------------------------------
// Capture inside repetition errors
// ---------------------------------------------------------------------------

pub fn capture_inside_repetition_test() {
  let errs = validate("(%Digit as d) * 3")
  errs |> should.equal([CaptureInRepetition("d")])
}

pub fn capture_outside_repetition_is_valid_test() {
  validate("%Digit * 3 as d")
  |> should.equal([])
}

pub fn nested_capture_inside_repetition_test() {
  let errs = validate("(('a' as inner) * 2) * 3")
  errs |> has_error(CaptureInRepetition("inner")) |> should.be_true
}
