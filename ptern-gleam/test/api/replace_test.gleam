import gleam/dict
import gleam/option.{Some}
import gleeunit/should
import ptern

// ---------------------------------------------------------------------------
// replace_all_of / replace_start_of / replace_end_of
// replace_first_in / replace_next_in / replace_all_in
// ---------------------------------------------------------------------------

pub fn replace_all_of_basic_test() {
  let assert Ok(p) = ptern.compile("%Digit * 4 as year")
  ptern.replace_all_of(
    p,
    "2026",
    dict.from_list([#("year", ptern.ScalarReplacement("2027"))]),
  )
  |> should.equal(Ok("2027"))
}

pub fn replace_all_of_no_match_test() {
  let assert Ok(p) = ptern.compile("%Digit * 4 as year")
  ptern.replace_all_of(
    p,
    "2026 extra",
    dict.from_list([#("year", ptern.ScalarReplacement("2027"))]),
  )
  |> should.equal(Ok("2026 extra"))
}

pub fn replace_start_of_basic_test() {
  let assert Ok(p) = ptern.compile("%Digit * 4 as year")
  ptern.replace_start_of(
    p,
    "2026 is the year",
    dict.from_list([#("year", ptern.ScalarReplacement("2027"))]),
  )
  |> should.equal(Ok("2027 is the year"))
}

pub fn replace_start_of_no_match_test() {
  let assert Ok(p) = ptern.compile("%Digit * 4 as year")
  ptern.replace_start_of(
    p,
    "the year is 2026",
    dict.from_list([#("year", ptern.ScalarReplacement("2027"))]),
  )
  |> should.equal(Ok("the year is 2026"))
}

pub fn replace_end_of_basic_test() {
  let assert Ok(p) = ptern.compile("%Digit * 4 as year")
  ptern.replace_end_of(
    p,
    "the year is 2026",
    dict.from_list([#("year", ptern.ScalarReplacement("2027"))]),
  )
  |> should.equal(Ok("the year is 2027"))
}

pub fn replace_end_of_no_match_test() {
  let assert Ok(p) = ptern.compile("%Digit * 4 as year")
  ptern.replace_end_of(
    p,
    "2026 is the year",
    dict.from_list([#("year", ptern.ScalarReplacement("2027"))]),
  )
  |> should.equal(Ok("2026 is the year"))
}

pub fn replace_first_in_basic_test() {
  let assert Ok(p) =
    ptern.compile("!replacements-ignore-matching = true\n%Digit * 4 as year")
  ptern.replace_first_in(
    p,
    "event in 2026, repeated in 2025",
    dict.from_list([#("year", ptern.ScalarReplacement("YYYY"))]),
  )
  |> should.equal(Ok("event in YYYY, repeated in 2025"))
}

pub fn replace_first_in_no_match_test() {
  let assert Ok(p) =
    ptern.compile("!replacements-ignore-matching = true\n%Digit * 4 as year")
  ptern.replace_first_in(
    p,
    "no digits here",
    dict.from_list([#("year", ptern.ScalarReplacement("YYYY"))]),
  )
  |> should.equal(Ok("no digits here"))
}

pub fn replace_next_in_basic_test() {
  let assert Ok(p) =
    ptern.compile("!replacements-ignore-matching = true\n%Digit * 4 as year")
  ptern.replace_next_in(
    p,
    "2026 and 2025",
    7,
    dict.from_list([#("year", ptern.ScalarReplacement("YYYY"))]),
  )
  |> should.equal(Ok("2026 and YYYY"))
}

pub fn replace_next_in_no_match_test() {
  let assert Ok(p) =
    ptern.compile("!replacements-ignore-matching = true\n%Digit * 4 as year")
  ptern.replace_next_in(
    p,
    "2026",
    1,
    dict.from_list([#("year", ptern.ScalarReplacement("YYYY"))]),
  )
  |> should.equal(Ok("2026"))
}

pub fn replace_all_in_basic_test() {
  let assert Ok(p) =
    ptern.compile("!replacements-ignore-matching = true\n%Digit * 4 as year")
  ptern.replace_all_in(
    p,
    "2026 and 2025",
    dict.from_list([#("year", ptern.ScalarReplacement("YYYY"))]),
  )
  |> should.equal(Ok("YYYY and YYYY"))
}

pub fn replace_all_in_no_match_test() {
  let assert Ok(p) =
    ptern.compile("!replacements-ignore-matching = true\n%Digit * 4 as year")
  ptern.replace_all_in(
    p,
    "no digits here",
    dict.from_list([#("year", ptern.ScalarReplacement("YYYY"))]),
  )
  |> should.equal(Ok("no digits here"))
}

pub fn replace_multiple_captures_test() {
  let assert Ok(p) = ptern.compile("%Digit * 4 as year '-' %Digit * 2 as month")
  ptern.replace_first_in(
    p,
    "date: 2026-07",
    dict.from_list([
      #("year", ptern.ScalarReplacement("2027")),
      #("month", ptern.ScalarReplacement("12")),
    ]),
  )
  |> should.equal(Ok("date: 2027-12"))
}

pub fn replace_all_in_multiple_captures_test() {
  let assert Ok(p) =
    ptern.compile(
      "!replacements-ignore-matching = true\n%Digit * 4 as year '-' %Digit * 2 as month",
    )
  ptern.replace_all_in(
    p,
    "2026-07 and 2025-03",
    dict.from_list([
      #("year", ptern.ScalarReplacement("YYYY")),
      #("month", ptern.ScalarReplacement("MM")),
    ]),
  )
  |> should.equal(Ok("YYYY-MM and YYYY-MM"))
}

// ---------------------------------------------------------------------------
// !replacements-ignore-matching
// ---------------------------------------------------------------------------

pub fn replacement_validates_by_default_valid_test() {
  let assert Ok(p) = ptern.compile("%Digit * 4 as year")
  ptern.replace_first_in(
    p,
    "event 2026",
    dict.from_list([#("year", ptern.ScalarReplacement("2027"))]),
  )
  |> should.equal(Ok("event 2027"))
}

pub fn replacement_validates_by_default_invalid_test() {
  let assert Ok(p) = ptern.compile("%Digit * 4 as year")
  ptern.replace_first_in(
    p,
    "event 2026",
    dict.from_list([#("year", ptern.ScalarReplacement("202"))]),
  )
  |> should.equal(Error(ptern.InvalidReplacementValue("year", "202")))
}

pub fn ignore_matching_annotation_skips_validation_test() {
  let assert Ok(p) =
    ptern.compile("!replacements-ignore-matching = true\n%Digit * 4 as year")
  ptern.replace_first_in(
    p,
    "event 2026",
    dict.from_list([#("year", ptern.ScalarReplacement("abc"))]),
  )
  |> should.equal(Ok("event abc"))
}

pub fn replacement_validates_interpolated_capture_test() {
  let assert Ok(p) =
    ptern.compile("yyyy = %Digit * 4;\n{yyyy} as year")
  ptern.replace_first_in(
    p,
    "2026",
    dict.from_list([#("year", ptern.ScalarReplacement("2027"))]),
  )
  |> should.equal(Ok("2027"))
  ptern.replace_first_in(
    p,
    "2026",
    dict.from_list([#("year", ptern.ScalarReplacement("abc"))]),
  )
  |> should.equal(Error(ptern.InvalidReplacementValue("year", "abc")))
}

pub fn replacement_validation_case_insensitive_flag_propagated_test() {
  let assert Ok(p) =
    ptern.compile("!case-insensitive = true\n'a'..'z' * 4 as word")
  ptern.replace_first_in(
    p,
    "stop",
    dict.from_list([#("word", ptern.ScalarReplacement("HALT"))]),
  )
  |> should.equal(Ok("HALT"))
}

// ---------------------------------------------------------------------------
// Array replacement (captures inside repetitions)
// ---------------------------------------------------------------------------

pub fn array_replace_fixed_repetition_test() {
  let assert Ok(p) =
    ptern.compile("!replacements-ignore-matching = true\n(%Digit * 4 as yr) * 3")
  ptern.replace_first_in(
    p,
    "202420252026",
    dict.from_list([
      #("yr", ptern.ArrayReplacement(["A", "B", "C"])),
    ]),
  )
  |> should.equal(Ok("ABC"))
}

pub fn array_replace_bounded_repetition_test() {
  let assert Ok(p) =
    ptern.compile(
      "!replacements-ignore-matching = true\n(%Digit * 4 as yr ' ') * 1..3",
    )
  ptern.replace_first_in(
    p,
    "2024 2025 ",
    dict.from_list([#("yr", ptern.ArrayReplacement(["X", "Y"]))]),
  )
  |> should.equal(Ok("X Y "))
}

pub fn scalar_broadcast_in_repetition_test() {
  let assert Ok(p) =
    ptern.compile(
      "!replacements-ignore-matching = true\n(%Digit * 4 as yr ' ') * 1..3",
    )
  ptern.replace_first_in(
    p,
    "2024 2025 2026 ",
    dict.from_list([#("yr", ptern.ScalarReplacement("YYYY"))]),
  )
  |> should.equal(Ok("YYYY YYYY YYYY "))
}

pub fn wrong_replacement_type_error_test() {
  let assert Ok(p) = ptern.compile("%Digit * 4 as year")
  ptern.replace_first_in(
    p,
    "2026",
    dict.from_list([#("year", ptern.ArrayReplacement(["2027"]))]),
  )
  |> should.equal(Error(ptern.WrongReplacementType("year")))
}

pub fn array_length_mismatch_error_test() {
  let assert Ok(p) =
    ptern.compile(
      "!replacements-ignore-matching = true\n(%Digit * 4 as yr) * 3",
    )
  ptern.replace_first_in(
    p,
    "202420252026",
    dict.from_list([#("yr", ptern.ArrayReplacement(["A", "B"]))]),
  )
  |> should.equal(Error(ptern.ArrayLengthMismatch("yr", 2, 3)))
}

pub fn duplicate_repetition_capture_error_test() {
  // The same capture name appears in two separate repetition groups.
  // ArrayReplacement is ambiguous in that case — the validator rejects it.
  let assert Ok(p) =
    ptern.compile(
      "!replacements-ignore-matching = true\n(%Digit as n) * 2 (%Alpha as n) * 3",
    )
  ptern.replace_first_in(
    p,
    "12abc",
    dict.from_list([#("n", ptern.ArrayReplacement(["x", "y"]))]),
  )
  |> should.equal(Error(ptern.DuplicateRepetitionCapture("n")))
}

// ---------------------------------------------------------------------------
// Empty string replacement values
// ---------------------------------------------------------------------------

pub fn replace_scalar_empty_deletes_capture_test() {
  let assert Ok(p) =
    ptern.compile("!replacements-ignore-matching = true\n%Digit * 4 as year")
  ptern.replace_first_in(
    p,
    "event 2026",
    dict.from_list([#("year", ptern.ScalarReplacement(""))]),
  )
  |> should.equal(Ok("event "))
}

pub fn replace_all_in_scalar_empty_deletes_all_test() {
  let assert Ok(p) =
    ptern.compile("!replacements-ignore-matching = true\n%Digit * 4 as year")
  ptern.replace_all_in(
    p,
    "2026 and 2025",
    dict.from_list([#("year", ptern.ScalarReplacement(""))]),
  )
  |> should.equal(Ok(" and "))
}

pub fn replace_array_empty_element_deletes_iteration_test() {
  let assert Ok(p) =
    ptern.compile("!replacements-ignore-matching = true\n(%Alpha as c) * 3")
  ptern.replace_first_in(
    p,
    "abc",
    dict.from_list([#("c", ptern.ArrayReplacement(["", "x", ""]))]),
  )
  |> should.equal(Ok("x"))
}

pub fn replace_scalar_empty_validates_invalid_test() {
  let assert Ok(p) = ptern.compile("%Digit * 4 as year")
  ptern.replace_first_in(
    p,
    "event 2026",
    dict.from_list([#("year", ptern.ScalarReplacement(""))]),
  )
  |> should.equal(Error(ptern.InvalidReplacementValue("year", "")))
}

// ---------------------------------------------------------------------------
// Round-trip: replace with the same values that came out of a match
// ---------------------------------------------------------------------------

// Helper: lift a captures dict into a replacements dict.
fn as_replacements(
  captures: dict.Dict(String, String),
) -> dict.Dict(String, ptern.ReplacementValue) {
  dict.map_values(captures, fn(_, v) { ptern.ScalarReplacement(v) })
}

pub fn round_trip_replace_all_of_test() {
  let assert Ok(p) =
    ptern.compile("%Digit * 4 as year '-' %Digit * 2 as month '-' %Digit * 2 as day")
  let input = "2026-04-27"
  let assert Some(m) = ptern.match_all_of(p, input)
  ptern.replace_all_of(p, input, as_replacements(m.captures))
  |> should.equal(Ok(input))
}

pub fn round_trip_replace_start_of_test() {
  let assert Ok(p) = ptern.compile("%Digit * 4 as year")
  let input = "2026 is a great year"
  let assert Some(m) = ptern.match_start_of(p, input)
  ptern.replace_start_of(p, input, as_replacements(m.captures))
  |> should.equal(Ok(input))
}

pub fn round_trip_replace_end_of_test() {
  let assert Ok(p) = ptern.compile("%Digit * 4 as year")
  let input = "the year is 2026"
  let assert Some(m) = ptern.match_end_of(p, input)
  ptern.replace_end_of(p, input, as_replacements(m.captures))
  |> should.equal(Ok(input))
}

pub fn round_trip_replace_first_in_test() {
  let assert Ok(p) = ptern.compile("%Digit * 4 as year")
  let input = "event in 2026, repeated in 2025"
  let assert Some(m) = ptern.match_first_in(p, input)
  ptern.replace_first_in(p, input, as_replacements(m.captures))
  |> should.equal(Ok(input))
}

pub fn round_trip_replace_next_in_test() {
  let assert Ok(p) = ptern.compile("%Digit * 4 as year")
  let input = "2026 and 2025"
  let assert Some(m) = ptern.match_next_in(p, input, 7)
  ptern.replace_next_in(p, input, 7, as_replacements(m.captures))
  |> should.equal(Ok(input))
}

// replace_all_in round-trips only when every occurrence shares the same
// capture values; the replacement dict is uniform across all matches.
pub fn round_trip_replace_all_in_uniform_captures_test() {
  let assert Ok(p) = ptern.compile("'v' %Digit as ver")
  let input = "v1 v1 v1"
  ptern.replace_all_in(
    p,
    input,
    dict.from_list([#("ver", ptern.ScalarReplacement("1"))]),
  )
  |> should.equal(Ok(input))
}

// replace_all_in does NOT round-trip when occurrences have different values;
// the last match's captured value is used as the replacement dict here.
pub fn round_trip_replace_all_in_non_uniform_breaks_test() {
  let assert Ok(p) = ptern.compile("'v' %Digit as ver")
  let input = "v1 v2 v3"
  let assert [_, _, last] = ptern.match_all_in(p, input)
  // Using only the last match's value replaces all occurrences with "3".
  ptern.replace_all_in(p, input, as_replacements(last.captures))
  |> should.equal(Ok("v3 v3 v3"))
}

// Repetition captures: match returns only the last iteration's value (how JS
// named groups work — overwritten each pass). Replacing with that scalar
// broadcasts the last value to ALL iterations rather than restoring each one.
pub fn round_trip_repetition_capture_broadcasts_last_value_test() {
  let assert Ok(p) =
    ptern.compile(
      "!replacements-ignore-matching = true\n(%Digit * 4 as yr) * 3",
    )
  let input = "202420252026"
  let assert Some(occ) = ptern.match_first_in(p, input)
  // The match API returns only the last iteration's value.
  dict.get(occ.captures, "yr") |> should.equal(Ok("2026"))
  // Replacing with that scalar broadcasts "2026" to all three slots.
  ptern.replace_first_in(p, input, as_replacements(occ.captures))
  |> should.equal(Ok("202620262026"))
}
