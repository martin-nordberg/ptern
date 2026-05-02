import gleam/dict.{type Dict}
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
  type SemanticError, BoundedRepetitionNeedsCapture, DuplicateAnnotation,
  EmptyCharacterSet, EmptyLiteral, InvalidEscapeSequence,
  InvalidExclusionOperand, InvalidRangeEndpoint, InvertedRange,
  InvertedRepetitionBounds, NotSubstitutableBody, PositionAssertionInRepetition,
  SubstitutionsIgnoreMatchingWithoutSubstitutable, UnknownAnnotation,
  UnknownPositionAssertion,
}

/// Run all constraint checks on a parsed Ptern, returning every error found.
/// An empty list means the pattern is structurally valid.
pub fn validate(ptern: ParsedPtern) -> List(SemanticError) {
  let is_substitutable =
    list.any(ptern.annotations, fn(a) { a.name == "substitutable" && a.value })
  let def_bodies =
    list.fold(ptern.definitions, dict.new(), fn(acc, def) {
      dict.insert(acc, def.name, def.body)
    })
  let subst_errs = validate_substitution_annotations(ptern.annotations)
  let body_subst_errs = case is_substitutable {
    False -> []
    True ->
      case is_substitutable_expr(ptern.body, def_bodies) {
        True -> []
        False -> [NotSubstitutableBody]
      }
  }
  list.flatten([
    validate_annotations(ptern.annotations),
    subst_errs,
    body_subst_errs,
    validate_definitions(ptern.definitions),
    validate_expression(ptern.body, False, is_substitutable, def_bodies),
  ])
}

// ---------------------------------------------------------------------------
// Annotations
// ---------------------------------------------------------------------------

fn known_annotation_names() -> List(String) {
  [
    "case-insensitive", "multiline", "replacements-ignore-matching",
    "substitutable", "substitutions-ignore-matching", "allow-backtracking",
  ]
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
// Cross-annotation checks for substitution
// ---------------------------------------------------------------------------

fn validate_substitution_annotations(
  anns: List(ast.Annotation),
) -> List(SemanticError) {
  let is_substitutable =
    list.any(anns, fn(a) { a.name == "substitutable" && a.value })
  let ignore_matching_set =
    list.any(anns, fn(a) {
      a.name == "substitutions-ignore-matching" && a.value
    })
  case ignore_matching_set && !is_substitutable {
    True -> [SubstitutionsIgnoreMatchingWithoutSubstitutable]
    False -> []
  }
}

// ---------------------------------------------------------------------------
// Definitions
// ---------------------------------------------------------------------------

fn validate_definitions(defs: List(Definition)) -> List(SemanticError) {
  list.flat_map(defs, fn(def) {
    validate_expression(def.body, False, False, dict.new())
  })
}

// ---------------------------------------------------------------------------
// Expression tree walk
// `inside_rep` is True when nested inside a counted repetition.
// `is_subst` is True when `!substitutable = true` is set — enforces
// BoundedRepetitionNeedsCapture.
// ---------------------------------------------------------------------------

fn validate_expression(
  expr: Expression,
  inside_rep: Bool,
  is_subst: Bool,
  def_bodies: Dict(String, Expression),
) -> List(SemanticError) {
  let Alternation(seqs) = expr
  list.flat_map(seqs, fn(seq) {
    validate_sequence(seq, inside_rep, is_subst, def_bodies)
  })
}

fn validate_sequence(
  seq: Sequence,
  inside_rep: Bool,
  is_subst: Bool,
  def_bodies: Dict(String, Expression),
) -> List(SemanticError) {
  let Sequence(items) = seq
  list.flat_map(items, fn(cap) {
    validate_capture(cap, inside_rep, is_subst, def_bodies)
  })
}

fn validate_capture(
  cap: Capture,
  inside_rep: Bool,
  is_subst: Bool,
  def_bodies: Dict(String, Expression),
) -> List(SemanticError) {
  // When this capture has a name it acts as a substitution point for its
  // inner repetition, so bounded-rep-needs-capture should not fire for it.
  let covered = is_subst && cap.name != option.None
  validate_repetition(cap.inner, inside_rep, is_subst, covered, def_bodies)
}

fn validate_repetition(
  rep: Repetition,
  inside_rep: Bool,
  is_subst: Bool,
  covered_by_capture: Bool,
  def_bodies: Dict(String, Expression),
) -> List(SemanticError) {
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
      // Only check that a bounded repetition contains a named capture when we
      // are not already covered by an outer named capture (which acts as the
      // substitution point and makes the inner repetition irrelevant).
      let bounded_cap_errs = case is_subst, covered_by_capture, rc {
        True, False, RepCount(_, Exact(_))
        | True, False, RepCount(_, ast.Unbounded) ->
          case has_named_capture_in_exclusion(rep.inner) {
            True -> []
            False -> [BoundedRepetitionNeedsCapture]
          }
        _, _, _ -> []
      }
      list.flatten([bounds_errs, assertion_errs, bounded_cap_errs])
    }
  }
  let sub_inside = case rep.count {
    Some(_) -> True
    None -> inside_rep
  }
  let body_errs =
    validate_exclusion(rep.inner, sub_inside, is_subst, def_bodies)
  list.append(count_errs, body_errs)
}

fn validate_rep_count(rc: RepCount) -> List(SemanticError) {
  case rc {
    RepCount(min, Exact(max)) if min > max -> [InvertedRepetitionBounds(min, max)]
    _ -> []
  }
}

fn validate_exclusion(
  excl: Exclusion,
  inside_rep: Bool,
  is_subst: Bool,
  def_bodies: Dict(String, Expression),
) -> List(SemanticError) {
  let base_errs = validate_range_item(excl.base, inside_rep, is_subst, def_bodies)
  case excl.excluded {
    None -> base_errs
    Some(excl_item) -> {
      let item_errs =
        validate_range_item(excl_item, inside_rep, is_subst, def_bodies)
      let set_errs = case is_char_set(excl.base) && is_char_set(excl_item) {
        False -> [InvalidExclusionOperand]
        True ->
          case excl.base == excl_item {
            True -> [EmptyCharacterSet]
            False -> []
          }
      }
      list.flatten([base_errs, item_errs, set_errs])
    }
  }
}

// A range item is a "character set" when it is a char-class, a single-char
// literal, or a char-range with literal endpoints. Does not accept groups;
// used as the non-recursive base for is_char_set.
fn is_simple_char_set(item: RangeItem) -> Bool {
  case item {
    SingleAtom(Literal(_)) -> True
    SingleAtom(CharClass(_)) -> True
    CharRange(Literal(_), Literal(_)) -> True
    _ -> False
  }
}

// Extends is_simple_char_set to also accept a flat union group:
// (A | B | …) where every alternative is a single bare char-set item
// (no name, no repetition count, no nested excluding, no interpolations).
fn is_char_set(item: RangeItem) -> Bool {
  case item {
    SingleAtom(Group(Alternation(alts))) ->
      !list.is_empty(alts) && list.all(alts, is_char_set_group_alt)
    _ -> is_simple_char_set(item)
  }
}

// True when a sequence is a single unnamed, uncounted, non-excluding item
// whose base passes is_simple_char_set (groups-within-groups are blocked).
fn is_char_set_group_alt(seq: Sequence) -> Bool {
  let Sequence(items) = seq
  case items {
    [ast.Capture(
      inner: ast.Repetition(
        inner: ast.Exclusion(base: base, excluded: None),
        count: None,
      ),
      name: None,
    )] -> is_simple_char_set(base)
    _ -> False
  }
}

fn validate_range_item(
  item: RangeItem,
  inside_rep: Bool,
  is_subst: Bool,
  def_bodies: Dict(String, Expression),
) -> List(SemanticError) {
  case item {
    SingleAtom(atom) -> validate_atom(atom, inside_rep, is_subst, def_bodies)
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

fn validate_atom(
  atom: Atom,
  inside_rep: Bool,
  is_subst: Bool,
  def_bodies: Dict(String, Expression),
) -> List(SemanticError) {
  case atom {
    Literal(c) ->
      case c {
        "" -> [EmptyLiteral]
        _ -> validate_literal_escapes(c)
      }
    CharClass(_) -> []
    Interpolation(_) -> []
    Group(expr) -> validate_expression(expr, inside_rep, is_subst, def_bodies)
    PositionAssertion(name) ->
      case list.contains(known_position_assertion_names(), name) {
        True -> []
        False -> [UnknownPositionAssertion(name)]
      }
  }
}

// ---------------------------------------------------------------------------
// Substitutability check
// ---------------------------------------------------------------------------

fn is_substitutable_expr(
  expr: Expression,
  def_bodies: Dict(String, Expression),
) -> Bool {
  let Alternation(seqs) = expr
  list.all(seqs, fn(seq) { is_substitutable_seq(seq, def_bodies) })
}

fn is_substitutable_seq(
  seq: Sequence,
  def_bodies: Dict(String, Expression),
) -> Bool {
  let Sequence(items) = seq
  list.all(items, fn(cap) { is_substitutable_cap(cap, def_bodies) })
}

fn is_substitutable_cap(
  cap: ast.Capture,
  def_bodies: Dict(String, Expression),
) -> Bool {
  case cap.name {
    Some(_) -> True
    None -> is_substitutable_rep(cap.inner, def_bodies)
  }
}

fn is_substitutable_rep(
  rep: ast.Repetition,
  def_bodies: Dict(String, Expression),
) -> Bool {
  case rep.count {
    None -> is_substitutable_excl(rep.inner, def_bodies)
    Some(RepCount(_, ast.None)) -> is_substitutable_excl(rep.inner, def_bodies)
    Some(RepCount(_, Exact(_))) | Some(RepCount(_, ast.Unbounded)) ->
      has_named_capture_in_exclusion(rep.inner)
  }
}

fn is_substitutable_excl(
  excl: ast.Exclusion,
  def_bodies: Dict(String, Expression),
) -> Bool {
  case excl.excluded {
    Some(_) -> False
    None -> is_substitutable_item(excl.base, def_bodies)
  }
}

fn is_substitutable_item(
  item: RangeItem,
  def_bodies: Dict(String, Expression),
) -> Bool {
  case item {
    CharRange(_, _) -> False
    SingleAtom(atom) -> is_substitutable_atom(atom, def_bodies)
  }
}

fn is_substitutable_atom(
  atom: Atom,
  def_bodies: Dict(String, Expression),
) -> Bool {
  case atom {
    Literal(_) -> True
    PositionAssertion(_) -> True
    CharClass(_) -> False
    Interpolation(name) ->
      case dict.get(def_bodies, name) {
        Ok(body) -> is_substitutable_expr(body, def_bodies)
        Error(_) -> False
      }
    Group(expr) -> is_substitutable_expr(expr, def_bodies)
  }
}

// True if any `Capture` with a name exists anywhere inside the exclusion tree.
fn has_named_capture_in_exclusion(excl: ast.Exclusion) -> Bool {
  has_named_capture_in_item(excl.base)
}

fn has_named_capture_in_item(item: RangeItem) -> Bool {
  case item {
    CharRange(_, _) -> False
    SingleAtom(atom) -> has_named_capture_in_atom(atom)
  }
}

fn has_named_capture_in_atom(atom: Atom) -> Bool {
  case atom {
    Literal(_) | CharClass(_) | PositionAssertion(_) | Interpolation(_) -> False
    Group(expr) -> has_named_capture_in_expr(expr)
  }
}

fn has_named_capture_in_expr(expr: Expression) -> Bool {
  let Alternation(seqs) = expr
  list.any(seqs, has_named_capture_in_seq)
}

fn has_named_capture_in_seq(seq: Sequence) -> Bool {
  let Sequence(items) = seq
  list.any(items, has_named_capture_in_cap)
}

fn has_named_capture_in_cap(cap: ast.Capture) -> Bool {
  case cap.name {
    Some(_) -> True
    None -> has_named_capture_in_rep(cap.inner)
  }
}

fn has_named_capture_in_rep(rep: ast.Repetition) -> Bool {
  has_named_capture_in_exclusion(rep.inner)
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
