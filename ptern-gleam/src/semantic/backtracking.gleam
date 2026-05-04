import gleam/dict.{type Dict}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import parser/ast.{
  type Atom, type Capture, type Exclusion, type Expression, type ParsedPtern,
  type Repetition, type Sequence,
  Alternation, CharClass, CharRange, Exact, Group, Interpolation, Literal,
  PositionAssertion, RepCount, Sequence, SingleAtom, Unbounded,
}
import semantic/error.{
  type SemanticError, AmbiguousAdjacentRepetition, AmbiguousRepetitionAdjacency,
  AmbiguousRepetitionBody,
}

// ---------------------------------------------------------------------------
// Public entry point
// ---------------------------------------------------------------------------

pub fn check(ptern: ParsedPtern) -> List(SemanticError) {
  case annotation_is_true(ptern.annotations, "allow-backtracking") {
    True -> []
    False -> {
      let defs = build_defs(ptern.definitions)
      let ctx = WalkContext(defs: defs)
      check_expression(ptern.body, ctx)
    }
  }
}

// ---------------------------------------------------------------------------
// Walk context
// ---------------------------------------------------------------------------

type WalkContext {
  WalkContext(defs: Dict(String, Expression))
}

// ---------------------------------------------------------------------------
// CharSet — conservative character-set representation for first/last analysis
// ---------------------------------------------------------------------------

type CharSet {
  EmptySet
  AnyChar
  LiteralChar(String)
  NamedClass(String)
  UnionSet(List(CharSet))
  ExclSet(CharSet, CharSet)
}

fn union_set(a: CharSet, b: CharSet) -> CharSet {
  case a, b {
    EmptySet, x | x, EmptySet -> x
    UnionSet(xs), UnionSet(ys) -> UnionSet(list.append(xs, ys))
    UnionSet(xs), y -> UnionSet(list.append(xs, [y]))
    x, UnionSet(ys) -> UnionSet([x, ..ys])
    x, y -> UnionSet([x, y])
  }
}

fn intersects(a: CharSet, b: CharSet) -> Bool {
  case a, b {
    EmptySet, _ | _, EmptySet -> False
    AnyChar, _ | _, AnyChar -> True
    ExclSet(base, excl), other ->
      intersects(base, other) && !is_subset(other, excl)
    other, ExclSet(base, excl) ->
      intersects(other, base) && !is_subset(other, excl)
    UnionSet(xs), _ -> list.any(xs, fn(x) { intersects(x, b) })
    _, UnionSet(ys) -> list.any(ys, fn(y) { intersects(a, y) })
    LiteralChar(x), LiteralChar(y) -> x == y
    NamedClass(n), NamedClass(m) -> named_classes_intersect(n, m)
    NamedClass(n), LiteralChar(c) -> char_in_named_class(c, n)
    LiteralChar(c), NamedClass(n) -> char_in_named_class(c, n)
  }
}

// Conservative subset check: True only when we can definitively prove other ⊆ excl.
// Used to determine whether a charset is provably absent from an ExclSet.
fn is_subset(other: CharSet, excl: CharSet) -> Bool {
  case other, excl {
    LiteralChar(c), LiteralChar(d) -> c == d
    LiteralChar(c), NamedClass(n) -> char_in_named_class(c, n)
    NamedClass(n), NamedClass(m) -> n == m
    _, _ -> False
  }
}

// Pairs that are definitively disjoint. Everything else is assumed to intersect.
fn named_classes_intersect(a: String, b: String) -> Bool {
  case a == b {
    True -> True
    False ->
      !list.any(disjoint_pairs(), fn(pair) {
        pair == #(a, b) || pair == #(b, a)
      })
  }
}

fn disjoint_pairs() -> List(#(String, String)) {
  [
    #("Alpha", "Digit"),
    #("L", "Digit"),
    #("Alpha", "N"),
    #("Upper", "Digit"),
    #("Lower", "Digit"),
    #("Upper", "Lower"),
    #("L", "N"),
    #("Upper", "N"),
    #("Lower", "N"),
    #("Upper", "Space"),
    #("Lower", "Space"),
    #("Alpha", "Space"),
    #("L", "Space"),
    #("N", "Space"),
    #("Digit", "Space"),
    #("Alnum", "Space"),
  ]
}

// Returns True if the single grapheme `c` could belong to the named class.
// For ASCII codepoints the check is precise; for non-ASCII we are conservative
// (return True for classes that have Unicode members, False for pure-ASCII ones).
fn char_in_named_class(c: String, class_name: String) -> Bool {
  case class_name {
    "Any" -> True
    "Digit" -> string.contains("0123456789", c)
    // %N is Unicode numbers; conservative True for non-ASCII single chars
    "N" ->
      string.contains("0123456789", c)
        || !string.contains(
          "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~ \t\n\r",
          c,
        )
    "Upper" -> string.contains("ABCDEFGHIJKLMNOPQRSTUVWXYZ", c)
    "Lower" -> string.contains("abcdefghijklmnopqrstuvwxyz", c)
    // %Alpha/%L include Unicode letters; conservative True for non-ASCII
    "Alpha" | "L" ->
      string.contains(
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz",
        c,
      )
        || !string.contains(
          "0123456789!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~ \t\n\r",
          c,
        )
    "Alnum" ->
      string.contains(
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789",
        c,
      )
    "Xdigit" -> string.contains("0123456789ABCDEFabcdef", c)
    "Space" -> c == " " || c == "\t" || c == "\n" || c == "\r"
    _ -> True
  }
}

// ---------------------------------------------------------------------------
// nullable / first_charset / last_charset
// ---------------------------------------------------------------------------

fn nullable_expr(expr: Expression, defs: Dict(String, Expression)) -> Bool {
  let Alternation(seqs) = expr
  list.any(seqs, fn(seq) { nullable_seq(seq, defs) })
}

fn nullable_seq(seq: Sequence, defs: Dict(String, Expression)) -> Bool {
  let Sequence(items) = seq
  list.all(items, fn(cap) { nullable_cap(cap, defs) })
}

fn nullable_cap(cap: Capture, defs: Dict(String, Expression)) -> Bool {
  nullable_rep(cap.inner, defs)
}

fn nullable_rep(rep: Repetition, defs: Dict(String, Expression)) -> Bool {
  case rep.count {
    None -> nullable_excl(rep.inner, defs)
    Some(RepCount(0, _, _)) -> True
    Some(_) -> False
  }
}

fn nullable_excl(excl: Exclusion, defs: Dict(String, Expression)) -> Bool {
  case excl.base {
    SingleAtom(atom) -> nullable_atom(atom, defs)
    CharRange(_, _) -> False
  }
}

fn nullable_atom(atom: Atom, defs: Dict(String, Expression)) -> Bool {
  case atom {
    PositionAssertion(_) -> True
    Group(inner) -> nullable_expr(inner, defs)
    Interpolation(name) ->
      case dict.get(defs, name) {
        Ok(body) -> nullable_expr(body, defs)
        Error(_) -> False
      }
    Literal(_) | CharClass(_) -> False
  }
}

fn first_charset_expr(
  expr: Expression,
  defs: Dict(String, Expression),
) -> CharSet {
  let Alternation(seqs) = expr
  list.fold(seqs, EmptySet, fn(acc, seq) {
    union_set(acc, first_charset_seq(seq, defs))
  })
}

fn first_charset_seq(seq: Sequence, defs: Dict(String, Expression)) -> CharSet {
  let Sequence(items) = seq
  first_charset_items(items, defs)
}

fn first_charset_items(
  items: List(Capture),
  defs: Dict(String, Expression),
) -> CharSet {
  case items {
    [] -> EmptySet
    [cap, ..rest] -> {
      let cap_first = first_charset_cap(cap, defs)
      case nullable_cap(cap, defs) {
        False -> cap_first
        True -> union_set(cap_first, first_charset_items(rest, defs))
      }
    }
  }
}

fn first_charset_cap(cap: Capture, defs: Dict(String, Expression)) -> CharSet {
  first_charset_rep(cap.inner, defs)
}

fn first_charset_rep(rep: Repetition, defs: Dict(String, Expression)) -> CharSet {
  first_charset_excl(rep.inner, defs)
}

fn first_charset_excl(
  excl: Exclusion,
  defs: Dict(String, Expression),
) -> CharSet {
  let base_cs = case excl.base {
    SingleAtom(atom) -> first_charset_atom(atom, defs)
    CharRange(_, _) -> AnyChar
  }
  case excl.excluded {
    None -> base_cs
    Some(SingleAtom(atom)) -> ExclSet(base_cs, first_charset_atom(atom, defs))
    Some(CharRange(_, _)) -> ExclSet(base_cs, AnyChar)
  }
}

fn first_charset_atom(atom: Atom, defs: Dict(String, Expression)) -> CharSet {
  case atom {
    Literal(s) ->
      case string.pop_grapheme(s) {
        Ok(#(g, _)) -> LiteralChar(g)
        Error(_) -> EmptySet
      }
    CharClass(name) -> NamedClass(name)
    PositionAssertion(_) -> EmptySet
    Group(inner) -> first_charset_expr(inner, defs)
    Interpolation(name) ->
      case dict.get(defs, name) {
        Ok(body) -> first_charset_expr(body, defs)
        Error(_) -> AnyChar
      }
  }
}

fn last_charset_expr(
  expr: Expression,
  defs: Dict(String, Expression),
) -> CharSet {
  let Alternation(seqs) = expr
  list.fold(seqs, EmptySet, fn(acc, seq) {
    union_set(acc, last_charset_seq(seq, defs))
  })
}

fn last_charset_seq(seq: Sequence, defs: Dict(String, Expression)) -> CharSet {
  let Sequence(items) = seq
  last_charset_items(list.reverse(items), defs)
}

fn last_charset_items(
  rev_items: List(Capture),
  defs: Dict(String, Expression),
) -> CharSet {
  case rev_items {
    [] -> EmptySet
    [cap, ..rest] -> {
      let cap_last = last_charset_cap(cap, defs)
      case nullable_cap(cap, defs) {
        False -> cap_last
        True -> union_set(cap_last, last_charset_items(rest, defs))
      }
    }
  }
}

fn last_charset_cap(cap: Capture, defs: Dict(String, Expression)) -> CharSet {
  last_charset_rep(cap.inner, defs)
}

fn last_charset_rep(rep: Repetition, defs: Dict(String, Expression)) -> CharSet {
  last_charset_excl(rep.inner, defs)
}

fn last_charset_excl(
  excl: Exclusion,
  defs: Dict(String, Expression),
) -> CharSet {
  let base_cs = case excl.base {
    SingleAtom(atom) -> last_charset_atom(atom, defs)
    CharRange(_, _) -> AnyChar
  }
  case excl.excluded {
    None -> base_cs
    Some(SingleAtom(atom)) -> ExclSet(base_cs, first_charset_atom(atom, defs))
    Some(CharRange(_, _)) -> ExclSet(base_cs, AnyChar)
  }
}

fn last_charset_atom(atom: Atom, defs: Dict(String, Expression)) -> CharSet {
  case atom {
    Literal(s) -> {
      let graphemes = string.to_graphemes(s)
      case list.last(graphemes) {
        Ok(g) -> LiteralChar(g)
        Error(_) -> EmptySet
      }
    }
    CharClass(name) -> NamedClass(name)
    PositionAssertion(_) -> EmptySet
    Group(inner) -> last_charset_expr(inner, defs)
    Interpolation(name) ->
      case dict.get(defs, name) {
        Ok(body) -> last_charset_expr(body, defs)
        Error(_) -> AnyChar
      }
  }
}

// ---------------------------------------------------------------------------
// Fixed-length detection
// Computes the exact fixed character count of an AST node, or None if it is
// variable-length. Used to distinguish fixed-length alternations (all branches
// the same length) from genuinely variable-length ones.
// ---------------------------------------------------------------------------

fn fixed_len_of_excl(
  excl: Exclusion,
  defs: Dict(String, Expression),
) -> Option(Int) {
  case excl.base {
    CharRange(_, _) -> Some(1)
    SingleAtom(atom) -> fixed_len_of_atom(atom, defs)
  }
}

fn fixed_len_of_atom(
  atom: Atom,
  defs: Dict(String, Expression),
) -> Option(Int) {
  case atom {
    Literal(s) -> Some(string.length(s))
    CharClass(_) -> Some(1)
    PositionAssertion(_) -> Some(0)
    Group(inner) -> fixed_len_of_expr(inner, defs)
    Interpolation(name) ->
      case dict.get(defs, name) {
        Ok(body) -> fixed_len_of_expr(body, defs)
        Error(_) -> None
      }
  }
}

fn fixed_len_of_expr(
  expr: Expression,
  defs: Dict(String, Expression),
) -> Option(Int) {
  let Alternation(seqs) = expr
  case seqs {
    [] -> Some(0)
    [first_seq, ..rest] ->
      case fixed_len_of_seq(first_seq, defs) {
        None -> None
        Some(n) ->
          case list.all(rest, fn(s) { fixed_len_of_seq(s, defs) == Some(n) }) {
            True -> Some(n)
            False -> None
          }
      }
  }
}

fn fixed_len_of_seq(
  seq: Sequence,
  defs: Dict(String, Expression),
) -> Option(Int) {
  let Sequence(items) = seq
  list.fold(items, Some(0), fn(acc, cap) {
    case acc, fixed_len_of_cap(cap, defs) {
      Some(a), Some(b) -> Some(a + b)
      _, _ -> None
    }
  })
}

fn fixed_len_of_cap(
  cap: Capture,
  defs: Dict(String, Expression),
) -> Option(Int) {
  fixed_len_of_rep(cap.inner, defs)
}

fn fixed_len_of_rep(
  rep: Repetition,
  defs: Dict(String, Expression),
) -> Option(Int) {
  case rep.count {
    None -> fixed_len_of_excl(rep.inner, defs)
    Some(RepCount(min, ast.None, _)) ->
      case fixed_len_of_excl(rep.inner, defs) {
        None -> None
        Some(n) -> Some(n * min)
      }
    Some(RepCount(min, Exact(max), _)) ->
      case min == max, fixed_len_of_excl(rep.inner, defs) {
        True, Some(n) -> Some(n * min)
        _, _ -> None
      }
    Some(RepCount(_, Unbounded, _)) -> None
  }
}

// ---------------------------------------------------------------------------
// Variable-length and count helpers
// ---------------------------------------------------------------------------

fn is_variable_count(count: Option(ast.RepCount)) -> Bool {
  case count {
    None -> False
    Some(RepCount(_, ast.None, _)) -> False
    Some(RepCount(min, Exact(max), _)) -> min != max
    Some(RepCount(_, Unbounded, _)) -> True
  }
}

fn is_unbounded_count(count: Option(ast.RepCount)) -> Bool {
  case count {
    Some(RepCount(_, Unbounded, _)) -> True
    _ -> False
  }
}

fn is_variable_length_excl(
  excl: Exclusion,
  defs: Dict(String, Expression),
) -> Bool {
  fixed_len_of_excl(excl, defs) == None
}

// ---------------------------------------------------------------------------
// Recursive walk
// ---------------------------------------------------------------------------

fn check_expression(expr: Expression, ctx: WalkContext) -> List(SemanticError) {
  let Alternation(seqs) = expr
  list.flat_map(seqs, fn(seq) { check_sequence(seq, ctx) })
}

fn check_sequence(seq: Sequence, ctx: WalkContext) -> List(SemanticError) {
  let Sequence(items) = seq
  let adj_errors = check_adjacent_unbounded(items, ctx.defs)
  let inner_errors = list.flat_map(items, fn(cap) { check_capture(cap, ctx) })
  list.append(adj_errors, inner_errors)
}

fn check_capture(cap: Capture, ctx: WalkContext) -> List(SemanticError) {
  check_repetition(cap.inner, ctx)
}

fn check_repetition(rep: Repetition, ctx: WalkContext) -> List(SemanticError) {
  let this_is_counted = rep.count != None

  // Checks 1 & 2: body ambiguity at iteration boundaries
  let check1_2 = case this_is_counted {
    False -> []
    True -> check_repetition_body(rep, ctx.defs)
  }

  let inner_errors = check_exclusion(rep.inner, ctx)
  list.append(check1_2, inner_errors)
}

fn check_repetition_body(
  rep: Repetition,
  defs: Dict(String, Expression),
) -> List(SemanticError) {
  case rep.inner.base {
    SingleAtom(Group(Alternation(branches))) -> {
      let multi = case branches {
        [_, _, ..] -> True
        _ -> False
      }
      case multi && is_variable_count(rep.count) {
        // Check 1: pairwise branch adjacency for variable outer rep
        True -> check_pairwise_branches(branches, defs)
        // Check 2: body self-ambiguity (multi-branch but exact outer, or single branch)
        False -> check_body_self_ambiguity(rep, defs)
      }
    }
    _ -> check_body_self_ambiguity(rep, defs)
  }
}

fn check_pairwise_branches(
  branches: List(Sequence),
  defs: Dict(String, Expression),
) -> List(SemanticError) {
  list.flat_map(list.index_map(branches, fn(b, i) { #(i, b) }), fn(pair_i) {
    let #(i, bi) = pair_i
    list.flat_map(list.index_map(branches, fn(b, j) { #(j, b) }), fn(pair_j) {
      let #(j, bj) = pair_j
      case i < j
        && intersects(last_charset_seq(bi, defs), first_charset_seq(bj, defs))
        || i < j
        && intersects(last_charset_seq(bj, defs), first_charset_seq(bi, defs))
      {
        True -> [
          AmbiguousRepetitionAdjacency(
            branch_a: seq_label(bi),
            branch_b: seq_label(bj),
          ),
        ]
        False -> []
      }
    })
  })
}

fn check_body_self_ambiguity(
  rep: Repetition,
  defs: Dict(String, Expression),
) -> List(SemanticError) {
  case is_variable_length_excl(rep.inner, defs) {
    False -> []
    True -> {
      let fc = first_charset_excl(rep.inner, defs)
      let lc = last_charset_excl(rep.inner, defs)
      case intersects(lc, fc) {
        True -> [AmbiguousRepetitionBody]
        False -> []
      }
    }
  }
}

fn check_exclusion(excl: Exclusion, ctx: WalkContext) -> List(SemanticError) {
  case excl.base {
    SingleAtom(atom) -> check_atom(atom, ctx)
    CharRange(_, _) -> []
  }
}

fn check_atom(atom: Atom, ctx: WalkContext) -> List(SemanticError) {
  case atom {
    Group(inner) -> check_expression(inner, ctx)
    Literal(_) | CharClass(_) | PositionAssertion(_) | Interpolation(_) -> []
  }
}

// ---------------------------------------------------------------------------
// Check 4: adjacent unbounded repetitions in a sequence
// ---------------------------------------------------------------------------

fn check_adjacent_unbounded(
  items: List(Capture),
  defs: Dict(String, Expression),
) -> List(SemanticError) {
  case items {
    [] | [_] -> []
    [cap_a, cap_b, ..rest] -> {
      let this_pair = case
        is_unbounded_count(cap_a.inner.count)
        && is_unbounded_count(cap_b.inner.count)
      {
        False -> []
        True -> {
          let lc = last_charset_cap(cap_a, defs)
          let fc = first_charset_cap(cap_b, defs)
          case intersects(lc, fc) {
            True -> [AmbiguousAdjacentRepetition]
            False -> []
          }
        }
      }
      list.append(this_pair, check_adjacent_unbounded([cap_b, ..rest], defs))
    }
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn annotation_is_true(
  annotations: List(ast.Annotation),
  name: String,
) -> Bool {
  list.any(annotations, fn(a) { a.name == name && a.value })
}

fn build_defs(
  definitions: List(ast.Definition),
) -> Dict(String, Expression) {
  list.fold(definitions, dict.new(), fn(acc, def) {
    dict.insert(acc, def.name, def.body)
  })
}

fn seq_label(seq: Sequence) -> String {
  let Sequence(items) = seq
  string.join(list.map(items, capture_label), " ")
}

fn capture_label(cap: Capture) -> String {
  rep_label(cap.inner)
}

fn rep_label(rep: Repetition) -> String {
  excl_label(rep.inner)
}

fn excl_label(excl: Exclusion) -> String {
  case excl.base {
    SingleAtom(atom) -> atom_label(atom)
    CharRange(from, to) -> atom_label(from) <> ".." <> atom_label(to)
  }
}

fn atom_label(atom: Atom) -> String {
  case atom {
    Literal(s) -> "'" <> s <> "'"
    CharClass(name) -> "%" <> name
    PositionAssertion(name) -> "@" <> name
    Interpolation(name) -> "{" <> name <> "}"
    Group(_) -> "(...)"
  }
}
