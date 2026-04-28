import gleam/dict
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
