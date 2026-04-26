import bounds
import codegen/codegen
import codegen/substitution
import gleam/dict
import gleam/list
import gleam/option.{type Option}
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

pub type ReplacementError {
  InvalidReplacementValue(capture_name: String, value: String)
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
    substitution_plan: Option(substitution.SubstitutionPlan),
    // Fields read by the TypeScript wrapper (index.ts)
    source: String,
    flags: String,
    capture_validator_list: List(#(String, String)),
  )
}

// ---------------------------------------------------------------------------
// Compile
// ---------------------------------------------------------------------------

pub fn compile(source: String) -> Result(Ptern, CompileError) {
  use tokens <- result.try(lexer.lex(source) |> result.map_error(LexError))
  use parsed <- result.try(parser.parse(tokens) |> result.map_error(ParseError))
  let is_substitutable =
    list.any(parsed.annotations, fn(a) { a.name == "substitutable" && a.value })
  let all_errors =
    list.append(validator.validate(parsed), resolver.resolve(parsed))
  // When !substitutable = true, duplicate captures are intentional (the same
  // name in multiple positions supplies the same value, or an array value
  // consumed sequentially). Filter them out only in that case.
  let semantic_errors = case is_substitutable {
    False -> all_errors
    True ->
      list.filter(all_errors, fn(e) {
        case e {
          semantic_error.DuplicateCapture(_) -> False
          _ -> True
        }
      })
  }
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
        capture_validator_list: compiled.capture_validators,
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

fn validate_replacements(
  ptern: Ptern,
  replacements: dict.Dict(String, String),
) -> Result(Nil, ReplacementError) {
  case ptern.ignore_matching {
    True -> Ok(Nil)
    False ->
      dict.fold(replacements, Ok(Nil), fn(acc, name, value) {
        case acc {
          Error(_) -> acc
          Ok(_) ->
            case dict.get(ptern.capture_validators, name) {
              Error(_) -> Ok(Nil)
              Ok(re) ->
                case regex.test_re(re, value) {
                  True -> Ok(Nil)
                  False -> Error(InvalidReplacementValue(name, value))
                }
            }
        }
      })
  }
}

// ---------------------------------------------------------------------------
// Replacing
// ---------------------------------------------------------------------------

/// Replace the match if the entire input matches, otherwise return input unchanged.
/// Returns `Error(InvalidReplacementValue(...))` when a replacement value does not match
/// the capture's subpattern (unless `!replacements-ignore-matching = true` is set).
pub fn replace_all_of(
  ptern: Ptern,
  input: String,
  replacements: dict.Dict(String, String),
) -> Result(String, ReplacementError) {
  use _ <- result.try(validate_replacements(ptern, replacements))
  Ok(regex.replace_rich(ptern.full_re, input, dict.to_list(replacements)))
}

/// Replace the match at the start of input, otherwise return input unchanged.
pub fn replace_start_of(
  ptern: Ptern,
  input: String,
  replacements: dict.Dict(String, String),
) -> Result(String, ReplacementError) {
  use _ <- result.try(validate_replacements(ptern, replacements))
  Ok(regex.replace_rich(ptern.starts_re, input, dict.to_list(replacements)))
}

/// Replace the match at the end of input, otherwise return input unchanged.
pub fn replace_end_of(
  ptern: Ptern,
  input: String,
  replacements: dict.Dict(String, String),
) -> Result(String, ReplacementError) {
  use _ <- result.try(validate_replacements(ptern, replacements))
  Ok(regex.replace_rich(ptern.ends_re, input, dict.to_list(replacements)))
}

/// Replace the first occurrence anywhere in the input, otherwise return input unchanged.
pub fn replace_first_in(
  ptern: Ptern,
  input: String,
  replacements: dict.Dict(String, String),
) -> Result(String, ReplacementError) {
  use _ <- result.try(validate_replacements(ptern, replacements))
  Ok(regex.replace_rich(ptern.contains_re, input, dict.to_list(replacements)))
}

/// Replace the next occurrence at or after start_index, otherwise return input unchanged.
pub fn replace_next_in(
  ptern: Ptern,
  input: String,
  start_index: Int,
  replacements: dict.Dict(String, String),
) -> Result(String, ReplacementError) {
  use _ <- result.try(validate_replacements(ptern, replacements))
  Ok(regex.replace_from_rich(
    ptern.contains_g_re,
    input,
    start_index,
    dict.to_list(replacements),
  ))
}

/// Replace all occurrences with the same replacements.
pub fn replace_all_in(
  ptern: Ptern,
  input: String,
  replacements: dict.Dict(String, String),
) -> Result(String, ReplacementError) {
  use _ <- result.try(validate_replacements(ptern, replacements))
  Ok(regex.replace_all_rich(
    ptern.contains_g_re,
    input,
    dict.to_list(replacements),
  ))
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
