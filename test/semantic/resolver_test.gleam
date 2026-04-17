import gleeunit/should
import lexer/lexer
import parser/parser
import semantic/error.{
  CaptureDefinitionConflict, CircularDefinition, DuplicateCapture,
  DuplicateDefinition, UndefinedReference,
}
import semantic/resolver

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn resolve(input: String) -> List(error.SemanticError) {
  let assert Ok(tokens) = lexer.lex(input)
  let assert Ok(ptern) = parser.parse(tokens)
  resolver.resolve(ptern)
}

fn has_error(errs: List(error.SemanticError), target: error.SemanticError) -> Bool {
  case errs {
    [] -> False
    [e, ..rest] -> e == target || has_error(rest, target)
  }
}

// ---------------------------------------------------------------------------
// No errors — valid patterns
// ---------------------------------------------------------------------------

pub fn no_errors_simple_literal_test() {
  resolve("'hello'")
  |> should.equal([])
}

pub fn no_errors_with_definition_test() {
  resolve("d = %Digit; {d}")
  |> should.equal([])
}

pub fn no_errors_multiple_definitions_test() {
  resolve("a = 'x'; b = 'y'; {a} {b}")
  |> should.equal([])
}

pub fn no_errors_body_capture_test() {
  resolve("%Digit * 4 as year")
  |> should.equal([])
}

pub fn no_errors_definition_reference_in_body_test() {
  resolve("d = %Digit * 4; {d} as year")
  |> should.equal([])
}

// ---------------------------------------------------------------------------
// Duplicate definitions
// ---------------------------------------------------------------------------

pub fn duplicate_definition_test() {
  let errs = resolve("foo = 'a'; foo = 'b'; {foo}")
  errs |> has_error(DuplicateDefinition("foo")) |> should.be_true
}

pub fn duplicate_definition_three_times_test() {
  let errs = resolve("d = 'a'; d = 'b'; d = 'c'; {d}")
  // Only one error per duplicated name.
  errs |> has_error(DuplicateDefinition("d")) |> should.be_true
}

// ---------------------------------------------------------------------------
// Circular definitions
// ---------------------------------------------------------------------------

pub fn circular_self_reference_test() {
  let errs = resolve("a = {a}; {a}")
  errs |> has_error(CircularDefinition(["a"])) |> should.be_true
}

pub fn circular_two_node_cycle_test() {
  let errs = resolve("a = {b}; b = {a}; {a}")
  errs |> has_error(CircularDefinition(["a", "b"])) |> should.be_true
}

pub fn no_circular_with_chain_test() {
  resolve("a = 'x'; b = {a}; {b}")
  |> should.equal([])
}

// ---------------------------------------------------------------------------
// Undefined references
// ---------------------------------------------------------------------------

pub fn undefined_interpolation_in_body_test() {
  let errs = resolve("{foo}")
  errs |> should.equal([UndefinedReference("foo")])
}

pub fn undefined_interpolation_in_definition_test() {
  let errs = resolve("a = {missing}; {a}")
  errs |> has_error(UndefinedReference("missing")) |> should.be_true
}

pub fn backreference_to_capture_is_valid_test() {
  // {year} here is a backreference to the capture established by `as year`
  resolve("%Digit * 4 as year '-' {year}")
  |> should.equal([])
}

// ---------------------------------------------------------------------------
// Duplicate captures
// ---------------------------------------------------------------------------

pub fn duplicate_capture_in_body_test() {
  let errs = resolve("%Digit * 4 as year '-' %Digit * 2 as year")
  errs |> should.equal([DuplicateCapture("year")])
}

pub fn duplicate_capture_three_times_test() {
  let errs = resolve("'a' as x '-' 'b' as x '-' 'c' as x")
  errs |> has_error(DuplicateCapture("x")) |> should.be_true
}

// ---------------------------------------------------------------------------
// Capture / definition name conflict
// ---------------------------------------------------------------------------

pub fn capture_matches_definition_name_test() {
  let errs = resolve("year = %Digit * 4; {year} as year")
  errs |> has_error(CaptureDefinitionConflict("year")) |> should.be_true
}

pub fn capture_inside_definition_matches_definition_name_test() {
  let errs = resolve("year = %Digit * 4 as year; {year}")
  errs |> has_error(CaptureDefinitionConflict("year")) |> should.be_true
}

// ---------------------------------------------------------------------------
// Multiple independent errors collected together
// ---------------------------------------------------------------------------

pub fn multiple_errors_collected_test() {
  // Two undefined refs and one duplicate definition
  let errs = resolve("d = 'a'; d = 'b'; {x} {y}")
  errs |> has_error(DuplicateDefinition("d")) |> should.be_true
  errs |> has_error(UndefinedReference("x")) |> should.be_true
  errs |> has_error(UndefinedReference("y")) |> should.be_true
}
