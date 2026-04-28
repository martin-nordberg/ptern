import gleam/list
import gleeunit/should
import ptern
import semantic/error

fn has_semantic_error(
  result: Result(ptern.Ptern, ptern.CompileError),
  target: error.SemanticError,
) -> Bool {
  case result {
    Error(ptern.SemanticErrors(errs)) -> list.any(errs, fn(e) { e == target })
    _ -> False
  }
}

// ---------------------------------------------------------------------------
// Substitution — compile-time errors
// ---------------------------------------------------------------------------

pub fn substitutable_bare_charclass_error_test() {
  ptern.compile("!substitutable = true\n%Digit")
  |> has_semantic_error(error.NotSubstitutableBody)
  |> should.be_true
}

pub fn substitutions_ignore_matching_without_substitutable_error_test() {
  ptern.compile("!substitutions-ignore-matching = true\n'hello'")
  |> has_semantic_error(error.SubstitutionsIgnoreMatchingWithoutSubstitutable)
  |> should.be_true
}

pub fn substitutable_bounded_rep_no_capture_error_test() {
  ptern.compile("!substitutable = true\n%Digit * 1..4")
  |> has_semantic_error(error.BoundedRepetitionNeedsCapture)
  |> should.be_true
}

pub fn substitutable_compiles_ok_literal_test() {
  ptern.compile("!substitutable = true\n'hello'")
  |> should.be_ok
}

pub fn substitutable_compiles_ok_named_capture_test() {
  ptern.compile("!substitutable = true\n%Digit * 4 as year")
  |> should.be_ok
}

pub fn substitutable_compiles_ok_bounded_with_capture_test() {
  ptern.compile("!substitutable = true\n%Any * 1..100 as field")
  |> should.be_ok
}

pub fn substitutable_compiles_ok_with_ignore_matching_test() {
  ptern.compile(
    "!substitutable = true\n!substitutions-ignore-matching = true\n'hello'",
  )
  |> should.be_ok
}

pub fn substitutable_compiles_ok_duplicate_captures_test() {
  ptern.compile(
    "!substitutable = true\nword = %Alpha * 1..20;\n'<' {word} as tag '>' {word} as body '</' {word} as tag '>'",
  )
  |> should.be_ok
}

pub fn substitutable_compiles_ok_iso_date_test() {
  ptern.compile(
    "!substitutable = true\nyyyy = %Digit * 4;\nmm = '0' '1'..'9' | '1' '0'..'2';\ndd = '0' '1'..'9' | '1'..'2' %Digit | '3' '0'..'1';\n{yyyy} as year '-' {mm} as month '-' {dd} as day",
  )
  |> should.be_ok
}

pub fn substitutable_compiles_ok_csv_test() {
  ptern.compile(
    "!substitutable = true\nfield = %Any * 1..100;\n{field} as col (',' {field} as col) * 0..20",
  )
  |> should.be_ok
}
