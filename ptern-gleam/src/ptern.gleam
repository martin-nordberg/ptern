import bounds
import codegen/codegen
import codegen/substitution.{
  type SubstitutionPlan,
  PlanAlternation,
  PlanBoundedRep,
  PlanCapture,
  PlanFixedRep,
  PlanLiteral,
  PlanNotEvaluable,
  PlanPositionAssertion,
  PlanSequence,
}
import gleam/dict.{type Dict}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import lexer/lexer
import lexer/token
import parser/ast
import parser/parser
import regex
import semantic/error as semantic_error
import semantic/resolver
import semantic/validator

// ---------------------------------------------------------------------------
// Public types
// ---------------------------------------------------------------------------

pub type CompileError {
  LexError(token.LexError)
  ParseError(ast.ParseError)
  SemanticErrors(List(semantic_error.SemanticError))
}

pub type MatchOccurrence {
  MatchOccurrence(index: Int, length: Int, captures: dict.Dict(String, String))
}

pub type ReplacementValue {
  ScalarReplacement(String)
  ArrayReplacement(List(String))
}

pub type ReplacementError {
  InvalidReplacementValue(capture_name: String, value: String)
  WrongReplacementType(capture_name: String)
  ArrayLengthMismatch(capture_name: String, provided: Int, actual: Int)
  DuplicateRepetitionCapture(capture_name: String)
}

pub type SubstitutionError {
  NotSubstitutable
  MissingCapture(name: String)
  CaptureMismatch(name: String, value: String)
  WrongCaptureType(name: String)
  ArrayLengthError(name: String, length: Int, min: Int, max: Option(Int))
  NoMatchingBranch
}

pub opaque type Ptern {
  Ptern(
    full_re: regex.Regex,
    starts_re: regex.Regex,
    ends_re: regex.Regex,
    contains_re: regex.Regex,
    contains_g_re: regex.Regex,
    min_len: Int,
    max_len: Option(Int),
    ignore_matching: Bool,
    capture_validators: dict.Dict(String, regex.Regex),
    is_substitutable: Bool,
    ignore_substitution_matching: Bool,
    substitution_plan: Option(SubstitutionPlan),
    source: String,
    flags: String,
    // Each entry: (group_name, sub_source, capture_names)
    repetition_info_list: List(#(String, String, List(String))),
  )
}

// ---------------------------------------------------------------------------
// Compile
// ---------------------------------------------------------------------------

pub fn compile(source: String) -> Result(Ptern, CompileError) {
  use tokens <- result.try(lexer.lex(source) |> result.map_error(LexError))
  use parsed <- result.try(parser.parse(tokens) |> result.map_error(ParseError))
  let all_errors =
    list.append(validator.validate(parsed), resolver.resolve(parsed))
  // Duplicate capture names are intentional in all patterns: the same name
  // in multiple positions means "apply the same replacement value everywhere"
  // (or, when !substitutable = true, consume an array sequentially).
  let semantic_errors =
    list.filter(all_errors, fn(e) {
      case e {
        semantic_error.DuplicateCapture(_) -> False
        _ -> True
      }
    })
  case semantic_errors {
    [_, ..] -> Error(SemanticErrors(semantic_errors))
    [] -> {
      let compiled = codegen.compile(parsed)
      let bounds = bounds.compute_ptern_bounds(parsed)
      let src = compiled.source
      let flg = compiled.flags
      let d_flg = case string.contains(flg, "d") {
        True -> flg
        False -> flg <> "d"
      }
      let g_flg = case string.contains(d_flg, "g") {
        True -> d_flg
        False -> d_flg <> "g"
      }
      Ok(Ptern(
        full_re: regex.make("^(?:" <> src <> ")$", d_flg),
        starts_re: regex.make("^(?:" <> src <> ")", d_flg),
        ends_re: regex.make("(?:" <> src <> ")$", d_flg),
        contains_re: regex.make(src, d_flg),
        contains_g_re: regex.make(src, g_flg),
        min_len: bounds.min,
        max_len: bounds.max,
        ignore_matching: compiled.ignore_matching,
        capture_validators: build_capture_validators(
          compiled.capture_validators,
          d_flg,
        ),
        is_substitutable: compiled.is_substitutable,
        ignore_substitution_matching: compiled.ignore_substitution_matching,
        substitution_plan: compiled.substitution_plan,
        source: src,
        flags: d_flg,
        repetition_info_list: list.map(
          compiled.repetition_info,
          fn(ri) { #(ri.group_name, ri.sub_source, ri.captures) },
        ),
      ))
    }
  }
}

// ---------------------------------------------------------------------------
// Matching
// ---------------------------------------------------------------------------

/// Returns `True` if the entire input matches this pattern.
pub fn matches_all_of(ptern: Ptern, input: String) -> Bool {
  regex.test_re(ptern.full_re, input)
}

/// Returns `True` if the input starts with this pattern.
pub fn matches_start_of(ptern: Ptern, input: String) -> Bool {
  regex.test_re(ptern.starts_re, input)
}

/// Returns `True` if the input ends with this pattern.
pub fn matches_end_of(ptern: Ptern, input: String) -> Bool {
  regex.test_re(ptern.ends_re, input)
}

/// Returns `True` if the pattern appears anywhere in the input.
pub fn matches_in(ptern: Ptern, input: String) -> Bool {
  regex.test_re(ptern.contains_re, input)
}

/// Returns the match occurrence if the entire input matches, or `None`.
pub fn match_all_of(ptern: Ptern, input: String) -> Option(MatchOccurrence) {
  regex.exec_rich(ptern.full_re, input)
  |> option.map(to_occurrence)
}

/// Returns the match occurrence if the input starts with this pattern, or `None`.
pub fn match_start_of(ptern: Ptern, input: String) -> Option(MatchOccurrence) {
  regex.exec_rich(ptern.starts_re, input)
  |> option.map(to_occurrence)
}

/// Returns the match occurrence if the input ends with this pattern, or `None`.
pub fn match_end_of(ptern: Ptern, input: String) -> Option(MatchOccurrence) {
  regex.exec_rich(ptern.ends_re, input)
  |> option.map(to_occurrence)
}

/// Returns the first match occurrence anywhere in the input, or `None`.
pub fn match_first_in(ptern: Ptern, input: String) -> Option(MatchOccurrence) {
  regex.exec_rich(ptern.contains_re, input)
  |> option.map(to_occurrence)
}

/// Returns the next match occurrence at or after `start_index`, or `None`.
pub fn match_next_in(
  ptern: Ptern,
  input: String,
  start_index: Int,
) -> Option(MatchOccurrence) {
  regex.exec_from_rich(ptern.contains_g_re, input, start_index)
  |> option.map(to_occurrence)
}

/// Returns all match occurrences in the input.
pub fn match_all_in(ptern: Ptern, input: String) -> List(MatchOccurrence) {
  regex.exec_all_rich(ptern.contains_g_re, input)
  |> list.map(to_occurrence)
}

fn to_occurrence(
  t: #(Int, Int, List(#(String, String))),
) -> MatchOccurrence {
  let #(idx, len, pairs) = t
  MatchOccurrence(index: idx, length: len, captures: dict.from_list(pairs))
}

fn build_capture_validators(
  fragments: List(#(String, String)),
  flags: String,
) -> dict.Dict(String, regex.Regex) {
  // Keep only the first fragment for each name: subsequent occurrences of the
  // same capture name are back-references whose compiled body is (?:(?!)).
  list.fold(fragments, dict.new(), fn(acc, pair) {
    let #(name, fragment) = pair
    case dict.has_key(acc, name) {
      True -> acc
      False -> dict.insert(acc, name, regex.make("^(?:" <> fragment <> ")$", flags))
    }
  })
}

fn rep_group_count(
  rep_info_list: List(#(String, String, List(String))),
  capture_name: String,
) -> Int {
  list.count(rep_info_list, fn(ri) {
    let #(_, _, caps) = ri
    list.contains(caps, capture_name)
  })
}

fn validate_replacements(
  ptern: Ptern,
  replacements: dict.Dict(String, ReplacementValue),
) -> Result(Nil, ReplacementError) {
  dict.fold(replacements, Ok(Nil), fn(acc, name, value) {
    case acc {
      Error(_) -> acc
      Ok(_) ->
        case value {
          ScalarReplacement(v) ->
            case ptern.ignore_matching {
              True -> Ok(Nil)
              False ->
                case dict.get(ptern.capture_validators, name) {
                  Error(_) -> Ok(Nil)
                  Ok(re) ->
                    case regex.test_re(re, v) {
                      True -> Ok(Nil)
                      False -> Error(InvalidReplacementValue(name, v))
                    }
                }
            }
          ArrayReplacement(vs) -> {
            let n_reps = rep_group_count(ptern.repetition_info_list, name)
            case n_reps {
              0 -> Error(WrongReplacementType(name))
              1 -> {
                case ptern.ignore_matching {
                  True -> Ok(Nil)
                  False ->
                    case dict.get(ptern.capture_validators, name) {
                      Error(_) -> Ok(Nil)
                      Ok(re) ->
                        list.fold(vs, Ok(Nil), fn(a, v) {
                          case a {
                            Error(_) -> a
                            Ok(_) ->
                              case regex.test_re(re, v) {
                                True -> Ok(Nil)
                                False -> Error(InvalidReplacementValue(name, v))
                              }
                          }
                        })
                    }
                }
              }
              _ -> Error(DuplicateRepetitionCapture(name))
            }
          }
        }
    }
  })
}

// ---------------------------------------------------------------------------
// Replacing
// ---------------------------------------------------------------------------

fn split_replacements(
  replacements: dict.Dict(String, ReplacementValue),
) -> #(List(#(String, String)), List(#(String, List(String)))) {
  dict.fold(replacements, #([], []), fn(acc, name, val) {
    let #(scalars, arrays) = acc
    case val {
      ScalarReplacement(v) -> #([#(name, v), ..scalars], arrays)
      ArrayReplacement(vs) -> #(scalars, [#(name, vs), ..arrays])
    }
  })
}

fn ffi_error_to_replacement_error(
  errs: List(#(String, Int, Int)),
) -> ReplacementError {
  let assert [#(name, provided, actual), ..] = errs
  ArrayLengthMismatch(name, provided, actual)
}

/// Replace the match if the entire input matches, otherwise return input unchanged.
/// Returns `Error(...)` when a replacement value is invalid.
pub fn replace_all_of(
  ptern: Ptern,
  input: String,
  replacements: dict.Dict(String, ReplacementValue),
) -> Result(String, ReplacementError) {
  use _ <- result.try(validate_replacements(ptern, replacements))
  let #(scalars, arrays) = split_replacements(replacements)
  regex.replace_rich_with_arrays(
    ptern.full_re,
    input,
    scalars,
    arrays,
    ptern.repetition_info_list,
    ptern.flags,
  )
  |> result.map_error(ffi_error_to_replacement_error)
}

/// Replace the match at the start of input, otherwise return input unchanged.
pub fn replace_start_of(
  ptern: Ptern,
  input: String,
  replacements: dict.Dict(String, ReplacementValue),
) -> Result(String, ReplacementError) {
  use _ <- result.try(validate_replacements(ptern, replacements))
  let #(scalars, arrays) = split_replacements(replacements)
  regex.replace_rich_with_arrays(
    ptern.starts_re,
    input,
    scalars,
    arrays,
    ptern.repetition_info_list,
    ptern.flags,
  )
  |> result.map_error(ffi_error_to_replacement_error)
}

/// Replace the match at the end of input, otherwise return input unchanged.
pub fn replace_end_of(
  ptern: Ptern,
  input: String,
  replacements: dict.Dict(String, ReplacementValue),
) -> Result(String, ReplacementError) {
  use _ <- result.try(validate_replacements(ptern, replacements))
  let #(scalars, arrays) = split_replacements(replacements)
  regex.replace_rich_with_arrays(
    ptern.ends_re,
    input,
    scalars,
    arrays,
    ptern.repetition_info_list,
    ptern.flags,
  )
  |> result.map_error(ffi_error_to_replacement_error)
}

/// Replace the first occurrence anywhere in the input, otherwise return input unchanged.
pub fn replace_first_in(
  ptern: Ptern,
  input: String,
  replacements: dict.Dict(String, ReplacementValue),
) -> Result(String, ReplacementError) {
  use _ <- result.try(validate_replacements(ptern, replacements))
  let #(scalars, arrays) = split_replacements(replacements)
  regex.replace_rich_with_arrays(
    ptern.contains_re,
    input,
    scalars,
    arrays,
    ptern.repetition_info_list,
    ptern.flags,
  )
  |> result.map_error(ffi_error_to_replacement_error)
}

/// Replace the next occurrence at or after start_index, otherwise return input unchanged.
pub fn replace_next_in(
  ptern: Ptern,
  input: String,
  start_index: Int,
  replacements: dict.Dict(String, ReplacementValue),
) -> Result(String, ReplacementError) {
  use _ <- result.try(validate_replacements(ptern, replacements))
  let #(scalars, arrays) = split_replacements(replacements)
  regex.replace_from_rich_with_arrays(
    ptern.contains_g_re,
    input,
    start_index,
    scalars,
    arrays,
    ptern.repetition_info_list,
    ptern.flags,
  )
  |> result.map_error(ffi_error_to_replacement_error)
}

/// Replace all occurrences with the same replacements.
pub fn replace_all_in(
  ptern: Ptern,
  input: String,
  replacements: dict.Dict(String, ReplacementValue),
) -> Result(String, ReplacementError) {
  use _ <- result.try(validate_replacements(ptern, replacements))
  let #(scalars, arrays) = split_replacements(replacements)
  regex.replace_all_rich_with_arrays(
    ptern.contains_g_re,
    input,
    scalars,
    arrays,
    ptern.repetition_info_list,
    ptern.flags,
  )
  |> result.map_error(ffi_error_to_replacement_error)
}

// ---------------------------------------------------------------------------
// Substitution
// ---------------------------------------------------------------------------

/// Assemble a string from capture values using the compiled substitution plan.
/// Returns `Error(NotSubstitutable)` if `!substitutable = true` was not set.
pub fn substitute(
  ptern: Ptern,
  captures: Dict(String, ReplacementValue),
) -> Result(String, SubstitutionError) {
  case ptern.is_substitutable {
    False -> Error(NotSubstitutable)
    True ->
      case ptern.substitution_plan {
        None -> Error(NotSubstitutable)
        Some(plan) ->
          evaluate_plan(
            plan,
            captures,
            ptern.capture_validators,
            ptern.ignore_substitution_matching,
            dict.new(),
          )
          |> result.map(fn(t) { t.0 })
      }
  }
}

// ---------------------------------------------------------------------------
// Substitution plan evaluation (private)
// ---------------------------------------------------------------------------

fn evaluate_plan(
  plan: SubstitutionPlan,
  captures: Dict(String, ReplacementValue),
  validators: dict.Dict(String, regex.Regex),
  ignore_matching: Bool,
  cursors: Dict(String, Int),
) -> Result(#(String, Dict(String, Int)), SubstitutionError) {
  case plan {
    PlanLiteral(text) -> Ok(#(text, cursors))

    PlanPositionAssertion -> Ok(#("", cursors))

    PlanNotEvaluable -> Error(NoMatchingBranch)

    PlanCapture(name, inner) ->
      case dict.get(captures, name) {
        Ok(ScalarReplacement(v)) ->
          case validate_sub_capture(name, v, validators, ignore_matching) {
            Error(e) -> Error(e)
            Ok(_) -> Ok(#(v, cursors))
          }
        Ok(ArrayReplacement(vs)) ->
          eval_array_capture(name, vs, validators, ignore_matching, cursors)
        Error(_) ->
          case evaluate_plan(inner, captures, validators, ignore_matching, cursors) {
            Error(NoMatchingBranch) -> Error(MissingCapture(name))
            other -> other
          }
      }

    PlanSequence(items) ->
      evaluate_sequence(items, captures, validators, ignore_matching, cursors, "")

    PlanAlternation(branches) ->
      try_branches(branches, captures, validators, ignore_matching, cursors)

    PlanFixedRep(inner, count) ->
      repeat_plan(inner, count, captures, validators, ignore_matching, cursors, "")

    PlanBoundedRep(inner, min, max_opt) ->
      eval_bounded_rep(inner, min, max_opt, captures, validators, ignore_matching, cursors)
  }
}

fn validate_sub_capture(
  name: String,
  value: String,
  validators: dict.Dict(String, regex.Regex),
  ignore_matching: Bool,
) -> Result(Nil, SubstitutionError) {
  case ignore_matching {
    True -> Ok(Nil)
    False ->
      case dict.get(validators, name) {
        Error(_) -> Ok(Nil)
        Ok(re) ->
          case regex.test_re(re, value) {
            True -> Ok(Nil)
            False -> Error(CaptureMismatch(name, value))
          }
      }
  }
}

fn eval_array_capture(
  name: String,
  vs: List(String),
  validators: dict.Dict(String, regex.Regex),
  ignore_matching: Bool,
  cursors: Dict(String, Int),
) -> Result(#(String, Dict(String, Int)), SubstitutionError) {
  let cursor = result.unwrap(dict.get(cursors, name), 0)
  case list.drop(vs, cursor) {
    [] -> Error(MissingCapture(name))
    [elem, ..] ->
      case validate_sub_capture(name, elem, validators, ignore_matching) {
        Error(e) -> Error(e)
        Ok(_) -> Ok(#(elem, dict.insert(cursors, name, cursor + 1)))
      }
  }
}

fn evaluate_sequence(
  items: List(SubstitutionPlan),
  captures: Dict(String, ReplacementValue),
  validators: dict.Dict(String, regex.Regex),
  ignore_matching: Bool,
  cursors: Dict(String, Int),
  acc: String,
) -> Result(#(String, Dict(String, Int)), SubstitutionError) {
  case items {
    [] -> Ok(#(acc, cursors))
    [item, ..rest] ->
      case evaluate_plan(item, captures, validators, ignore_matching, cursors) {
        Error(e) -> Error(e)
        Ok(#(s, new_cursors)) ->
          evaluate_sequence(
            rest,
            captures,
            validators,
            ignore_matching,
            new_cursors,
            acc <> s,
          )
      }
  }
}

fn try_branches(
  branches: List(SubstitutionPlan),
  captures: Dict(String, ReplacementValue),
  validators: dict.Dict(String, regex.Regex),
  ignore_matching: Bool,
  cursors: Dict(String, Int),
) -> Result(#(String, Dict(String, Int)), SubstitutionError) {
  case branches {
    [] -> Error(NoMatchingBranch)
    [branch, ..rest] ->
      case evaluate_plan(branch, captures, validators, ignore_matching, cursors) {
        // On missing capture or no matching branch: restore original cursors
        // (immutability handles this automatically) and try the next branch.
        Error(MissingCapture(_)) | Error(NoMatchingBranch) ->
          try_branches(rest, captures, validators, ignore_matching, cursors)
        other -> other
      }
  }
}

fn repeat_plan(
  plan: SubstitutionPlan,
  remaining: Int,
  captures: Dict(String, ReplacementValue),
  validators: dict.Dict(String, regex.Regex),
  ignore_matching: Bool,
  cursors: Dict(String, Int),
  acc: String,
) -> Result(#(String, Dict(String, Int)), SubstitutionError) {
  case remaining {
    0 -> Ok(#(acc, cursors))
    _ ->
      case evaluate_plan(plan, captures, validators, ignore_matching, cursors) {
        Error(e) -> Error(e)
        Ok(#(s, new_cursors)) ->
          repeat_plan(
            plan,
            remaining - 1,
            captures,
            validators,
            ignore_matching,
            new_cursors,
            acc <> s,
          )
      }
  }
}

fn eval_bounded_rep(
  inner: SubstitutionPlan,
  min: Int,
  max_opt: Option(Int),
  captures: Dict(String, ReplacementValue),
  validators: dict.Dict(String, regex.Regex),
  ignore_matching: Bool,
  cursors: Dict(String, Int),
) -> Result(#(String, Dict(String, Int)), SubstitutionError) {
  let names = collect_direct_capture_names(inner)
  case determine_iter_count(names, captures, cursors, min, max_opt) {
    Error(e) -> Error(e)
    Ok(None) ->
      case min {
        0 -> Ok(#("", cursors))
        _ -> Error(NoMatchingBranch)
      }
    Ok(Some(iter_count)) ->
      repeat_plan(inner, iter_count, captures, validators, ignore_matching, cursors, "")
  }
}

// Collect names of PlanCapture nodes directly within a plan, without
// recursing into the inner plan of each PlanCapture itself.
fn collect_direct_capture_names(plan: SubstitutionPlan) -> List(String) {
  case plan {
    PlanCapture(name, _) -> [name]
    PlanSequence(items) -> list.flat_map(items, collect_direct_capture_names)
    PlanAlternation(branches) ->
      branches
      |> list.flat_map(collect_direct_capture_names)
      |> deduplicate_names
    PlanFixedRep(inner, _) -> collect_direct_capture_names(inner)
    PlanBoundedRep(inner, _, _) -> collect_direct_capture_names(inner)
    _ -> []
  }
}

fn deduplicate_names(names: List(String)) -> List(String) {
  names
  |> list.fold(dict.new(), fn(seen, name) { dict.insert(seen, name, Nil) })
  |> dict.keys
}

// Inspect array-valued captures to determine how many iterations a
// PlanBoundedRep should produce.  Returns Ok(None) when no array captures
// are present, Ok(Some(n)) when all arrays agree on n remaining elements,
// or Error(ArrayLengthError) when arrays disagree or n is out of bounds.
fn determine_iter_count(
  names: List(String),
  captures: Dict(String, ReplacementValue),
  cursors: Dict(String, Int),
  min: Int,
  max_opt: Option(Int),
) -> Result(Option(Int), SubstitutionError) {
  do_determine_iter_count(names, captures, cursors, min, max_opt, None, "")
}

fn do_determine_iter_count(
  names: List(String),
  captures: Dict(String, ReplacementValue),
  cursors: Dict(String, Int),
  min: Int,
  max_opt: Option(Int),
  found: Option(Int),
  first_name: String,
) -> Result(Option(Int), SubstitutionError) {
  case names {
    [] ->
      case found {
        None -> Ok(None)
        Some(n) -> check_iter_bounds(n, first_name, captures, min, max_opt)
      }
    [name, ..rest] ->
      case dict.get(captures, name) {
        Error(_) | Ok(ScalarReplacement(_)) ->
          do_determine_iter_count(
            rest,
            captures,
            cursors,
            min,
            max_opt,
            found,
            first_name,
          )
        Ok(ArrayReplacement(vs)) -> {
          let cursor = result.unwrap(dict.get(cursors, name), 0)
          let total = list.length(vs)
          let remaining = total - cursor
          case found {
            None ->
              do_determine_iter_count(
                rest,
                captures,
                cursors,
                min,
                max_opt,
                Some(remaining),
                name,
              )
            Some(existing) ->
              case existing == remaining {
                True ->
                  do_determine_iter_count(
                    rest,
                    captures,
                    cursors,
                    min,
                    max_opt,
                    found,
                    first_name,
                  )
                False -> Error(ArrayLengthError(name, total, min, max_opt))
              }
          }
        }
      }
  }
}

fn check_iter_bounds(
  n: Int,
  name: String,
  captures: Dict(String, ReplacementValue),
  min: Int,
  max_opt: Option(Int),
) -> Result(Option(Int), SubstitutionError) {
  let above_max = case max_opt {
    None -> False
    Some(m) -> n > m
  }
  case n >= min && !above_max {
    True -> Ok(Some(n))
    False ->
      case dict.get(captures, name) {
        Ok(ArrayReplacement(vs)) ->
          Error(ArrayLengthError(name, list.length(vs), min, max_opt))
        _ -> Error(NoMatchingBranch)
      }
  }
}

// ---------------------------------------------------------------------------
// Metadata
// ---------------------------------------------------------------------------

/// Minimum number of characters this pattern can match.
pub fn min_length(ptern: Ptern) -> Int {
  ptern.min_len
}

/// Maximum number of characters this pattern can match,
/// or `None` if the pattern is unbounded.
pub fn max_length(ptern: Ptern) -> Option(Int) {
  ptern.max_len
}

// ---------------------------------------------------------------------------
// CLI entry point (not part of the library API)
// ---------------------------------------------------------------------------

pub fn main() {
  Nil
}
