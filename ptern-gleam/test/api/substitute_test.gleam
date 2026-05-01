import gleam/dict
import gleam/list
import gleam/option.{None, Some}
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
    "!substitutable = true\nfield = %Any excluding ',' * 1..100;\n{field} as col (',' {field} as col) * 0..20",
  )
  |> should.be_ok
}

// ---------------------------------------------------------------------------
// substitute — NotSubstitutable
// ---------------------------------------------------------------------------

pub fn substitute_not_substitutable_error_test() {
  let assert Ok(p) = ptern.compile("%Digit * 4 as year")
  ptern.substitute(p, dict.from_list([#("year", ptern.ScalarReplacement("2026"))]))
  |> should.equal(Error(ptern.NotSubstitutable))
}

// ---------------------------------------------------------------------------
// substitute — literal-only pattern
// ---------------------------------------------------------------------------

pub fn substitute_literal_test() {
  let assert Ok(p) = ptern.compile("!substitutable = true\n'hello'")
  ptern.substitute(p, dict.new())
  |> should.equal(Ok("hello"))
}

pub fn substitute_literal_extra_keys_ignored_test() {
  let assert Ok(p) = ptern.compile("!substitutable = true\n'hello'")
  ptern.substitute(p, dict.from_list([#("x", ptern.ScalarReplacement("y"))]))
  |> should.equal(Ok("hello"))
}

// ---------------------------------------------------------------------------
// substitute — scalar capture
// ---------------------------------------------------------------------------

pub fn substitute_scalar_capture_test() {
  let assert Ok(p) = ptern.compile("!substitutable = true\n%Digit * 4 as year")
  ptern.substitute(p, dict.from_list([#("year", ptern.ScalarReplacement("2026"))]))
  |> should.equal(Ok("2026"))
}

pub fn substitute_sequence_of_captures_test() {
  let assert Ok(p) =
    ptern.compile(
      "!substitutable = true\n%Digit * 4 as year '-' %Digit * 2 as month '-' %Digit * 2 as day",
    )
  ptern.substitute(
    p,
    dict.from_list([
      #("year", ptern.ScalarReplacement("2026")),
      #("month", ptern.ScalarReplacement("04")),
      #("day", ptern.ScalarReplacement("28")),
    ]),
  )
  |> should.equal(Ok("2026-04-28"))
}

pub fn substitute_missing_capture_falls_back_to_inner_test() {
  // A PlanCapture whose name is absent evaluates its inner plan.
  // For a literal inner that compiles to a fixed string this means success.
  let assert Ok(p) =
    ptern.compile("!substitutable = true\n'v' %Digit as ver")
  // "ver" is absent — inner is PlanNotEvaluable (char class), so MissingCapture.
  ptern.substitute(p, dict.new())
  |> should.equal(Error(ptern.MissingCapture("ver")))
}

// ---------------------------------------------------------------------------
// substitute — MissingCapture
// ---------------------------------------------------------------------------

pub fn substitute_missing_capture_error_test() {
  let assert Ok(p) = ptern.compile("!substitutable = true\n%Digit * 4 as year")
  ptern.substitute(p, dict.new())
  |> should.equal(Error(ptern.MissingCapture("year")))
}

// ---------------------------------------------------------------------------
// substitute — CaptureMismatch (validation)
// ---------------------------------------------------------------------------

pub fn substitute_capture_mismatch_error_test() {
  let assert Ok(p) = ptern.compile("!substitutable = true\n%Digit * 4 as year")
  ptern.substitute(
    p,
    dict.from_list([#("year", ptern.ScalarReplacement("abcd"))]),
  )
  |> should.equal(Error(ptern.CaptureMismatch("year", "abcd")))
}

pub fn substitute_ignore_matching_skips_validation_test() {
  let assert Ok(p) =
    ptern.compile(
      "!substitutable = true\n!substitutions-ignore-matching = true\n%Digit * 4 as year",
    )
  ptern.substitute(
    p,
    dict.from_list([#("year", ptern.ScalarReplacement("YYYY"))]),
  )
  |> should.equal(Ok("YYYY"))
}

// ---------------------------------------------------------------------------
// substitute — alternation (NoMatchingBranch)
// ---------------------------------------------------------------------------

pub fn substitute_alternation_first_branch_test() {
  let assert Ok(p) =
    ptern.compile(
      "!substitutable = true\n%Digit * 4 as year | %Alpha * 1..? as word",
    )
  ptern.substitute(
    p,
    dict.from_list([#("year", ptern.ScalarReplacement("2026"))]),
  )
  |> should.equal(Ok("2026"))
}

pub fn substitute_alternation_second_branch_test() {
  let assert Ok(p) =
    ptern.compile(
      "!substitutable = true\n%Digit * 4 as year | %Alpha * 1..? as word",
    )
  ptern.substitute(
    p,
    dict.from_list([#("word", ptern.ScalarReplacement("hello"))]),
  )
  |> should.equal(Ok("hello"))
}

pub fn substitute_no_matching_branch_error_test() {
  let assert Ok(p) =
    ptern.compile(
      "!substitutable = true\n%Digit * 4 as year | %Alpha * 1..? as word",
    )
  ptern.substitute(p, dict.new())
  |> should.equal(Error(ptern.NoMatchingBranch))
}

// ---------------------------------------------------------------------------
// substitute — fixed repetition
// ---------------------------------------------------------------------------

pub fn substitute_fixed_rep_scalar_test() {
  let assert Ok(p) =
    ptern.compile(
      "!substitutable = true\n(%Digit as d) * 3",
    )
  ptern.substitute(
    p,
    dict.from_list([#("d", ptern.ScalarReplacement("7"))]),
  )
  |> should.equal(Ok("777"))
}

pub fn substitute_fixed_rep_array_test() {
  let assert Ok(p) =
    ptern.compile(
      "!substitutable = true\n(%Digit as d) * 3",
    )
  ptern.substitute(
    p,
    dict.from_list([#("d", ptern.ArrayReplacement(["1", "2", "3"]))]),
  )
  |> should.equal(Ok("123"))
}

// ---------------------------------------------------------------------------
// substitute — bounded repetition
// ---------------------------------------------------------------------------

pub fn substitute_bounded_rep_array_test() {
  let assert Ok(p) =
    ptern.compile(
      "!substitutable = true\nfield = %Any excluding ',' * 1..20;\n{field} as col (',' {field} as col) * 0..5",
    )
  ptern.substitute(
    p,
    dict.from_list([
      #("col", ptern.ArrayReplacement(["alice", "bob", "carol"])),
    ]),
  )
  |> should.equal(Ok("alice,bob,carol"))
}

pub fn substitute_bounded_rep_min_zero_no_array_test() {
  // min=0, no array capture provided → zero iterations, empty repetition.
  let assert Ok(p) =
    ptern.compile(
      "!substitutable = true\n'[' (%Digit as d ',' ) * 0..5 ']'",
    )
  ptern.substitute(p, dict.from_list([#("d", ptern.ArrayReplacement([]))]))
  |> should.equal(Ok("[]"))
}

// ---------------------------------------------------------------------------
// substitute — ArrayLengthError
// ---------------------------------------------------------------------------

pub fn substitute_array_length_below_min_error_test() {
  let assert Ok(p) =
    ptern.compile(
      "!substitutable = true\n(%Digit as d) * 3..5",
    )
  // Providing only 2 elements when min is 3.
  ptern.substitute(
    p,
    dict.from_list([#("d", ptern.ArrayReplacement(["1", "2"]))]),
  )
  |> should.equal(Error(ptern.ArrayLengthError("d", 2, 3, Some(5))))
}

pub fn substitute_array_length_above_max_error_test() {
  let assert Ok(p) =
    ptern.compile(
      "!substitutable = true\n(%Digit as d) * 1..3",
    )
  // Providing 5 elements when max is 3.
  ptern.substitute(
    p,
    dict.from_list([
      #("d", ptern.ArrayReplacement(["1", "2", "3", "4", "5"])),
    ]),
  )
  |> should.equal(Error(ptern.ArrayLengthError("d", 5, 1, Some(3))))
}

// ---------------------------------------------------------------------------
// substitute — subpattern definitions
// ---------------------------------------------------------------------------

pub fn substitute_with_definition_test() {
  let assert Ok(p) =
    ptern.compile(
      "!substitutable = true\nyyyy = %Digit * 4;\nmm = %Digit * 2;\ndd = %Digit * 2;\n{yyyy} as year '-' {mm} as month '-' {dd} as day",
    )
  ptern.substitute(
    p,
    dict.from_list([
      #("year", ptern.ScalarReplacement("2026")),
      #("month", ptern.ScalarReplacement("04")),
      #("day", ptern.ScalarReplacement("28")),
    ]),
  )
  |> should.equal(Ok("2026-04-28"))
}

// ---------------------------------------------------------------------------
// substitute — duplicate capture name (same value at every position)
// ---------------------------------------------------------------------------

pub fn substitute_duplicate_capture_name_test() {
  let assert Ok(p) =
    ptern.compile(
      "!substitutable = true\nword = %Alpha * 1..20;\n'<' {word} as tag '>' {word} as body '</' {word} as tag '>'",
    )
  ptern.substitute(
    p,
    dict.from_list([
      #("tag", ptern.ScalarReplacement("em")),
      #("body", ptern.ScalarReplacement("hello")),
    ]),
  )
  |> should.equal(Ok("<em>hello</em>"))
}

// ---------------------------------------------------------------------------
// substitute — array capture consumed positionally
// ---------------------------------------------------------------------------

pub fn substitute_array_capture_consumed_in_order_test() {
  let assert Ok(p) =
    ptern.compile(
      "!substitutable = true\n(%Alpha * 1..? as w ' ') * 1..4",
    )
  ptern.substitute(
    p,
    dict.from_list([
      #("w", ptern.ArrayReplacement(["one", "two", "three"])),
    ]),
  )
  |> should.equal(Ok("one two three "))
}

// ---------------------------------------------------------------------------
// substitute — array CaptureMismatch (validation of individual elements)
// ---------------------------------------------------------------------------

pub fn substitute_array_element_mismatch_error_test() {
  let assert Ok(p) =
    ptern.compile("!substitutable = true\n(%Digit as d) * 3")
  ptern.substitute(
    p,
    dict.from_list([#("d", ptern.ArrayReplacement(["1", "x", "3"]))]),
  )
  |> should.equal(Error(ptern.CaptureMismatch("d", "x")))
}

// ---------------------------------------------------------------------------
// substitute — unbounded repetition (min..?)
// ---------------------------------------------------------------------------

pub fn substitute_unbounded_rep_test() {
  let assert Ok(p) =
    ptern.compile(
      "!substitutable = true\n(%Alpha * 1..? as w ' ') * 1..?",
    )
  ptern.substitute(
    p,
    dict.from_list([
      #("w", ptern.ArrayReplacement(["a", "bb", "ccc"])),
    ]),
  )
  |> should.equal(Ok("a bb ccc "))
}

pub fn substitute_unbounded_rep_array_length_no_upper_bound_test() {
  // max=None means no upper bound — any length >= min is accepted.
  let assert Ok(p) =
    ptern.compile(
      "!substitutable = true\n(%Digit as d) * 1..?",
    )
  ptern.substitute(
    p,
    dict.from_list([#("d", ptern.ArrayReplacement(["1", "2", "3", "4", "5"]))]),
  )
  |> should.equal(Ok("12345"))
}

pub fn substitute_unbounded_rep_below_min_error_test() {
  let assert Ok(p) =
    ptern.compile("!substitutable = true\n(%Digit as d) * 3..?")
  ptern.substitute(
    p,
    dict.from_list([#("d", ptern.ArrayReplacement(["1", "2"]))]),
  )
  |> should.equal(Error(ptern.ArrayLengthError("d", 2, 3, None)))
}

// ---------------------------------------------------------------------------
// substitute — empty string values
// ---------------------------------------------------------------------------

pub fn substitute_empty_scalar_validates_mismatch_test() {
  let assert Ok(p) = ptern.compile("!substitutable = true\n%Digit * 4 as year")
  ptern.substitute(
    p,
    dict.from_list([#("year", ptern.ScalarReplacement(""))]),
  )
  |> should.equal(Error(ptern.CaptureMismatch("year", "")))
}

pub fn substitute_empty_scalar_ignore_matching_test() {
  let assert Ok(p) =
    ptern.compile(
      "!substitutable = true\n!substitutions-ignore-matching = true\n'[' %Digit as d ']'",
    )
  ptern.substitute(
    p,
    dict.from_list([#("d", ptern.ScalarReplacement(""))]),
  )
  |> should.equal(Ok("[]"))
}

pub fn substitute_empty_array_element_ignore_matching_test() {
  let assert Ok(p) =
    ptern.compile(
      "!substitutable = true\n!substitutions-ignore-matching = true\n(%Digit as d) * 3",
    )
  ptern.substitute(
    p,
    dict.from_list([#("d", ptern.ArrayReplacement(["1", "", "3"]))]),
  )
  |> should.equal(Ok("13"))
}
