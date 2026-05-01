import gleam/list
import gleeunit/should
import ptern
import semantic/error

fn has_error(
  result: Result(ptern.Ptern, ptern.CompileError),
  target: error.SemanticError,
) -> Bool {
  case result {
    Error(ptern.SemanticErrors(errs)) -> list.any(errs, fn(e) { e == target })
    _ -> False
  }
}

// ---------------------------------------------------------------------------
// Check 1: AmbiguousRepetitionAdjacency — pairwise branches of a variable-count
// repetition whose last/first charsets overlap.
// ---------------------------------------------------------------------------

pub fn check1_digit_alpha_branches_are_disjoint_test() {
  // %Digit and %Alpha are disjoint — no error.
  ptern.compile("(%Digit | %Alpha) * 1..?")
  |> should.be_ok
}

pub fn check1_overlapping_literal_branches_test() {
  // 'a' and 'ab': last('a') = 'a', first('ab') = 'a', they overlap.
  ptern.compile("('a' | 'ab') * 1..?")
  |> has_error(error.AmbiguousRepetitionAdjacency(branch_a: "'a'", branch_b: "'ab'"))
  |> should.be_true
}

pub fn check1_same_class_branches_overlap_test() {
  // Two branches drawn from the same class share charsets.
  ptern.compile("(%Digit | %Digit) * 1..?")
  |> has_error(error.AmbiguousRepetitionAdjacency(
    branch_a: "%Digit",
    branch_b: "%Digit",
  ))
  |> should.be_true
}

pub fn check1_exact_count_no_check_test() {
  // Exact repetition (* 3) is not variable — Check 1 does not apply.
  ptern.compile("('a' | 'b') * 3")
  |> should.be_ok
}

pub fn check1_upper_lower_disjoint_test() {
  // %Upper and %Lower are disjoint.
  ptern.compile("(%Upper | %Lower) * 1..?")
  |> should.be_ok
}

pub fn check1_letter_underscore_disjoint_test() {
  // Letters and underscore are disjoint.
  ptern.compile("(%Alpha | '_') * 1..?")
  |> should.be_ok
}

pub fn check1_l_n_disjoint_test() {
  // %L (Unicode letters) and %N (Unicode numbers) are disjoint.
  ptern.compile("(%L | %N) * 1..?")
  |> should.be_ok
}

pub fn check1_multichar_literal_last_first_overlap_test() {
  // last('xy') = 'y', first('yz') = 'y' — overlap at the iteration boundary.
  ptern.compile("('xy' | 'yz') * 1..?")
  |> has_error(error.AmbiguousRepetitionAdjacency(branch_a: "'xy'", branch_b: "'yz'"))
  |> should.be_true
}

pub fn check1_multichar_literal_no_overlap_test() {
  // last('ab') = 'b', first('cd') = 'c' — disjoint.
  ptern.compile("('ab' | 'cd') * 1..?")
  |> should.be_ok
}

pub fn check1_excl_set_covers_excluded_char_test() {
  // %Alpha excluding 'a' and 'a': the excluded char is provably absent from the
  // ExclSet, so last(branch0) ∩ first(branch1) = ∅ in both directions.
  ptern.compile("(%Alpha excluding 'a' | 'a') * 1..?")
  |> should.be_ok
}

pub fn check1_three_branch_one_overlapping_pair_test() {
  // Three branches; only the ('a', 'ab') pair overlaps — error is still reported.
  ptern.compile("('a' | 'b' | 'ab') * 1..?")
  |> has_error(error.AmbiguousRepetitionAdjacency(branch_a: "'a'", branch_b: "'ab'"))
  |> should.be_true
}

pub fn check1_bounded_variable_range_triggers_check_test() {
  // * 2..5 is variable (n < m) — Check 1 applies just like * 1..?
  ptern.compile("('a' | 'ab') * 2..5")
  |> has_error(error.AmbiguousRepetitionAdjacency(branch_a: "'a'", branch_b: "'ab'"))
  |> should.be_true
}

// ---------------------------------------------------------------------------
// Check 2: AmbiguousRepetitionBody — body is variable-length and last/first
// charsets of the body overlap across iterations.
// ---------------------------------------------------------------------------

pub fn check2_variable_body_same_class_test() {
  // %Alpha * 1..? as body of outer rep: last=%Alpha, first=%Alpha — same class.
  ptern.compile("(%Alpha * 1..?) * 1..?")
  |> has_error(error.AmbiguousRepetitionBody)
  |> should.be_true
}

pub fn check2_disjoint_endpoints_no_error_test() {
  // Body 'x' %Digit * 1..?: first='x', last=%Digit — disjoint.
  ptern.compile("('x' %Digit * 1..?) * 1..?")
  |> should.be_ok
}

pub fn check2_fixed_length_body_no_error_test() {
  // Body %Digit (fixed length 1) — no body self-ambiguity possible.
  ptern.compile("(%Digit) * 1..?")
  |> should.be_ok
}

pub fn check2_fixed_length_alt_body_no_error_test() {
  // Body (%L | %N | '_') is fixed length 1 despite being alternation.
  ptern.compile("((%L | %N | '_') * 1..?) * 1..?")
  |> has_error(error.AmbiguousRepetitionBody)
  |> should.be_true
}

pub fn check2_excl_body_overlaps_itself_test() {
  // (%Any excluding ',') * 1..? is variable-length; non-comma chars overlap
  // non-comma chars across iterations.
  ptern.compile("((%Any excluding ',') * 1..?) * 1..?")
  |> has_error(error.AmbiguousRepetitionBody)
  |> should.be_true
}

pub fn check2_separator_makes_excl_body_safe_test() {
  // Body ',' (%Any excluding ',') * 1..?: first=',', last=ExclSet(Any,',').
  // ',' is provably absent from ExclSet(Any,',') so the endpoints are disjoint.
  ptern.compile("(',' (%Any excluding ',') * 1..?) * 1..?")
  |> should.be_ok
}

pub fn check2_nullable_inner_rep_test() {
  // %Digit * 0..? is nullable and variable-length; digit chars overlap across
  // iterations.
  ptern.compile("(%Digit * 0..?) * 1..?")
  |> has_error(error.AmbiguousRepetitionBody)
  |> should.be_true
}

// ---------------------------------------------------------------------------
// Check 4: AmbiguousAdjacentRepetition — two consecutive unbounded repetitions
// whose last/first charsets overlap.
// ---------------------------------------------------------------------------

pub fn check4_adjacent_same_class_test() {
  ptern.compile("%Digit * 1..? %Digit * 1..?")
  |> has_error(error.AmbiguousAdjacentRepetition)
  |> should.be_true
}

pub fn check4_adjacent_disjoint_test() {
  // %Upper * 1..? followed by %Lower * 1..? — disjoint.
  ptern.compile("%Upper * 1..? %Lower * 1..?")
  |> should.be_ok
}

pub fn check4_separator_between_prevents_error_test() {
  // A literal separator between two unbounded reps means they are not adjacent.
  ptern.compile("%Digit * 1..? '-' %Digit * 1..?")
  |> should.be_ok
}

pub fn check4_bounded_not_adjacent_unbounded_test() {
  // * 1..5 is bounded, not unbounded — Check 4 does not apply.
  ptern.compile("%Alpha * 1..5 %Alpha * 1..?")
  |> should.be_ok
}

pub fn check4_excl_class_makes_adjacent_reps_disjoint_test() {
  // last(%Digit) ∩ first(%Any excluding %Digit) = ∅ because %Digit ⊆ %Digit
  // (the excluded class), so no digit appears in ExclSet(Any, Digit).
  ptern.compile("%Digit * 1..? (%Any excluding %Digit) * 1..?")
  |> should.be_ok
}

pub fn check4_zero_lower_bound_is_still_unbounded_test() {
  // * 0..? has no upper bound — Check 4 applies identically to * 1..?
  ptern.compile("%Alpha * 0..? %Alpha * 1..?")
  |> has_error(error.AmbiguousAdjacentRepetition)
  |> should.be_true
}

// ---------------------------------------------------------------------------
// !allow-backtracking = true — global opt-out
// ---------------------------------------------------------------------------

pub fn allow_backtracking_suppresses_all_checks_test() {
  ptern.compile(
    "!allow-backtracking = true\n(%Alpha * 1..?) * 1..? %Alpha * 1..?",
  )
  |> should.be_ok
}

pub fn allow_backtracking_false_still_checks_test() {
  ptern.compile("!allow-backtracking = false\n(%Alpha * 1..?) * 1..?")
  |> has_error(error.AmbiguousRepetitionBody)
  |> should.be_true
}
