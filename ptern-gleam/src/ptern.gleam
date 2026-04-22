import codegen/codegen
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import lexer/lexer
import lexer/token
import parser/ast.{
  type Atom, type Expression, type RangeItem, Alternation, CharClass, CharRange,
  Exact, Group, Interpolation, Literal, RepCount, Sequence, SingleAtom, Unbounded,
}
import parser/parser
import regex
import semantic/error.{type SemanticError}
import semantic/resolver
import semantic/validator

// ---------------------------------------------------------------------------
// Public types
// ---------------------------------------------------------------------------

pub type CompileError {
  LexError(token.LexError)
  ParseError(ast.ParseError)
  SemanticErrors(List(SemanticError))
}

pub opaque type Ptern {
  Ptern(
    full_re: regex.Regex,
    starts_re: regex.Regex,
    ends_re: regex.Regex,
    contains_re: regex.Regex,
    min_len: Int,
    max_len: Option(Int),
  )
}

// ---------------------------------------------------------------------------
// Compile
// ---------------------------------------------------------------------------

pub fn compile(source: String) -> Result(Ptern, CompileError) {
  use tokens <- result.try(lexer.lex(source) |> result.map_error(LexError))
  use parsed <- result.try(parser.parse(tokens) |> result.map_error(ParseError))
  let semantic_errors =
    list.append(validator.validate(parsed), resolver.resolve(parsed))
  case semantic_errors {
    [_, ..] -> Error(SemanticErrors(semantic_errors))
    [] -> {
      let compiled = codegen.compile(parsed)
      let bounds = compute_ptern_bounds(parsed)
      let src = compiled.source
      let flg = compiled.flags
      Ok(Ptern(
        full_re: regex.make("^(?:" <> src <> ")$", flg),
        starts_re: regex.make("^(?:" <> src <> ")", flg),
        ends_re: regex.make("(?:" <> src <> ")$", flg),
        contains_re: regex.make(src, flg),
        min_len: bounds.min,
        max_len: bounds.max,
      ))
    }
  }
}

// ---------------------------------------------------------------------------
// Matching
// ---------------------------------------------------------------------------

/// Returns `True` if the entire input matches this pattern.
pub fn matches(ptern: Ptern, input: String) -> Bool {
  regex.test_re(ptern.full_re, input)
}

/// Returns `True` if the input starts with this pattern.
pub fn starts(ptern: Ptern, input: String) -> Bool {
  regex.test_re(ptern.starts_re, input)
}

/// Returns `True` if the input ends with this pattern.
pub fn ends(ptern: Ptern, input: String) -> Bool {
  regex.test_re(ptern.ends_re, input)
}

/// Returns `True` if the pattern appears anywhere in the input.
pub fn contained_in(ptern: Ptern, input: String) -> Bool {
  regex.test_re(ptern.contains_re, input)
}

/// Returns the named captures from the first match, or `None` if no match.
pub fn match(
  ptern: Ptern,
  input: String,
) -> Option(Dict(String, String)) {
  regex.exec(ptern.contains_re, input)
  |> option.map(dict.from_list)
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
// Length bounds (internal)
// ---------------------------------------------------------------------------

type Bounds {
  Bounds(min: Int, max: Option(Int))
}

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

fn compute_ptern_bounds(parsed: ast.ParsedPtern) -> Bounds {
  let def_bounds = compute_def_bounds_all(parsed.definitions)
  compute_expression_bounds(parsed.body, def_bounds)
}

fn compute_def_bounds_all(
  defs: List(ast.Definition),
) -> Dict(String, Bounds) {
  let def_exprs: Dict(String, ast.Expression) =
    list.fold(defs, dict.new(), fn(m, def) { dict.insert(m, def.name, def.body) })
  list.fold(defs, dict.new(), fn(acc, def) {
    compute_def_bounds_memo(def.name, def_exprs, acc)
  })
}

fn compute_def_bounds_memo(
  name: String,
  def_exprs: Dict(String, ast.Expression),
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

fn compute_sequence_bounds(
  seq: ast.Sequence,
  defs: Dict(String, Bounds),
) -> Bounds {
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
  rep: ast.Repetition,
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
  excl: ast.Exclusion,
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

// ---------------------------------------------------------------------------
// CLI entry point (not part of the library API)
// ---------------------------------------------------------------------------

pub fn main() {
  Nil
}
