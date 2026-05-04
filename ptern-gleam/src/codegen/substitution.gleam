import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import parser/ast.{
  type Atom, type Capture, type Exclusion, type Expression, type RangeItem,
  type Repetition, type Sequence, Alternation, CharClass, CharRange, Exact,
  Group, Interpolation, Literal, PositionAssertion, RepCount, Sequence,
  SingleAtom, Unbounded,
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// A compile-time substitution plan: a simplified AST node that the TypeScript
/// runtime traverses to assemble a string from capture values.
pub type SubstitutionPlan {
  PlanLiteral(text: String)
  PlanPositionAssertion
  /// A char class, range, or set-difference — not directly evaluable without
  /// a named capture providing the value.
  PlanNotEvaluable
  PlanCapture(name: String, inner: SubstitutionPlan)
  PlanSequence(items: List(SubstitutionPlan))
  PlanAlternation(branches: List(SubstitutionPlan))
  PlanFixedRep(inner: SubstitutionPlan, count: Int)
  PlanBoundedRep(inner: SubstitutionPlan, min: Int, max: Option(Int))
}

/// Build a substitution plan from the body expression of a substitutable ptern.
pub fn build_plan(
  body: Expression,
  def_bodies: Dict(String, Expression),
) -> SubstitutionPlan {
  let cap_reps = collect_capture_reps_in_expr(body)
  build_plan_expr(body, def_bodies, cap_reps)
}

// ---------------------------------------------------------------------------
// Body-capture repetition collector (for {name} interpolation in the plan)
// ---------------------------------------------------------------------------

fn collect_capture_reps_in_expr(expr: Expression) -> Dict(String, Repetition) {
  let Alternation(seqs) = expr
  list.fold(seqs, dict.new(), fn(acc, seq) {
    dict.merge(acc, collect_capture_reps_in_seq(seq))
  })
}

fn collect_capture_reps_in_seq(seq: Sequence) -> Dict(String, Repetition) {
  let Sequence(items) = seq
  list.fold(items, dict.new(), fn(acc, cap) {
    dict.merge(acc, collect_capture_reps_in_cap(cap))
  })
}

fn collect_capture_reps_in_cap(cap: Capture) -> Dict(String, Repetition) {
  let own = case cap.name {
    None -> dict.new()
    Some(name) -> dict.from_list([#(name, cap.inner)])
  }
  dict.merge(own, collect_capture_reps_in_rep(cap.inner))
}

fn collect_capture_reps_in_rep(rep: Repetition) -> Dict(String, Repetition) {
  collect_capture_reps_in_excl(rep.inner)
}

fn collect_capture_reps_in_excl(excl: Exclusion) -> Dict(String, Repetition) {
  collect_capture_reps_in_item(excl.base)
}

fn collect_capture_reps_in_item(item: RangeItem) -> Dict(String, Repetition) {
  case item {
    CharRange(_, _) -> dict.new()
    SingleAtom(atom) -> collect_capture_reps_in_atom(atom)
  }
}

fn collect_capture_reps_in_atom(atom: Atom) -> Dict(String, Repetition) {
  case atom {
    Literal(_) | CharClass(_) | Interpolation(_) | PositionAssertion(_) ->
      dict.new()
    Group(expr) -> collect_capture_reps_in_expr(expr)
  }
}

// ---------------------------------------------------------------------------
// Plan builder
// ---------------------------------------------------------------------------

fn build_plan_expr(
  expr: Expression,
  def_bodies: Dict(String, Expression),
  cap_reps: Dict(String, Repetition),
) -> SubstitutionPlan {
  let Alternation(seqs) = expr
  case seqs {
    [single] -> build_plan_seq(single, def_bodies, cap_reps)
    _ ->
      PlanAlternation(list.map(seqs, fn(s) {
        build_plan_seq(s, def_bodies, cap_reps)
      }))
  }
}

fn build_plan_seq(
  seq: Sequence,
  def_bodies: Dict(String, Expression),
  cap_reps: Dict(String, Repetition),
) -> SubstitutionPlan {
  let Sequence(items) = seq
  case items {
    [single] -> build_plan_cap(single, def_bodies, cap_reps)
    _ ->
      PlanSequence(list.map(items, fn(c) {
        build_plan_cap(c, def_bodies, cap_reps)
      }))
  }
}

fn build_plan_cap(
  cap: Capture,
  def_bodies: Dict(String, Expression),
  cap_reps: Dict(String, Repetition),
) -> SubstitutionPlan {
  let inner = build_plan_rep(cap.inner, def_bodies, cap_reps)
  case cap.name {
    None -> inner
    Some(name) -> PlanCapture(name, inner)
  }
}

fn build_plan_rep(
  rep: Repetition,
  def_bodies: Dict(String, Expression),
  cap_reps: Dict(String, Repetition),
) -> SubstitutionPlan {
  let base = build_plan_item(rep.inner.base, def_bodies, cap_reps)
  let inner = case rep.inner.excluded {
    Some(_) -> PlanNotEvaluable
    None -> base
  }
  case rep.count {
    None -> inner
    Some(RepCount(n, ast.None, _)) -> PlanFixedRep(inner, n)
    Some(RepCount(n, Exact(m), _)) -> PlanBoundedRep(inner, n, Some(m))
    Some(RepCount(n, Unbounded, _)) -> PlanBoundedRep(inner, n, None)
  }
}

fn build_plan_item(
  item: RangeItem,
  def_bodies: Dict(String, Expression),
  cap_reps: Dict(String, Repetition),
) -> SubstitutionPlan {
  case item {
    CharRange(_, _) -> PlanNotEvaluable
    SingleAtom(atom) -> build_plan_atom(atom, def_bodies, cap_reps)
  }
}

fn build_plan_atom(
  atom: Atom,
  def_bodies: Dict(String, Expression),
  cap_reps: Dict(String, Repetition),
) -> SubstitutionPlan {
  case atom {
    Literal(raw) -> PlanLiteral(raw_to_string(raw))
    CharClass(_) -> PlanNotEvaluable
    PositionAssertion(_) -> PlanPositionAssertion
    Interpolation(name) ->
      case dict.get(def_bodies, name) {
        Ok(body) -> build_plan_expr(body, def_bodies, cap_reps)
        Error(_) ->
          case dict.has_key(cap_reps, name) {
            // Body-capture back-reference: produce the value of this capture.
            // PlanNotEvaluable as inner means absence → MissingCapture at runtime.
            True -> PlanCapture(name, PlanNotEvaluable)
            False -> PlanLiteral("")
          }
      }
    Group(expr) -> build_plan_expr(expr, def_bodies, cap_reps)
  }
}

// ---------------------------------------------------------------------------
// Literal decoding (raw → plain string for PlanLiteral nodes)
// ---------------------------------------------------------------------------

fn raw_to_string(raw: String) -> String {
  do_raw_to_string(raw, "")
}

fn do_raw_to_string(s: String, acc: String) -> String {
  case string.pop_grapheme(s) {
    Error(_) -> acc
    Ok(#("\\", rest)) -> decode_escape(rest, acc)
    Ok(#(c, rest)) -> do_raw_to_string(rest, acc <> c)
  }
}

fn decode_escape(s: String, acc: String) -> String {
  case string.pop_grapheme(s) {
    Error(_) -> acc
    Ok(#(c, rest)) -> {
      let decoded = case c {
        "n" -> "\n"
        "t" -> "\t"
        "r" -> "\r"
        "a" -> "\u{0007}"
        "f" -> "\u{000C}"
        "v" -> "\u{000B}"
        "\\" -> "\\"
        "'" -> "'"
        "\"" -> "\""
        "u" -> {
          let #(hex, _) = take_chars(rest, 4)
          do_unicode_escape(hex)
        }
        _ -> c
      }
      let rest2 = case c {
        "u" -> string.drop_start(rest, 4)
        _ -> rest
      }
      do_raw_to_string(rest2, acc <> decoded)
    }
  }
}

fn do_unicode_escape(hex: String) -> String {
  case int.base_parse(hex, 16) {
    Ok(cp) ->
      case string.utf_codepoint(cp) {
        Ok(ucp) -> string.from_utf_codepoints([ucp])
        Error(_) -> ""
      }
    Error(_) -> ""
  }
}

fn take_chars(s: String, n: Int) -> #(String, String) {
  do_take_chars(s, n, "")
}

fn do_take_chars(s: String, n: Int, acc: String) -> #(String, String) {
  case n {
    0 -> #(acc, s)
    _ ->
      case string.pop_grapheme(s) {
        Error(_) -> #(acc, s)
        Ok(#(c, rest)) -> do_take_chars(rest, n - 1, acc <> c)
      }
  }
}
