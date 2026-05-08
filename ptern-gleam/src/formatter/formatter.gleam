import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/result
import gleam/set
import gleam/string
import lexer/lexer
import lexer/token
import parser/ast
import parser/parser

// ---------------------------------------------------------------------------
// Public types
// ---------------------------------------------------------------------------

pub type FormatOptions {
  FormatOptions(
    line_width: Int,
    compact: Bool,
    aligned: Bool,
    reordered: Bool,
  )
}

pub fn default_format_options() -> FormatOptions {
  FormatOptions(line_width: 80, compact: False, aligned: True, reordered: False)
}

pub type FormatError {
  FormatLexError(token.LexError)
  FormatParseError(ast.ParseError)
  InvalidLineWidth
}

// ---------------------------------------------------------------------------
// Public entry point
// ---------------------------------------------------------------------------

pub fn format(source: String, options: FormatOptions) -> Result(String, FormatError) {
  case options.line_width < 40 {
    True -> Error(InvalidLineWidth)
    False -> {
      use tokens <- result.try(
        lexer.lex(source) |> result.map_error(FormatLexError),
      )
      use parsed <- result.try(
        parser.parse(tokens) |> result.map_error(FormatParseError),
      )
      Ok(emit_ptern(parsed, options))
    }
  }
}

// ---------------------------------------------------------------------------
// Annotated piece type for line-breaking
// ---------------------------------------------------------------------------

type Piece {
  // Literal text (not a break point).
  PText(String)
  // Sequence-separating space — 1 char; D2/B1 break point.
  PSeqSpace
  // Outermost-alternation separator: " | " (non-compact) or "|" (compact).
  PAlt
}

fn piece_len(p: Piece, compact: Bool) -> Int {
  case p {
    PText(s) -> string.length(s)
    PSeqSpace -> 1
    PAlt ->
      case compact {
        True -> 1
        False -> 3
      }
  }
}

fn pieces_to_str(pieces: List(Piece), compact: Bool) -> String {
  string.concat(
    list.map(pieces, fn(p) {
      case p {
        PText(s) -> s
        PSeqSpace -> " "
        PAlt ->
          case compact {
            True -> "|"
            False -> " | "
          }
      }
    }),
  )
}

// ---------------------------------------------------------------------------
// Top-level emitter
// ---------------------------------------------------------------------------

fn emit_ptern(parsed: ast.ParsedPtern, opts: FormatOptions) -> String {
  let compact = opts.compact
  let aligned = opts.aligned
  let line_width = opts.line_width

  // §5.2 Annotation block (sorted lexicographically by name)
  let sorted_anns =
    list.sort(parsed.annotations, fn(a, b) { string.compare(a.name, b.name) })
  let ann_col = case aligned && sorted_anns != [] {
    True -> compute_align_col(list.map(sorted_anns, fn(a) { a.name }))
    False -> 0
  }
  let ann_lines = emit_annotation_block(sorted_anns, ann_col, aligned, compact)

  // §5.4 Definition block
  let ordered_defs = case opts.reordered {
    True -> reorder_definitions(parsed.definitions)
    False -> parsed.definitions
  }
  let def_col = case aligned && ordered_defs != [] {
    True -> compute_align_col(list.map(ordered_defs, fn(d) { d.name }))
    False -> 0
  }
  let def_lines =
    emit_definition_block(ordered_defs, def_col, aligned, compact, line_width)

  // §5.6–7 Body comments + body expression
  let body_comment_lines =
    list.map(parsed.body_comments, emit_comment_line)
  let body_pieces = emit_expr_pieces(parsed.body, compact)
  let body_lines = break_body_expr(body_pieces, "", line_width, compact)

  // Blank separators between sections (§5)
  let has_anns = sorted_anns != []
  let has_defs = ordered_defs != []
  let ann_sep = case has_anns && { has_defs || True } && !compact {
    True -> [""]
    False -> []
  }
  let def_sep = case has_defs && !compact {
    True -> [""]
    False -> []
  }

  // §4.1 Ptern-level comment block (followed by exactly one blank line)
  let ptern_block = case parsed.ptern_comments {
    [] -> []
    comments -> list.append(list.map(comments, emit_comment_line), [""])
  }

  let all_lines =
    list.flatten([
      ptern_block,
      ann_lines,
      ann_sep,
      def_lines,
      def_sep,
      body_comment_lines,
      body_lines,
    ])

  string.join(all_lines, "\n")
}

// ---------------------------------------------------------------------------
// Comment
// ---------------------------------------------------------------------------

fn emit_comment_line(content: String) -> String {
  "#" <> content
}

// ---------------------------------------------------------------------------
// Annotation block
// ---------------------------------------------------------------------------

fn emit_annotation_block(
  annotations: List(ast.Annotation),
  align_col: Int,
  aligned: Bool,
  compact: Bool,
) -> List(String) {
  let #(_, lines) =
    list.fold(annotations, #(0, []), fn(state, ann) {
      let #(i, acc) = state
      let is_first = i == 0
      let blank_before = case ann.comments, is_first, compact {
        [_, ..], False, False -> [""]
        _, _, _ -> []
      }
      let comment_lines = list.map(ann.comments, emit_comment_line)
      let ann_line = emit_annotation_line(ann, align_col, aligned)
      #(i + 1, list.flatten([acc, blank_before, comment_lines, [ann_line]]))
    })
  lines
}

fn emit_annotation_line(
  ann: ast.Annotation,
  align_col: Int,
  aligned: Bool,
) -> String {
  let val_str = case ann.value {
    True -> "true"
    False -> "false"
  }
  let name_part = "!" <> ann.name
  let spacing = case aligned {
    False -> " "
    True -> string.repeat(" ", align_col - string.length(name_part))
  }
  name_part <> spacing <> "= " <> val_str
}

// ---------------------------------------------------------------------------
// Definition ordering (reordered = True) — §5.1
// ---------------------------------------------------------------------------

fn reorder_definitions(defs: List(ast.Definition)) -> List(ast.Definition) {
  let def_name_set =
    list.fold(defs, set.new(), fn(s, d) { set.insert(s, d.name) })
  let adj =
    list.map(defs, fn(d) {
      #(d.name, collect_def_refs(d.body, def_name_set))
    })
  topo_layer_sort(defs, adj)
}

fn collect_def_refs(
  expr: ast.Expression,
  def_names: set.Set(String),
) -> List(String) {
  let ast.Alternation(branches) = expr
  list.flat_map(branches, fn(seq) { refs_from_seq(seq, def_names) })
}

fn refs_from_seq(seq: ast.Sequence, def_names: set.Set(String)) -> List(String) {
  let ast.Sequence(items) = seq
  list.flat_map(items, fn(cap) { refs_from_capture(cap, def_names) })
}

fn refs_from_capture(
  cap: ast.Capture,
  def_names: set.Set(String),
) -> List(String) {
  let ast.Capture(rep, _) = cap
  refs_from_rep(rep, def_names)
}

fn refs_from_rep(rep: ast.Repetition, def_names: set.Set(String)) -> List(String) {
  let ast.Repetition(excl, _) = rep
  refs_from_excl(excl, def_names)
}

fn refs_from_excl(
  excl: ast.Exclusion,
  def_names: set.Set(String),
) -> List(String) {
  let ast.Exclusion(base, excluded) = excl
  let base_refs = refs_from_range_item(base, def_names)
  let excl_refs = case excluded {
    None -> []
    Some(ri) -> refs_from_range_item(ri, def_names)
  }
  list.append(base_refs, excl_refs)
}

fn refs_from_range_item(
  ri: ast.RangeItem,
  def_names: set.Set(String),
) -> List(String) {
  case ri {
    ast.SingleAtom(a) -> refs_from_atom(a, def_names)
    ast.CharRange(from, to) ->
      list.append(
        refs_from_atom(from, def_names),
        refs_from_atom(to, def_names),
      )
  }
}

fn refs_from_atom(atom: ast.Atom, def_names: set.Set(String)) -> List(String) {
  case atom {
    ast.Interpolation(name) ->
      case set.contains(def_names, name) {
        True -> [name]
        False -> []
      }
    ast.Group(inner) -> collect_def_refs(inner, def_names)
    _ -> []
  }
}

fn topo_layer_sort(
  defs: List(ast.Definition),
  adj: List(#(String, List(String))),
) -> List(ast.Definition) {
  // Compute layer assignments by iterating until stable.
  // Definitions in cycles remain at -1.
  let initial_layers = list.map(adj, fn(p) { #(p.0, -1) })
  let final_layers =
    do_compute_layers(adj, initial_layers, True, 0, list.length(adj) + 1)

  // Sort non-cyclic defs: ascending layer, then alphabetically by name.
  let cycle_names =
    list.fold(final_layers, set.new(), fn(s, pair) {
      case pair.1 < 0 {
        True -> set.insert(s, pair.0)
        False -> s
      }
    })

  let layered_names =
    list.filter(final_layers, fn(p) { p.1 >= 0 })
    |> list.sort(fn(a, b) {
      case int.compare(a.1, b.1) {
        order.Eq -> string.compare(a.0, b.0)
        other -> other
      }
    })
    |> list.map(fn(p) { p.0 })

  let find_def = fn(name) {
    list.find(defs, fn(d) { d.name == name })
    |> result.unwrap(
      ast.Definition(comments: [], name: name, body: ast.Alternation([])),
    )
  }

  let layered_defs = list.map(layered_names, find_def)
  let cycle_defs = list.filter(defs, fn(d) { set.contains(cycle_names, d.name) })
  list.append(layered_defs, cycle_defs)
}

fn do_compute_layers(
  adj: List(#(String, List(String))),
  layers: List(#(String, Int)),
  changed: Bool,
  iters: Int,
  max_iters: Int,
) -> List(#(String, Int)) {
  case changed && iters < max_iters {
    False -> layers
    True -> {
      let #(new_layers, any_changed) =
        list.fold(adj, #(layers, False), fn(state, entry) {
          let #(name, deps) = entry
          let #(cur_layers, cur_changed) = state
          let cur_layer = result.unwrap(list.key_find(cur_layers, name), -1)
          let new_layer = single_layer(deps, cur_layers)
          case new_layer != cur_layer {
            True ->
              #(assoc_set(cur_layers, name, new_layer), True)
            False ->
              #(cur_layers, cur_changed)
          }
        })
      do_compute_layers(adj, new_layers, any_changed, iters + 1, max_iters)
    }
  }
}

fn single_layer(deps: List(String), layers: List(#(String, Int))) -> Int {
  case deps {
    [] -> 0
    _ -> {
      let resolved =
        list.filter_map(deps, fn(d) {
          case list.key_find(layers, d) {
            Ok(l) ->
              case l >= 0 {
                True -> Ok(l)
                False -> Error(Nil)
              }
            _ -> Error(Nil)
          }
        })
      case list.length(resolved) == list.length(deps) {
        True -> list.fold(resolved, 0, fn(m, l) { int.max(m, l) }) + 1
        False -> -1
      }
    }
  }
}

// Set (or replace) a key in an association list.
fn assoc_set(
  pairs: List(#(String, Int)),
  key: String,
  val: Int,
) -> List(#(String, Int)) {
  case pairs {
    [] -> [#(key, val)]
    [#(k, _), ..rest] if k == key -> [#(key, val), ..rest]
    [head, ..rest] -> [head, ..assoc_set(rest, key, val)]
  }
}

// ---------------------------------------------------------------------------
// Definition block
// ---------------------------------------------------------------------------

fn emit_definition_block(
  defs: List(ast.Definition),
  align_col: Int,
  aligned: Bool,
  compact: Bool,
  line_width: Int,
) -> List(String) {
  let #(_, lines) =
    list.fold(defs, #(0, []), fn(state, def) {
      let #(i, acc) = state
      let is_first = i == 0
      let blank_before = case def.comments, is_first, compact {
        [_, ..], False, False -> [""]
        _, _, _ -> []
      }
      let comment_lines = list.map(def.comments, emit_comment_line)
      let def_lines =
        emit_definition(def, align_col, aligned, compact, line_width)
      #(i + 1, list.flatten([acc, blank_before, comment_lines, def_lines]))
    })
  lines
}

fn emit_definition(
  def: ast.Definition,
  align_col: Int,
  aligned: Bool,
  compact: Bool,
  line_width: Int,
) -> List(String) {
  let name_part = def.name
  let spacing = case aligned {
    False -> " "
    True -> string.repeat(" ", align_col - string.length(name_part))
  }
  let name_eq = name_part <> spacing
  let full_prefix = name_eq <> "= "
  let body_pieces = emit_expr_pieces(def.body, compact)
  break_definition(full_prefix, name_eq, body_pieces, line_width, compact)
}

// Break a definition body into formatted lines applying D1→D2→D3→D4.
// full_prefix: e.g. "word  = " (name + alignment + "= ")
// name_eq:     e.g. "word  "  (name + alignment, no "=")
fn break_definition(
  full_prefix: String,
  name_eq: String,
  body_pieces: List(Piece),
  line_width: Int,
  compact: Bool,
) -> List(String) {
  let body_str = pieces_to_str(body_pieces, compact)
  let body_with_semi = body_str <> " ;"
  let full_line = full_prefix <> body_with_semi

  case string.length(full_line) <= line_width {
    True -> [full_line]
    False -> {
      // D1: if body (including " ;") fits in line_width - 4 columns
      case string.length(body_with_semi) <= line_width - 4 {
        True -> {
          let line1 = name_eq <> "="
          let body_lines =
            break_body_expr(body_pieces, "    ", line_width, compact)
          // Append " ;" to the last body line
          case list.reverse(body_lines) {
            [] -> [line1]
            [last, ..rev_rest] ->
              list.flatten([[line1], list.reverse(rev_rest), [last <> " ;"]])
          }
        }
        False -> {
          // D2/D3 on the full single line
          let col = string.length(full_prefix)
          let cont = string.repeat(" ", col)
          break_line(full_prefix, cont, col, body_pieces, " ;", line_width, compact)
        }
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Body expression line breaking
// ---------------------------------------------------------------------------

fn break_body_expr(
  pieces: List(Piece),
  indent: String,
  line_width: Int,
  compact: Bool,
) -> List(String) {
  let col = string.length(indent)
  break_line(indent, indent, col, pieces, "", line_width, compact)
}

// Core recursive line-breaking engine.
// Applies D2/B1 (sequence break) then D3/B2 (alt break) then D4/B3 (as-is).
fn break_line(
  prefix: String,
  cont_prefix: String,
  col: Int,
  pieces: List(Piece),
  suffix: String,
  line_width: Int,
  compact: Bool,
) -> List(String) {
  let flat = pieces_to_str(pieces, compact)
  let full_line = prefix <> flat <> suffix
  case string.length(full_line) <= line_width {
    True -> [full_line]
    False -> {
      let limit = line_width - col
      case find_rightmost_seq_break(pieces, 0, limit, compact) {
        Some(idx) -> {
          let before = list.take(pieces, idx)
          let after = list.drop(pieces, idx + 1)
          let line1 = prefix <> pieces_to_str(before, compact)
          let cont_col = string.length(cont_prefix)
          [
            line1,
            ..break_line(
              cont_prefix,
              cont_prefix,
              cont_col,
              after,
              suffix,
              line_width,
              compact,
            )
          ]
        }
        None ->
          case find_rightmost_alt_break(pieces, 0, limit, compact) {
            Some(idx) -> {
              let before = list.take(pieces, idx)
              let after = list.drop(pieces, idx + 1)
              let line1 = prefix <> pieces_to_str(before, compact)
              // | aligns with `col` (the body's starting column)
              let alt_bar = case compact {
                True -> "|"
                False -> "| "
              }
              let alt_prefix = string.repeat(" ", col) <> alt_bar
              let alt_col = string.length(alt_prefix)
              [
                line1,
                ..break_line(
                  alt_prefix,
                  alt_prefix,
                  alt_col,
                  after,
                  suffix,
                  line_width,
                  compact,
                )
              ]
            }
            None -> [full_line]
          }
      }
    }
  }
}

// Rightmost PSeqSpace whose position p satisfies p <= limit.
fn find_rightmost_seq_break(
  pieces: List(Piece),
  pos: Int,
  limit: Int,
  compact: Bool,
) -> Option(Int) {
  do_find_seq(pieces, pos, limit, compact, 0, None)
}

fn do_find_seq(
  pieces: List(Piece),
  pos: Int,
  limit: Int,
  compact: Bool,
  idx: Int,
  best: Option(Int),
) -> Option(Int) {
  case pieces {
    [] -> best
    [p, ..rest] -> {
      let new_best = case p {
        PSeqSpace ->
          case pos <= limit {
            True -> Some(idx)
            False -> best
          }
        _ -> best
      }
      do_find_seq(
        rest,
        pos + piece_len(p, compact),
        limit,
        compact,
        idx + 1,
        new_best,
      )
    }
  }
}

// Rightmost PAlt whose `|` position satisfies pipe_pos <= limit.
// Non-compact: PAlt = " | " (len 3), pipe at pos+1.
// Compact:     PAlt = "|"   (len 1), pipe at pos.
fn find_rightmost_alt_break(
  pieces: List(Piece),
  pos: Int,
  limit: Int,
  compact: Bool,
) -> Option(Int) {
  do_find_alt(pieces, pos, limit, compact, 0, None)
}

fn do_find_alt(
  pieces: List(Piece),
  pos: Int,
  limit: Int,
  compact: Bool,
  idx: Int,
  best: Option(Int),
) -> Option(Int) {
  case pieces {
    [] -> best
    [p, ..rest] -> {
      let new_best = case p {
        PAlt -> {
          let pipe_pos = case compact {
            True -> pos
            False -> pos + 1
          }
          case pipe_pos <= limit {
            True -> Some(idx)
            False -> best
          }
        }
        _ -> best
      }
      do_find_alt(
        rest,
        pos + piece_len(p, compact),
        limit,
        compact,
        idx + 1,
        new_best,
      )
    }
  }
}

// ---------------------------------------------------------------------------
// Expression piece emitters
// ---------------------------------------------------------------------------

fn emit_expr_pieces(expr: ast.Expression, compact: Bool) -> List(Piece) {
  let ast.Alternation(branches) = expr
  case branches {
    [] -> []
    [branch] -> emit_seq_pieces(branch, compact)
    _ ->
      branches
      |> list.map(fn(seq) { emit_seq_pieces(seq, compact) })
      |> list.intersperse([PAlt])
      |> list.flatten
  }
}

fn emit_seq_pieces(seq: ast.Sequence, compact: Bool) -> List(Piece) {
  let ast.Sequence(items) = seq
  case items {
    [] -> []
    [item] -> emit_capture_pieces(item, compact)
    _ ->
      items
      |> list.map(fn(item) { emit_capture_pieces(item, compact) })
      |> list.intersperse([PSeqSpace])
      |> list.flatten
  }
}

fn emit_capture_pieces(cap: ast.Capture, compact: Bool) -> List(Piece) {
  let ast.Capture(rep, name) = cap
  let base = emit_rep_pieces(rep, compact)
  case name {
    None -> base
    Some(n) -> list.append(base, [PText(" as " <> n)])
  }
}

fn emit_rep_pieces(rep: ast.Repetition, compact: Bool) -> List(Piece) {
  let ast.Repetition(excl, count) = rep
  let excl_str = emit_excl_str(excl, compact)
  case count {
    None -> [PText(excl_str)]
    Some(rc) -> {
      let sep = case compact {
        True -> "*"
        False -> " * "
      }
      [PText(excl_str <> sep <> emit_rep_count_str(rc))]
    }
  }
}

// ---------------------------------------------------------------------------
// String emitters for atoms and nested expressions
// ---------------------------------------------------------------------------

fn emit_excl_str(excl: ast.Exclusion, compact: Bool) -> String {
  let ast.Exclusion(base, excluded) = excl
  case excluded {
    None -> emit_range_item_str(base, compact)
    Some(ex) ->
      emit_range_item_str(base, compact)
      <> " excluding "
      <> emit_range_item_str(ex, compact)
  }
}

fn emit_range_item_str(ri: ast.RangeItem, compact: Bool) -> String {
  case ri {
    ast.SingleAtom(a) -> emit_atom_str(a, compact)
    ast.CharRange(from, to) ->
      emit_atom_str(from, compact) <> ".." <> emit_atom_str(to, compact)
  }
}

fn emit_atom_str(atom: ast.Atom, compact: Bool) -> String {
  case atom {
    ast.Literal(content) ->
      case string.contains(content, "'") {
        True -> "\"" <> content <> "\""
        False -> "'" <> content <> "'"
      }
    ast.CharClass(name) -> "%" <> name
    ast.Interpolation(name) -> "{" <> name <> "}"
    ast.PositionAssertion(name) -> "@" <> name
    ast.Group(inner) -> {
      let inner_str = emit_expr_str(inner, compact)
      case compact {
        True -> "(" <> inner_str <> ")"
        False -> "( " <> inner_str <> " )"
      }
    }
  }
}

fn emit_expr_str(expr: ast.Expression, compact: Bool) -> String {
  let ast.Alternation(branches) = expr
  let sep = case compact {
    True -> "|"
    False -> " | "
  }
  branches
  |> list.map(fn(seq) { emit_seq_str(seq, compact) })
  |> string.join(sep)
}

fn emit_seq_str(seq: ast.Sequence, compact: Bool) -> String {
  let ast.Sequence(items) = seq
  items
  |> list.map(fn(cap) { emit_capture_str(cap, compact) })
  |> string.join(" ")
}

fn emit_capture_str(cap: ast.Capture, compact: Bool) -> String {
  let ast.Capture(rep, name) = cap
  let base = emit_rep_str(rep, compact)
  case name {
    None -> base
    Some(n) -> base <> " as " <> n
  }
}

fn emit_rep_str(rep: ast.Repetition, compact: Bool) -> String {
  let ast.Repetition(excl, count) = rep
  let excl_str = emit_excl_str(excl, compact)
  case count {
    None -> excl_str
    Some(rc) -> {
      let sep = case compact {
        True -> "*"
        False -> " * "
      }
      excl_str <> sep <> emit_rep_count_str(rc)
    }
  }
}

fn emit_rep_count_str(rc: ast.RepCount) -> String {
  let ast.RepCount(min, upper, lazy) = rc
  let base = case upper {
    ast.None -> int.to_string(min)
    ast.Exact(n) -> int.to_string(min) <> ".." <> int.to_string(n)
    ast.Unbounded -> int.to_string(min) <> "..?"
  }
  case lazy {
    False -> base
    True -> base <> " fewest"
  }
}

// ---------------------------------------------------------------------------
// Alignment helper
// ---------------------------------------------------------------------------

// C = max_name_len + 2  (§6.3)
fn compute_align_col(names: List(String)) -> Int {
  let max_len =
    list.fold(names, 0, fn(acc, n) { int.max(acc, string.length(n)) })
  max_len + 2
}
