import gleam/list
import gleam/option.{None, Some}
import gleam/string
import parser/ast.{
  type Atom, type Capture, type Definition, type Exclusion, type Expression,
  type ParsedPtern, type RangeItem, type RepCount, type Repetition, type Sequence,
  Alternation, CharClass, CharRange, Exact, Group, Interpolation, Literal,
  PositionAssertion, RepCount, Sequence, SingleAtom,
}
import semantic/error.{
  type SemanticError, CaptureInRepetition, DuplicateAnnotation,
  InvalidEscapeSequence, InvalidExclusionOperand, InvalidRangeEndpoint,
  InvertedRange, InvertedRepetitionBounds, PositionAssertionInRepetition,
  UnknownAnnotation, UnknownPositionAssertion,
}

/// Run all constraint checks on a parsed Ptern, returning every error found.
/// An empty list means the pattern is structurally valid.
pub fn validate(ptern: ParsedPtern) -> List(SemanticError) {
  list.flatten([
    validate_annotations(ptern.annotations),
    validate_definitions(ptern.definitions),
    validate_expression(ptern.body, False),
  ])
}

// ---------------------------------------------------------------------------
// Annotations
// ---------------------------------------------------------------------------

fn known_annotation_names() -> List(String) {
  ["case-insensitive", "multiline", "replacements-ignore-matching"]
}

fn known_position_assertion_names() -> List(String) {
  ["word-start", "word-end", "line-start", "line-end"]
}

fn validate_annotations(
  anns: List(ast.Annotation),
) -> List(SemanticError) {
  let name_errs =
    list.flat_map(anns, fn(ann) {
      case list.contains(known_annotation_names(), ann.name) {
        True -> []
        False -> [UnknownAnnotation(ann.name)]
      }
    })
  let dup_errs =
    find_duplicate_names(list.map(anns, fn(a) { a.name }), DuplicateAnnotation)
  list.append(name_errs, dup_errs)
}

// ---------------------------------------------------------------------------
// Definitions
// ---------------------------------------------------------------------------

fn validate_definitions(defs: List(Definition)) -> List(SemanticError) {
  list.flat_map(defs, fn(def) { validate_expression(def.body, False) })
}

// ---------------------------------------------------------------------------
// Expression tree walk — `inside_rep` is True when we are nested inside a
// counted repetition; named captures in that context are errors.
// ---------------------------------------------------------------------------

fn validate_expression(expr: Expression, inside_rep: Bool) -> List(SemanticError) {
  let Alternation(seqs) = expr
  list.flat_map(seqs, fn(seq) { validate_sequence(seq, inside_rep) })
}

fn validate_sequence(seq: Sequence, inside_rep: Bool) -> List(SemanticError) {
  let Sequence(items) = seq
  list.flat_map(items, fn(cap) { validate_capture(cap, inside_rep) })
}

fn validate_capture(cap: Capture, inside_rep: Bool) -> List(SemanticError) {
  let name_errs = case inside_rep, cap.name {
    True, Some(name) -> [CaptureInRepetition(name)]
    _, _ -> []
  }
  let inner_errs = validate_repetition(cap.inner, inside_rep)
  list.append(name_errs, inner_errs)
}

fn validate_repetition(rep: Repetition, inside_rep: Bool) -> List(SemanticError) {
  let count_errs = case rep.count {
    None -> []
    Some(rc) -> {
      let bounds_errs = validate_rep_count(rc)
      let assertion_errs = case rep.inner.excluded, rep.inner.base {
        None, SingleAtom(PositionAssertion(name)) -> [
          PositionAssertionInRepetition(name),
        ]
        _, _ -> []
      }
      list.append(bounds_errs, assertion_errs)
    }
  }
  // Once we enter a counted repetition, all nested captures are errors.
  let sub_inside = case rep.count {
    Some(_) -> True
    None -> inside_rep
  }
  let body_errs = validate_exclusion(rep.inner, sub_inside)
  list.append(count_errs, body_errs)
}

fn validate_rep_count(rc: RepCount) -> List(SemanticError) {
  case rc {
    RepCount(min, Exact(max)) if min > max -> [InvertedRepetitionBounds(min, max)]
    _ -> []
  }
}

fn validate_exclusion(excl: Exclusion, inside_rep: Bool) -> List(SemanticError) {
  let base_errs = validate_range_item(excl.base, inside_rep)
  case excl.excluded {
    None -> base_errs
    Some(excl_item) -> {
      let item_errs = validate_range_item(excl_item, inside_rep)
      let set_errs = case is_char_set(excl.base) && is_char_set(excl_item) {
        True -> []
        False -> [InvalidExclusionOperand]
      }
      list.flatten([base_errs, item_errs, set_errs])
    }
  }
}

// A range item is a "character set" when it is a char-class, a single-char
// literal, or a char-range with literal endpoints. Groups and interpolations
// cannot be used as operands to `excluding`.
fn is_char_set(item: RangeItem) -> Bool {
  case item {
    SingleAtom(Literal(_)) -> True
    SingleAtom(CharClass(_)) -> True
    CharRange(Literal(_), Literal(_)) -> True
    _ -> False
  }
}

fn validate_range_item(item: RangeItem, inside_rep: Bool) -> List(SemanticError) {
  case item {
    SingleAtom(atom) -> validate_atom(atom, inside_rep)
    CharRange(from, to) -> validate_char_range(from, to)
  }
}

fn validate_char_range(from: Atom, to: Atom) -> List(SemanticError) {
  let check_endpoint = fn(atom) {
    case atom {
      Literal(c) -> {
        let len_err = case decoded_length(c) == 1 {
          True -> []
          False -> [InvalidRangeEndpoint(c)]
        }
        list.append(len_err, validate_literal_escapes(c))
      }
      _ -> [InvalidRangeEndpoint("<non-literal>")]
    }
  }
  let from_errs = check_endpoint(from)
  let to_errs = check_endpoint(to)
  // Inversion check only for plain single graphemes (no escapes to decode).
  let inv_errs = case from, to {
    Literal(fc), Literal(tc) -> {
      case string.length(fc) == 1 && string.length(tc) == 1 {
        False -> []
        True ->
          case char_code_of(fc) > char_code_of(tc) {
            True -> [InvertedRange(fc, tc)]
            False -> []
          }
      }
    }
    _, _ -> []
  }
  list.flatten([from_errs, to_errs, inv_errs])
}

fn validate_atom(atom: Atom, inside_rep: Bool) -> List(SemanticError) {
  case atom {
    Literal(c) -> validate_literal_escapes(c)
    CharClass(_) -> []
    Interpolation(_) -> []
    Group(expr) -> validate_expression(expr, inside_rep)
    PositionAssertion(name) ->
      case list.contains(known_position_assertion_names(), name) {
        True -> []
        False -> [UnknownPositionAssertion(name)]
      }
  }
}

// ---------------------------------------------------------------------------
// String literal escape sequence validation
// ---------------------------------------------------------------------------

fn validate_literal_escapes(content: String) -> List(SemanticError) {
  do_validate_escapes(content, [])
}

fn do_validate_escapes(
  s: String,
  acc: List(SemanticError),
) -> List(SemanticError) {
  case string.pop_grapheme(s) {
    Error(_) -> acc
    Ok(#("\\", rest)) -> validate_escape_char(rest, acc)
    Ok(#(_, rest)) -> do_validate_escapes(rest, acc)
  }
}

fn validate_escape_char(
  s: String,
  acc: List(SemanticError),
) -> List(SemanticError) {
  case string.pop_grapheme(s) {
    Error(_) -> [InvalidEscapeSequence("\\"), ..acc]
    Ok(#(c, rest)) ->
      case c {
        "n" | "t" | "r" | "a" | "f" | "v" | "'" | "\"" | "\\" ->
          do_validate_escapes(rest, acc)
        "u" ->
          // \uXXXX — lexer already ensured 4 hex digits exist; skip them.
          skip_chars(rest, 4, acc)
        _ -> do_validate_escapes(rest, [InvalidEscapeSequence("\\" <> c), ..acc])
      }
  }
}

fn skip_chars(
  s: String,
  n: Int,
  acc: List(SemanticError),
) -> List(SemanticError) {
  case n {
    0 -> do_validate_escapes(s, acc)
    _ ->
      case string.pop_grapheme(s) {
        Error(_) -> acc
        Ok(#(_, rest)) -> skip_chars(rest, n - 1, acc)
      }
  }
}

// ---------------------------------------------------------------------------
// Character / length helpers
// ---------------------------------------------------------------------------

// Number of decoded characters that `content` represents (escape sequences
// count as one character each).
fn decoded_length(content: String) -> Int {
  count_decoded_chars(content, 0)
}

fn count_decoded_chars(s: String, count: Int) -> Int {
  case string.pop_grapheme(s) {
    Error(_) -> count
    Ok(#("\\", rest)) ->
      case string.pop_grapheme(rest) {
        Error(_) -> count + 1
        Ok(#("u", rest2)) ->
          count_decoded_chars(string.drop_start(rest2, 4), count + 1)
        Ok(#(_, rest2)) -> count_decoded_chars(rest2, count + 1)
      }
    Ok(#(_, rest)) -> count_decoded_chars(rest, count + 1)
  }
}

fn char_code_of(s: String) -> Int {
  case string.to_utf_codepoints(s) {
    [cp, ..] -> string.utf_codepoint_to_int(cp)
    _ -> 0
  }
}

// ---------------------------------------------------------------------------
// Duplicate detection helper
// ---------------------------------------------------------------------------

fn find_duplicate_names(
  names: List(String),
  to_error: fn(String) -> SemanticError,
) -> List(SemanticError) {
  do_find_dups(names, [], [])
  |> list.map(to_error)
}

fn do_find_dups(
  names: List(String),
  seen: List(String),
  dups: List(String),
) -> List(String) {
  case names {
    [] -> list.reverse(dups)
    [name, ..rest] ->
      case list.contains(seen, name) {
        False -> do_find_dups(rest, [name, ..seen], dups)
        True ->
          case list.contains(dups, name) {
            True -> do_find_dups(rest, seen, dups)
            False -> do_find_dups(rest, seen, [name, ..dups])
          }
      }
  }
}
