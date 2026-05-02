import gleeunit/should
import lexer/lexer
import parser/parser
import semantic/error.{
  BoundedRepetitionNeedsCapture, DuplicateAnnotation, EmptyCharacterSet,
  EmptyLiteral, InvalidEscapeSequence, InvalidExclusionOperand,
  InvalidRangeEndpoint, InvertedRange, InvertedRepetitionBounds,
  NotSubstitutableBody, SubstitutionsIgnoreMatchingWithoutSubstitutable,
  UnknownAnnotation,
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
// Empty literal errors
// ---------------------------------------------------------------------------

pub fn empty_single_quoted_literal_test() {
  validate("''")
  |> should.equal([EmptyLiteral])
}

pub fn empty_double_quoted_literal_test() {
  validate("\"\"")
  |> should.equal([EmptyLiteral])
}

pub fn empty_literal_in_sequence_test() {
  let errs = validate("'a' '' 'b'")
  errs |> has_error(EmptyLiteral) |> should.be_true
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

pub fn empty_character_set_charclass_test() {
  validate("%Digit excluding %Digit")
  |> should.equal([EmptyCharacterSet])
}

pub fn empty_character_set_single_char_test() {
  validate("'x' excluding 'x'")
  |> should.equal([EmptyCharacterSet])
}

pub fn empty_character_set_range_test() {
  validate("'a'..'z' excluding 'a'..'z'")
  |> should.equal([EmptyCharacterSet])
}

pub fn non_empty_exclusion_different_operands_valid_test() {
  validate("%Digit excluding '0'")
  |> should.equal([])
}

pub fn valid_exclusion_group_literals_test() {
  validate("%Digit excluding ('1'|'3'|'5'|'7'|'9')")
  |> should.equal([])
}

pub fn valid_exclusion_group_single_alt_test() {
  validate("'a'..'z' excluding ('a')")
  |> should.equal([])
}

pub fn valid_exclusion_group_with_range_test() {
  validate("%Alpha excluding ('a'..'e' | 'x')")
  |> should.equal([])
}

pub fn valid_exclusion_group_with_charclass_test() {
  validate("%Any excluding (%Digit | 'x')")
  |> should.equal([])
}

pub fn valid_exclusion_interpolation_test() {
  validate("oddDigit = ('1'|'3'|'5'|'7'|'9');\n%Digit excluding {oddDigit}")
  |> should.equal([])
}

pub fn valid_exclusion_interpolation_flat_body_test() {
  validate("odds = '1'|'3'|'5';\n%Digit excluding {odds}")
  |> should.equal([])
}

pub fn invalid_exclusion_interpolation_non_charset_test() {
  // definition body is a multi-char literal — not a char-set expression
  let errs = validate("greeting = 'hello';\n%Alpha excluding {greeting}")
  errs |> has_error(InvalidExclusionOperand) |> should.be_true
}

pub fn invalid_exclusion_group_multi_item_seq_test() {
  // sequence of two items inside the group → invalid
  let errs = validate("'a'..'z' excluding ('a' 'b')")
  errs |> has_error(InvalidExclusionOperand) |> should.be_true
}

pub fn invalid_exclusion_group_named_capture_test() {
  let errs = validate("%Digit excluding ('1' as d)")
  errs |> has_error(InvalidExclusionOperand) |> should.be_true
}

pub fn invalid_exclusion_group_repetition_test() {
  let errs = validate("%Digit excluding ('1' * 2)")
  errs |> has_error(InvalidExclusionOperand) |> should.be_true
}

pub fn invalid_exclusion_nested_group_test() {
  // group-within-group is blocked
  let errs = validate("%Digit excluding (('1'))")
  errs |> has_error(InvalidExclusionOperand) |> should.be_true
}

pub fn invalid_exclusion_interpolation_operand_test() {
  // definition body is a multi-item sequence — not a char-set expression
  let errs = validate("d = 'a' 'b'; %Alpha excluding {d}")
  errs |> has_error(InvalidExclusionOperand) |> should.be_true
}

pub fn invalid_exclusion_group_interpolation_test() {
  // interpolation inside group → invalid
  let errs = validate("d = '1'; %Digit excluding ({d})")
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
  validate("!replacements-ignore-matching = true\n'x'")
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
  // Captures inside repetitions are now always allowed.
  validate("(%Digit as d) * 3")
  |> should.equal([])
}

pub fn capture_outside_repetition_is_valid_test() {
  validate("%Digit * 3 as d")
  |> should.equal([])
}

pub fn nested_capture_inside_repetition_test() {
  validate("(('a' as inner) * 2) * 3")
  |> should.equal([])
}

// ---------------------------------------------------------------------------
// Position assertions
// ---------------------------------------------------------------------------

pub fn valid_word_start_test() {
  validate("@word-start %Alpha * 1..?")
  |> should.equal([])
}

pub fn valid_word_end_test() {
  validate("%Alpha * 1..? @word-end")
  |> should.equal([])
}

pub fn valid_line_start_test() {
  validate("@line-start %Digit * 1..?")
  |> should.equal([])
}

pub fn valid_line_end_test() {
  validate("%Digit * 1..? @line-end")
  |> should.equal([])
}

pub fn unknown_position_assertion_test() {
  let errs = validate("@start-of-line 'x'")
  errs |> has_error(error.UnknownPositionAssertion("start-of-line")) |> should.be_true
}

pub fn position_assertion_in_repetition_test() {
  let errs = validate("@word-start * 3")
  errs |> has_error(error.PositionAssertionInRepetition("word-start")) |> should.be_true
}

pub fn position_assertion_exact_repetition_test() {
  let errs = validate("@line-end * 1")
  errs |> has_error(error.PositionAssertionInRepetition("line-end")) |> should.be_true
}

pub fn multiline_annotation_valid_test() {
  validate("!multiline = true\n'x'")
  |> should.equal([])
}

// ---------------------------------------------------------------------------
// !substitutable
// ---------------------------------------------------------------------------

pub fn substitutable_literal_valid_test() {
  validate("!substitutable = true\n'hello'")
  |> should.equal([])
}

pub fn substitutable_named_capture_of_class_valid_test() {
  validate("!substitutable = true\n%Digit * 4 as year")
  |> should.equal([])
}

pub fn substitutable_bare_charclass_invalid_test() {
  let errs = validate("!substitutable = true\n%Digit")
  errs |> has_error(NotSubstitutableBody) |> should.be_true
}

pub fn substitutable_bare_charrange_invalid_test() {
  let errs = validate("!substitutable = true\n'a'..'z'")
  errs |> has_error(NotSubstitutableBody) |> should.be_true
}

pub fn substitutable_group_of_literal_valid_test() {
  validate("!substitutable = true\n('hello')")
  |> should.equal([])
}

pub fn substitutable_alternation_all_literal_valid_test() {
  validate("!substitutable = true\n'foo' | 'bar'")
  |> should.equal([])
}

pub fn substitutable_alternation_mixed_invalid_test() {
  let errs = validate("!substitutable = true\n'foo' | %Digit")
  errs |> has_error(NotSubstitutableBody) |> should.be_true
}

pub fn substitutable_sequence_all_literal_valid_test() {
  validate("!substitutable = true\n'hello' ' ' 'world'")
  |> should.equal([])
}

pub fn substitutable_sequence_mixed_invalid_test() {
  let errs = validate("!substitutable = true\n'hello' %Digit")
  errs |> has_error(NotSubstitutableBody) |> should.be_true
}

pub fn substitutable_fixed_rep_of_literal_valid_test() {
  validate("!substitutable = true\n'x' * 3")
  |> should.equal([])
}

pub fn substitutable_bounded_rep_with_capture_valid_test() {
  validate("!substitutable = true\n%Digit * 1..4 as d")
  |> should.equal([])
}

pub fn substitutable_bounded_rep_no_capture_invalid_test() {
  let errs = validate("!substitutable = true\n%Digit * 1..4")
  errs |> has_error(BoundedRepetitionNeedsCapture) |> should.be_true
}

pub fn substitutable_bounded_rep_in_group_with_capture_valid_test() {
  validate("!substitutable = true\n(',' %Digit * 1..4 as d) * 0..10")
  |> should.equal([])
}

pub fn substitutable_capture_in_repetition_allowed_test() {
  validate("!substitutable = true\n%Digit * 4 as n")
  |> should.equal([])
}

pub fn substitutable_interpolation_of_literal_def_valid_test() {
  validate("!substitutable = true\nword = 'hello';\n{word}")
  |> should.equal([])
}

pub fn substitutable_interpolation_of_class_def_invalid_test() {
  let errs = validate("!substitutable = true\ndigits = %Digit * 4;\n{digits}")
  errs |> has_error(NotSubstitutableBody) |> should.be_true
}

pub fn substitutable_interpolation_with_outer_capture_valid_test() {
  validate("!substitutable = true\ndigits = %Digit * 4;\n{digits} as year")
  |> should.equal([])
}

// ---------------------------------------------------------------------------
// !substitutions-ignore-matching
// ---------------------------------------------------------------------------

pub fn substitutions_ignore_matching_requires_substitutable_test() {
  let errs = validate("!substitutions-ignore-matching = true\n'hello'")
  errs
  |> has_error(SubstitutionsIgnoreMatchingWithoutSubstitutable)
  |> should.be_true
}

pub fn substitutions_ignore_matching_with_substitutable_valid_test() {
  validate("!substitutable = true\n!substitutions-ignore-matching = true\n'hello'")
  |> should.equal([])
}

pub fn substitutions_ignore_matching_false_without_substitutable_valid_test() {
  validate("!substitutions-ignore-matching = false\n'hello'")
  |> should.equal([])
}

// Captures inside repetitions are always allowed (not restricted to !substitutable).
pub fn capture_in_repetition_allowed_without_substitutable_test() {
  validate("(%Digit as d) * 3")
  |> should.equal([])
}
