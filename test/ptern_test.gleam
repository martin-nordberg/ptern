import gleam/option.{None, Some}
import gleeunit
import gleeunit/should
import ptern.{LexError, SemanticErrors}

pub fn main() {
  gleeunit.main()
}

// ---------------------------------------------------------------------------
// Compile — success cases
// ---------------------------------------------------------------------------

pub fn compile_simple_literal_test() {
  ptern.compile("'hello'")
  |> should.be_ok
}

pub fn compile_returns_source_test() {
  let assert Ok(p) = ptern.compile("'hello'")
  p.source |> should.equal("hello")
}

pub fn compile_default_flags_test() {
  let assert Ok(p) = ptern.compile("'hello'")
  p.flags |> should.equal("v")
}

pub fn compile_case_insensitive_flag_test() {
  let assert Ok(p) = ptern.compile("@case-insensitive = true\n'hello'")
  p.flags |> should.equal("vi")
}

// ---------------------------------------------------------------------------
// Length bounds
// ---------------------------------------------------------------------------

pub fn min_length_literal_test() {
  let assert Ok(p) = ptern.compile("'hello'")
  p.min_length |> should.equal(5)
}

pub fn max_length_literal_test() {
  let assert Ok(p) = ptern.compile("'hello'")
  p.max_length |> should.equal(Some(5))
}

pub fn min_length_digit_test() {
  let assert Ok(p) = ptern.compile("%Digit")
  p.min_length |> should.equal(1)
}

pub fn max_length_digit_test() {
  let assert Ok(p) = ptern.compile("%Digit")
  p.max_length |> should.equal(Some(1))
}

pub fn min_length_exact_repetition_test() {
  let assert Ok(p) = ptern.compile("%Digit * 4")
  p.min_length |> should.equal(4)
}

pub fn max_length_exact_repetition_test() {
  let assert Ok(p) = ptern.compile("%Digit * 4")
  p.max_length |> should.equal(Some(4))
}

pub fn min_length_bounded_repetition_test() {
  let assert Ok(p) = ptern.compile("%Digit * 2..5")
  p.min_length |> should.equal(2)
}

pub fn max_length_bounded_repetition_test() {
  let assert Ok(p) = ptern.compile("%Digit * 2..5")
  p.max_length |> should.equal(Some(5))
}

pub fn max_length_unbounded_repetition_test() {
  let assert Ok(p) = ptern.compile("%Digit * 1..?")
  p.max_length |> should.equal(None)
}

pub fn min_length_unbounded_repetition_test() {
  let assert Ok(p) = ptern.compile("%Digit * 1..?")
  p.min_length |> should.equal(1)
}

pub fn min_length_optional_is_zero_test() {
  let assert Ok(p) = ptern.compile("%Digit * 0..1")
  p.min_length |> should.equal(0)
}

pub fn max_length_optional_is_one_test() {
  let assert Ok(p) = ptern.compile("%Digit * 0..1")
  p.max_length |> should.equal(Some(1))
}

pub fn min_length_sequence_test() {
  let assert Ok(p) = ptern.compile("'ab' %Digit")
  p.min_length |> should.equal(3)
}

pub fn max_length_sequence_test() {
  let assert Ok(p) = ptern.compile("'ab' %Digit")
  p.max_length |> should.equal(Some(3))
}

pub fn min_length_alternation_test() {
  let assert Ok(p) = ptern.compile("'a' | 'bcd'")
  p.min_length |> should.equal(1)
}

pub fn max_length_alternation_test() {
  let assert Ok(p) = ptern.compile("'a' | 'bcd'")
  p.max_length |> should.equal(Some(3))
}

pub fn max_length_alternation_with_unbounded_test() {
  let assert Ok(p) = ptern.compile("'a' | %Digit * 1..?")
  p.max_length |> should.equal(None)
}

pub fn min_length_definition_interpolation_test() {
  let assert Ok(p) = ptern.compile("d = %Digit * 4; {d}")
  p.min_length |> should.equal(4)
}

pub fn max_length_definition_interpolation_test() {
  let assert Ok(p) = ptern.compile("d = %Digit * 4; {d}")
  p.max_length |> should.equal(Some(4))
}

// ---------------------------------------------------------------------------
// Compile — failure cases
// ---------------------------------------------------------------------------

pub fn compile_lex_error_test() {
  case ptern.compile("'unterminated") {
    Error(LexError(_)) -> Nil
    _ -> should.fail()
  }
}

pub fn compile_semantic_error_test() {
  case ptern.compile("{missing}") {
    Error(SemanticErrors(_)) -> Nil
    _ -> should.fail()
  }
}
