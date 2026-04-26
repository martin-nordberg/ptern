import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import parser/ast.{
  type Atom, type Definition, type Exclusion, type Expression, type RangeItem,
  type Repetition, type Sequence, Alternation, CharClass, CharRange, Exact,
  Group, Interpolation, Literal, PositionAssertion, RepCount, Sequence,
  SingleAtom, Unbounded,
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

pub type Bounds {
  Bounds(min: Int, max: Option(Int))
}

pub fn compute_ptern_bounds(parsed: ast.ParsedPtern) -> Bounds {
  let def_bounds = compute_def_bounds_all(parsed.definitions)
  compute_expression_bounds(parsed.body, def_bounds)
}

// ---------------------------------------------------------------------------
// Definition bounds (memoised)
// ---------------------------------------------------------------------------

fn compute_def_bounds_all(defs: List(Definition)) -> Dict(String, Bounds) {
  let def_exprs: Dict(String, Expression) =
    list.fold(defs, dict.new(), fn(m, def) { dict.insert(m, def.name, def.body) })
  list.fold(defs, dict.new(), fn(acc, def) {
    compute_def_bounds_memo(def.name, def_exprs, acc)
  })
}

fn compute_def_bounds_memo(
  name: String,
  def_exprs: Dict(String, Expression),
  acc: Dict(String, Bounds),
) -> Dict(String, Bounds) {
  case dict.get(acc, name) {
    Ok(_) -> acc
    Error(_) ->
      case dict.get(def_exprs, name) {
        Error(_) -> acc
        Ok(body) -> {
          let bounds = compute_expression_bounds(body, acc)
          dict.insert(acc, name, bounds)
        }
      }
  }
}

// ---------------------------------------------------------------------------
// Expression bounds
// ---------------------------------------------------------------------------

fn compute_expression_bounds(
  expr: Expression,
  defs: Dict(String, Bounds),
) -> Bounds {
  let Alternation(seqs) = expr
  case seqs {
    [] -> Bounds(0, Some(0))
    [first, ..rest] -> {
      let first_b = compute_sequence_bounds(first, defs)
      list.fold(rest, first_b, fn(acc, seq) {
        let b = compute_sequence_bounds(seq, defs)
        Bounds(min: int.min(acc.min, b.min), max: max_opt(acc.max, b.max))
      })
    }
  }
}

fn compute_sequence_bounds(seq: Sequence, defs: Dict(String, Bounds)) -> Bounds {
  let Sequence(items) = seq
  list.fold(items, Bounds(0, Some(0)), fn(acc, cap) {
    let b = compute_capture_bounds(cap, defs)
    Bounds(min: acc.min + b.min, max: add_opt(acc.max, b.max))
  })
}

fn compute_capture_bounds(
  cap: ast.Capture,
  defs: Dict(String, Bounds),
) -> Bounds {
  compute_repetition_bounds(cap.inner, defs)
}

fn compute_repetition_bounds(
  rep: Repetition,
  defs: Dict(String, Bounds),
) -> Bounds {
  let inner = compute_exclusion_bounds(rep.inner, defs)
  case rep.count {
    None -> inner
    Some(RepCount(min, Exact(max))) ->
      Bounds(min: inner.min * min, max: mul_opt(inner.max, max))
    Some(RepCount(min, ast.None)) ->
      Bounds(min: inner.min * min, max: mul_opt(inner.max, min))
    Some(RepCount(min, Unbounded)) ->
      Bounds(min: inner.min * min, max: None)
  }
}

fn compute_exclusion_bounds(
  excl: Exclusion,
  defs: Dict(String, Bounds),
) -> Bounds {
  compute_range_item_bounds(excl.base, defs)
}

fn compute_range_item_bounds(
  item: RangeItem,
  defs: Dict(String, Bounds),
) -> Bounds {
  case item {
    SingleAtom(atom) -> compute_atom_bounds(atom, defs)
    CharRange(_, _) -> Bounds(1, Some(1))
  }
}

fn compute_atom_bounds(atom: Atom, defs: Dict(String, Bounds)) -> Bounds {
  case atom {
    Literal(content) -> {
      let len = decoded_length(content)
      Bounds(len, Some(len))
    }
    CharClass(_) -> Bounds(1, Some(1))
    Interpolation(name) ->
      result.unwrap(dict.get(defs, name), Bounds(0, Some(0)))
    Group(expr) -> compute_expression_bounds(expr, defs)
    PositionAssertion(_) -> Bounds(0, Some(0))
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn add_opt(a: Option(Int), b: Option(Int)) -> Option(Int) {
  case a, b {
    Some(x), Some(y) -> Some(x + y)
    _, _ -> None
  }
}

fn max_opt(a: Option(Int), b: Option(Int)) -> Option(Int) {
  case a, b {
    Some(x), Some(y) -> Some(int.max(x, y))
    _, _ -> None
  }
}

fn mul_opt(a: Option(Int), n: Int) -> Option(Int) {
  case a {
    Some(x) -> Some(x * n)
    None -> None
  }
}

fn decoded_length(content: String) -> Int {
  do_decoded_length(content, 0)
}

fn do_decoded_length(s: String, count: Int) -> Int {
  case string.pop_grapheme(s) {
    Error(_) -> count
    Ok(#("\\", rest)) ->
      case string.pop_grapheme(rest) {
        Error(_) -> count + 1
        Ok(#("u", rest2)) ->
          do_decoded_length(string.drop_start(rest2, 4), count + 1)
        Ok(#(_, rest2)) -> do_decoded_length(rest2, count + 1)
      }
    Ok(#(_, rest)) -> do_decoded_length(rest, count + 1)
  }
}
