import gleam/dict.{type Dict}
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import parser/ast.{
  type Capture, type Definition, type Exclusion, type Expression, type Ptern,
  type Repetition, type Sequence, Alternation, CharRange, Group, Interpolation,
  Sequence, SingleAtom,
}
import semantic/error.{
  type SemanticError, CaptureDefinitionConflict, CircularDefinition,
  DuplicateCapture, DuplicateDefinition, UndefinedReference,
}

/// Run all name-resolution checks on a parsed Ptern, returning every error
/// found. An empty list means all names are correctly defined and used.
pub fn resolve(ptern: Ptern) -> List(SemanticError) {
  // 1. Collect definition names; flag duplicates.
  let #(def_names, dup_def_errs) = collect_def_names(ptern.definitions)

  // 2. Detect circular definitions.
  let circ_errs = find_circular_definitions(ptern.definitions, def_names)

  // 3. Check for undefined interpolations inside definition bodies.
  //    Definitions may only reference other definitions (not body captures).
  let def_ref_errs =
    list.flat_map(ptern.definitions, fn(def) {
      check_undefined_refs(def.body, def_names, [])
    })

  // 4. Collect capture names in the body.
  let body_cap_names = captures_in_expression(ptern.body)

  // 5. Flag duplicate capture names in the body.
  let dup_cap_errs =
    find_duplicate_names(body_cap_names, DuplicateCapture)

  // 6. Collect capture names in all definition bodies (for conflict check).
  let def_cap_names =
    list.flat_map(ptern.definitions, fn(def) {
      captures_in_expression(def.body)
    })

  // 7. Flag any capture name that collides with a definition name.
  let all_cap_names = list.append(body_cap_names, def_cap_names)
  let conflict_errs = find_capture_def_conflicts(all_cap_names, def_names)

  // 8. Check for undefined interpolations in the body.
  //    Body interpolations may reference definitions OR body captures.
  let body_ref_errs =
    check_undefined_refs(ptern.body, def_names, body_cap_names)

  list.flatten([
    dup_def_errs,
    circ_errs,
    def_ref_errs,
    dup_cap_errs,
    conflict_errs,
    body_ref_errs,
  ])
}

// ---------------------------------------------------------------------------
// Definition name collection
// ---------------------------------------------------------------------------

fn collect_def_names(
  defs: List(Definition),
) -> #(List(String), List(SemanticError)) {
  let names = list.map(defs, fn(d) { d.name })
  let errors = find_duplicate_names(names, DuplicateDefinition)
  #(dedup_list(names), errors)
}

// ---------------------------------------------------------------------------
// Circular definition detection
// ---------------------------------------------------------------------------

fn find_circular_definitions(
  defs: List(Definition),
  def_names: List(String),
) -> List(SemanticError) {
  // Build a graph: definition name → list of referenced definition names.
  let graph =
    list.fold(defs, dict.new(), fn(g, def) {
      let deps =
        interpolations_in_expression(def.body)
        |> list.filter(fn(d) { list.contains(def_names, d) })
      dict.insert(g, def.name, deps)
    })

  // DFS from each definition; collect, sort, and deduplicate all cycles.
  list.flat_map(def_names, fn(name) { dfs_cycles(graph, name, []) })
  |> list.map(fn(cycle) { list.sort(cycle, string.compare) })
  |> dedup_list_of_lists
  |> list.map(CircularDefinition)
}

fn dfs_cycles(
  graph: Dict(String, List(String)),
  node: String,
  path: List(String),
) -> List(List(String)) {
  case list.contains(path, node) {
    True -> [take_until_inclusive(path, node)]
    False -> {
      let new_path = [node, ..path]
      let deps = result.unwrap(dict.get(graph, node), [])
      list.flat_map(deps, fn(dep) { dfs_cycles(graph, dep, new_path) })
    }
  }
}

// Return the prefix of `lst` up to and including the first occurrence of
// `target`. Used to extract the cycle nodes from the current DFS path.
fn take_until_inclusive(lst: List(String), target: String) -> List(String) {
  case lst {
    [] -> []
    [x, ..rest] ->
      case x == target {
        True -> [x]
        False -> [x, ..take_until_inclusive(rest, target)]
      }
  }
}

// ---------------------------------------------------------------------------
// Undefined reference checking
// ---------------------------------------------------------------------------

// Report any `{name}` in `expr` whose name is not in `def_names` or
// `cap_names`.
fn check_undefined_refs(
  expr: Expression,
  def_names: List(String),
  cap_names: List(String),
) -> List(SemanticError) {
  interpolations_in_expression(expr)
  |> list.filter_map(fn(name) {
    case list.contains(def_names, name) || list.contains(cap_names, name) {
      True -> Error(Nil)
      False -> Ok(UndefinedReference(name))
    }
  })
}

// ---------------------------------------------------------------------------
// Capture / definition name conflict checking
// ---------------------------------------------------------------------------

fn find_capture_def_conflicts(
  cap_names: List(String),
  def_names: List(String),
) -> List(SemanticError) {
  dedup_list(cap_names)
  |> list.filter_map(fn(name) {
    case list.contains(def_names, name) {
      True -> Ok(CaptureDefinitionConflict(name))
      False -> Error(Nil)
    }
  })
}

// ---------------------------------------------------------------------------
// Collecting interpolation names from the AST
// ---------------------------------------------------------------------------

fn interpolations_in_expression(expr: Expression) -> List(String) {
  let Alternation(seqs) = expr
  list.flat_map(seqs, interpolations_in_sequence)
}

fn interpolations_in_sequence(seq: Sequence) -> List(String) {
  let Sequence(items) = seq
  list.flat_map(items, interpolations_in_capture)
}

fn interpolations_in_capture(cap: Capture) -> List(String) {
  interpolations_in_repetition(cap.inner)
}

fn interpolations_in_repetition(rep: Repetition) -> List(String) {
  interpolations_in_exclusion(rep.inner)
}

fn interpolations_in_exclusion(excl: Exclusion) -> List(String) {
  let base = interpolations_in_range_item(excl.base)
  let rest = case excl.excluded {
    None -> []
    Some(item) -> interpolations_in_range_item(item)
  }
  list.append(base, rest)
}

fn interpolations_in_range_item(item: ast.RangeItem) -> List(String) {
  case item {
    SingleAtom(atom) -> interpolations_in_atom(atom)
    CharRange(_, _) -> []
  }
}

fn interpolations_in_atom(atom: ast.Atom) -> List(String) {
  case atom {
    ast.Literal(_) | ast.CharClass(_) -> []
    Interpolation(name) -> [name]
    Group(expr) -> interpolations_in_expression(expr)
  }
}

// ---------------------------------------------------------------------------
// Collecting capture names from the AST
// ---------------------------------------------------------------------------

fn captures_in_expression(expr: Expression) -> List(String) {
  let Alternation(seqs) = expr
  list.flat_map(seqs, captures_in_sequence)
}

fn captures_in_sequence(seq: Sequence) -> List(String) {
  let Sequence(items) = seq
  list.flat_map(items, captures_in_capture)
}

fn captures_in_capture(cap: Capture) -> List(String) {
  let own = case cap.name {
    None -> []
    Some(name) -> [name]
  }
  list.append(own, captures_in_repetition(cap.inner))
}

fn captures_in_repetition(rep: Repetition) -> List(String) {
  captures_in_exclusion(rep.inner)
}

fn captures_in_exclusion(excl: Exclusion) -> List(String) {
  captures_in_range_item(excl.base)
}

fn captures_in_range_item(item: ast.RangeItem) -> List(String) {
  case item {
    SingleAtom(atom) -> captures_in_atom(atom)
    CharRange(_, _) -> []
  }
}

fn captures_in_atom(atom: ast.Atom) -> List(String) {
  case atom {
    ast.Literal(_) | ast.CharClass(_) | Interpolation(_) -> []
    Group(expr) -> captures_in_expression(expr)
  }
}

// ---------------------------------------------------------------------------
// List utilities
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

fn dedup_list(lst: List(String)) -> List(String) {
  list.fold(lst, [], fn(acc, x) {
    case list.contains(acc, x) {
      True -> acc
      False -> [x, ..acc]
    }
  })
  |> list.reverse
}

fn dedup_list_of_lists(lsts: List(List(String))) -> List(List(String)) {
  list.fold(lsts, [], fn(acc, lst) {
    case list.contains(acc, lst) {
      True -> acc
      False -> [lst, ..acc]
    }
  })
  |> list.reverse
}
