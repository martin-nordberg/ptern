import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import parser/ast.{
  type Atom, type Capture, type Definition, type Exclusion, type Expression,
  type ParsedPtern, type RangeItem, type RepCount, type Repetition, type Sequence,
  Alternation, CharClass, CharRange, Exact, Group, Interpolation, Literal,
  PositionAssertion, RepCount, Sequence, SingleAtom, Unbounded,
}

// ---------------------------------------------------------------------------
// Flags
// ---------------------------------------------------------------------------

pub fn determine_flags(ptern: ParsedPtern) -> String {
  let anns = ptern.annotations
  let case_insensitive =
    list.any(anns, fn(a) { a.name == "case-insensitive" && a.value })
  let multiline =
    list.any(anns, fn(a) { a.name == "multiline" && a.value })
    || has_line_boundary_in_defs(ptern.definitions)
    || has_line_boundary_in_expr(ptern.body)
  case case_insensitive, multiline {
    True, True -> "vim"
    True, False -> "vi"
    False, True -> "vm"
    False, False -> "v"
  }
}

fn has_line_boundary_in_defs(defs: List(Definition)) -> Bool {
  list.any(defs, fn(def) { has_line_boundary_in_expr(def.body) })
}

fn has_line_boundary_in_expr(expr: Expression) -> Bool {
  let Alternation(seqs) = expr
  list.any(seqs, has_line_boundary_in_seq)
}

fn has_line_boundary_in_seq(seq: ast.Sequence) -> Bool {
  let Sequence(items) = seq
  list.any(items, has_line_boundary_in_cap)
}

fn has_line_boundary_in_cap(cap: ast.Capture) -> Bool {
  has_line_boundary_in_excl(cap.inner.inner)
}

fn has_line_boundary_in_excl(excl: ast.Exclusion) -> Bool {
  has_line_boundary_in_item(excl.base)
}

fn has_line_boundary_in_item(item: RangeItem) -> Bool {
  case item {
    SingleAtom(PositionAssertion("line-start")) -> True
    SingleAtom(PositionAssertion("line-end")) -> True
    SingleAtom(Group(expr)) -> has_line_boundary_in_expr(expr)
    _ -> False
  }
}

pub fn determine_ignore_matching(annotations: List(ast.Annotation)) -> Bool {
  list.any(annotations, fn(a) {
    a.name == "replacements-ignore-matching" && a.value
  })
}

// ---------------------------------------------------------------------------
// Duplicate capture name detection (for !substitutable suppression)
// ---------------------------------------------------------------------------

pub fn find_duplicate_capture_names(expr: Expression) -> List(String) {
  let names = collect_all_capture_names_expr(expr)
  find_dups(names, [], [])
}

fn find_dups(
  names: List(String),
  seen: List(String),
  dups: List(String),
) -> List(String) {
  case names {
    [] -> dups
    [name, ..rest] ->
      case list.contains(seen, name) {
        False -> find_dups(rest, [name, ..seen], dups)
        True ->
          case list.contains(dups, name) {
            True -> find_dups(rest, seen, dups)
            False -> find_dups(rest, seen, [name, ..dups])
          }
      }
  }
}

fn collect_all_capture_names_expr(expr: Expression) -> List(String) {
  let Alternation(seqs) = expr
  list.flat_map(seqs, collect_all_capture_names_seq)
}

fn collect_all_capture_names_seq(seq: Sequence) -> List(String) {
  let Sequence(items) = seq
  list.flat_map(items, collect_all_capture_names_cap)
}

fn collect_all_capture_names_cap(cap: Capture) -> List(String) {
  let own = case cap.name {
    None -> []
    Some(name) -> [name]
  }
  list.append(own, collect_all_capture_names_rep(cap.inner))
}

fn collect_all_capture_names_rep(rep: Repetition) -> List(String) {
  collect_all_capture_names_excl(rep.inner)
}

fn collect_all_capture_names_excl(excl: Exclusion) -> List(String) {
  collect_all_capture_names_item(excl.base)
}

fn collect_all_capture_names_item(item: RangeItem) -> List(String) {
  case item {
    SingleAtom(atom) -> collect_all_capture_names_atom(atom)
    CharRange(_, _) -> []
  }
}

fn collect_all_capture_names_atom(atom: Atom) -> List(String) {
  case atom {
    Literal(_) | CharClass(_) | Interpolation(_) | PositionAssertion(_) -> []
    Group(expr) -> collect_all_capture_names_expr(expr)
  }
}

// ---------------------------------------------------------------------------
// Definition compilation (recursive, memoised)
// ---------------------------------------------------------------------------

pub fn compile_definitions(
  defs: List(Definition),
  class_defs: Dict(String, String),
) -> Dict(String, String) {
  let def_bodies: Dict(String, Expression) =
    list.fold(defs, dict.new(), fn(m, def) { dict.insert(m, def.name, def.body) })
  list.fold(defs, dict.new(), fn(compiled, def) {
    compile_def_memo(def.name, def_bodies, compiled, class_defs)
  })
}

fn compile_def_memo(
  name: String,
  def_bodies: Dict(String, Expression),
  compiled: Dict(String, String),
  class_defs: Dict(String, String),
) -> Dict(String, String) {
  case dict.get(compiled, name) {
    Ok(_) -> compiled
    Error(_) -> {
      let assert Ok(body) = dict.get(def_bodies, name)
      let deps = interpolations_in_expression(body)
      let compiled2 =
        list.fold(deps, compiled, fn(c, dep) {
          case dict.has_key(def_bodies, dep) {
            True -> compile_def_memo(dep, def_bodies, c, class_defs)
            False -> c
          }
        })
      let frag = compile_expression(body, compiled2, class_defs, [])
      dict.insert(compiled2, name, frag)
    }
  }
}

// ---------------------------------------------------------------------------
// Class-operand compilation for definitions used in `excluding` contexts
// ---------------------------------------------------------------------------

// Build class-operand strings (e.g. "[13579]") for definitions whose bodies
// are pure char-set expressions. Used by range_item_as_class_operand when an
// interpolation appears as an `excluding` operand.
pub fn compile_class_definitions(defs: List(ast.Definition)) -> Dict(String, String) {
  let def_bodies =
    list.fold(defs, dict.new(), fn(m, def) { dict.insert(m, def.name, def.body) })
  list.fold(defs, dict.new(), fn(class_compiled, def) {
    compile_class_def_memo(def.name, def_bodies, class_compiled)
  })
}

fn compile_class_def_memo(
  name: String,
  def_bodies: Dict(String, Expression),
  class_compiled: Dict(String, String),
) -> Dict(String, String) {
  case dict.get(class_compiled, name) {
    Ok(_) -> class_compiled
    Error(_) ->
      case dict.get(def_bodies, name) {
        Error(_) -> class_compiled
        Ok(body) -> {
          let deps = interpolations_in_expression(body)
          let class_compiled2 =
            list.fold(deps, class_compiled, fn(c, dep) {
              case dict.has_key(def_bodies, dep) {
                True -> compile_class_def_memo(dep, def_bodies, c)
                False -> c
              }
            })
          let class_body = expr_as_class_body(body, class_compiled2)
          case class_body {
            "" -> class_compiled2
            _ -> dict.insert(class_compiled2, name, "[" <> class_body <> "]")
          }
        }
      }
  }
}

// Returns the fragment to place inside `[...]` for a definition body that is
// a pure char-set expression. Returns "" for non-qualifying bodies.
fn expr_as_class_body(
  expr: Expression,
  class_defs: Dict(String, String),
) -> String {
  let Alternation(alts) = expr
  let parts = list.map(alts, seq_as_class_body_ext(_, class_defs))
  case list.any(parts, fn(p) { p == "" }) {
    True -> ""
    False -> string.concat(parts)
  }
}

fn seq_as_class_body_ext(
  seq: Sequence,
  class_defs: Dict(String, String),
) -> String {
  let Sequence(items) = seq
  case items {
    [ast.Capture(
      inner: ast.Repetition(
        inner: ast.Exclusion(base: base, excluded: None),
        count: None,
      ),
      name: None,
    )] -> range_item_as_class_body_ext(base, class_defs)
    _ -> ""
  }
}

fn range_item_as_class_body_ext(
  item: RangeItem,
  class_defs: Dict(String, String),
) -> String {
  case item {
    SingleAtom(Literal(raw)) -> raw_to_class_char(raw)
    SingleAtom(CharClass(name)) -> char_class_standalone(name)
    CharRange(Literal(from_raw), Literal(to_raw)) ->
      "[" <> raw_to_class_char(from_raw) <> "-" <> raw_to_class_char(to_raw) <> "]"
    SingleAtom(Group(Alternation(alts))) ->
      string.concat(list.map(alts, seq_as_class_body_ext(_, class_defs)))
    SingleAtom(Interpolation(dep_name)) ->
      result.unwrap(dict.get(class_defs, dep_name), "")
    _ -> ""
  }
}

// ---------------------------------------------------------------------------
// Expression → regex string
//
// `suppressed` is a list of capture names that should be rendered as unnamed
// groups `(?:...)` rather than named groups `(?<name>...)`. Used when
// `!substitutable = true` allows duplicate capture names — JS regex cannot
// have duplicate named groups, so all but the first occurrence are suppressed.
// Pass `[]` when compiling definitions or validators (no suppression needed).
// ---------------------------------------------------------------------------

pub fn compile_expression(
  expr: Expression,
  defs: Dict(String, String),
  class_defs: Dict(String, String),
  suppressed: List(String),
) -> String {
  let Alternation(seqs) = expr
  let mergeable = case seqs {
    [_, _, ..] -> list.all(seqs, is_class_item)
    _ -> False
  }
  case mergeable {
    True -> "[" <> string.concat(list.map(seqs, sequence_as_class_body)) <> "]"
    False ->
      list.map(seqs, fn(seq) { compile_sequence(seq, defs, class_defs, suppressed) })
      |> string.join("|")
  }
}

fn compile_sequence(
  seq: Sequence,
  defs: Dict(String, String),
  class_defs: Dict(String, String),
  suppressed: List(String),
) -> String {
  let Sequence(items) = seq
  list.map(items, fn(cap) { compile_capture(cap, defs, class_defs, suppressed) })
  |> string.join("")
}

fn compile_capture(
  cap: Capture,
  defs: Dict(String, String),
  class_defs: Dict(String, String),
  suppressed: List(String),
) -> String {
  let body = compile_repetition(cap.inner, defs, class_defs, suppressed)
  case cap.name {
    None -> body
    Some(name) ->
      case list.contains(suppressed, name) {
        True -> "(?:" <> body <> ")"
        False -> "(?<" <> name <> ">" <> body <> ")"
      }
  }
}

fn compile_repetition(
  rep: Repetition,
  defs: Dict(String, String),
  class_defs: Dict(String, String),
  suppressed: List(String),
) -> String {
  let body = compile_exclusion(rep.inner, defs, class_defs, suppressed)
  case rep.count {
    None -> body
    Some(rc) -> wrap_if_needed(body) <> compile_quantifier(rc)
  }
}

fn compile_exclusion(
  excl: Exclusion,
  defs: Dict(String, String),
  class_defs: Dict(String, String),
  suppressed: List(String),
) -> String {
  case excl.excluded {
    None -> compile_range_item(excl.base, defs, class_defs, suppressed)
    Some(excl_item) -> {
      let base_class = range_item_as_class_operand(excl.base, defs, class_defs)
      let excl_class = range_item_as_class_operand(excl_item, defs, class_defs)
      "[" <> base_class <> "--" <> excl_class <> "]"
    }
  }
}

fn compile_range_item(
  item: RangeItem,
  defs: Dict(String, String),
  class_defs: Dict(String, String),
  suppressed: List(String),
) -> String {
  case item {
    SingleAtom(atom) -> compile_atom(atom, defs, class_defs, suppressed)
    CharRange(Literal(from_raw), Literal(to_raw)) ->
      "[" <> raw_to_class_char(from_raw) <> "-" <> raw_to_class_char(to_raw) <> "]"
    CharRange(_, _) -> "(?!)"
  }
}

fn compile_atom(
  atom: Atom,
  defs: Dict(String, String),
  class_defs: Dict(String, String),
  suppressed: List(String),
) -> String {
  case atom {
    Literal(raw) -> raw_to_regex(raw)
    CharClass(name) -> char_class_standalone(name)
    Interpolation(name) ->
      "(?:" <> result.unwrap(dict.get(defs, name), "(?!)") <> ")"
    Group(expr) -> "(?:" <> compile_expression(expr, defs, class_defs, suppressed) <> ")"
    PositionAssertion(name) -> compile_position_assertion(name)
  }
}

// ---------------------------------------------------------------------------
// Range items (class operand helpers — suppression not applicable here)
// ---------------------------------------------------------------------------

// Return a `[...]` or `\p{...}`-style string suitable as one operand of a
// `--` set-subtraction inside a `v`-flag character class.
fn range_item_as_class_operand(
  item: RangeItem,
  defs: Dict(String, String),
  class_defs: Dict(String, String),
) -> String {
  case item {
    SingleAtom(CharClass(name)) -> char_class_standalone(name)
    SingleAtom(Literal(raw)) -> "[" <> raw_to_class_char(raw) <> "]"
    CharRange(Literal(from_raw), Literal(to_raw)) ->
      "[" <> raw_to_class_char(from_raw) <> "-" <> raw_to_class_char(to_raw) <> "]"
    SingleAtom(Group(Alternation(alts))) ->
      "[" <> string.concat(list.map(alts, sequence_as_class_body)) <> "]"
    SingleAtom(Interpolation(name)) ->
      result.unwrap(dict.get(class_defs, name), "[(?!)]")
    SingleAtom(atom) -> "[" <> compile_atom(atom, defs, class_defs, []) <> "]"
    CharRange(_, _) -> "[(?!)]"
  }
}

// ---------------------------------------------------------------------------
// Character-class merging for alternations
// ---------------------------------------------------------------------------

// True when a sequence is a single unnamed, unrepeted character-set item
// (single-char literal, charclass, or char range) that can be merged into [..].
fn is_class_item(seq: Sequence) -> Bool {
  let Sequence(items) = seq
  case items {
    [cap] ->
      case cap.name {
        Some(_) -> False
        None ->
          case cap.inner.count {
            Some(_) -> False
            None -> is_class_range_item(cap.inner.inner.base)
          }
      }
    _ -> False
  }
}

fn is_class_range_item(item: RangeItem) -> Bool {
  case item {
    SingleAtom(Literal(raw)) -> decoded_length(raw) == 1
    SingleAtom(CharClass(_)) -> True
    CharRange(Literal(_), Literal(_)) -> True
    _ -> False
  }
}

// Return the fragment to place inside `[...]` for a qualifying sequence.
fn sequence_as_class_body(seq: Sequence) -> String {
  let Sequence(items) = seq
  let assert [cap] = items
  let excl = cap.inner.inner
  case excl.excluded {
    None -> range_item_as_class_body(excl.base)
    Some(excl_item) ->
      "["
      <> range_item_as_class_operand(excl.base, dict.new(), dict.new())
      <> "--"
      <> range_item_as_class_operand(excl_item, dict.new(), dict.new())
      <> "]"
  }
}

fn range_item_as_class_body(item: RangeItem) -> String {
  case item {
    SingleAtom(Literal(raw)) -> raw_to_class_char(raw)
    SingleAtom(CharClass(name)) -> char_class_standalone(name)
    CharRange(Literal(from_raw), Literal(to_raw)) ->
      "[" <> raw_to_class_char(from_raw) <> "-" <> raw_to_class_char(to_raw) <> "]"
    _ -> ""
  }
}

fn decoded_length(raw: String) -> Int {
  do_decoded_length(raw, 0)
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
// Atoms
// ---------------------------------------------------------------------------

fn compile_position_assertion(name: String) -> String {
  case name {
    "word-start" | "word-end" -> "\\b"
    "line-start" -> "^"
    "line-end" -> "$"
    _ -> "(?!)"
  }
}

// ---------------------------------------------------------------------------
// Quantifiers
// ---------------------------------------------------------------------------

fn compile_quantifier(rc: RepCount) -> String {
  case rc {
    RepCount(0, Exact(1)) -> "?"
    RepCount(0, Unbounded) -> "*"
    RepCount(1, Unbounded) -> "+"
    RepCount(n, Unbounded) -> "{" <> int.to_string(n) <> ",}"
    RepCount(n, ast.None) -> "{" <> int.to_string(n) <> "}"
    RepCount(m, Exact(n)) ->
      "{" <> int.to_string(m) <> "," <> int.to_string(n) <> "}"
  }
}

// ---------------------------------------------------------------------------
// Character classes
// ---------------------------------------------------------------------------

// Returns the standalone regex form: e.g. `[0-9]`, `\p{L}`, `[\s\S]`.
fn char_class_standalone(name: String) -> String {
  case name {
    "Any" -> "[\\s\\S]"
    "Digit" -> "[0-9]"
    "Alpha" -> "[A-Za-z]"
    "Alnum" -> "[A-Za-z0-9]"
    "Lower" -> "[a-z]"
    "Upper" -> "[A-Z]"
    "Word" -> "[A-Za-z0-9_]"
    "Space" -> "[ \\t\\n\\r\\f\\v]"
    "Blank" -> "[ \\t]"
    "Xdigit" -> "[0-9A-Fa-f]"
    "Ascii" -> "[\\x00-\\x7F]"
    "Cntrl" -> "[\\x00-\\x1F\\x7F]"
    "Graph" -> "[\\x21-\\x7E]"
    "Print" -> "[\\x20-\\x7E]"
    "Punct" -> "[\\x21-\\x2F\\x3A-\\x40\\x5B-\\x60\\x7B-\\x7E]"
    // Unicode General Categories — use \p{X} (requires v or u flag)
    "L" | "Letter" -> "\\p{L}"
    "Ll" | "LowercaseLetter" -> "\\p{Ll}"
    "Lu" | "UppercaseLetter" -> "\\p{Lu}"
    "Lm" | "ModifierLetter" -> "\\p{Lm}"
    "Lo" | "OtherLetter" -> "\\p{Lo}"
    "Lt" | "TitlecaseLetter" -> "\\p{Lt}"
    "M" | "Mark" -> "\\p{M}"
    "Mc" | "SpacingMark" -> "\\p{Mc}"
    "Me" | "EnclosingMark" -> "\\p{Me}"
    "Mn" | "NonspacingMark" -> "\\p{Mn}"
    "N" | "Number" -> "\\p{N}"
    "Nd" | "DecimalNumber" -> "\\p{Nd}"
    "Nl" | "LetterNumber" -> "\\p{Nl}"
    "No" | "OtherNumber" -> "\\p{No}"
    "P" | "Punctuation" -> "\\p{P}"
    "Pc" | "ConnectorPunctuation" -> "\\p{Pc}"
    "Pd" | "DashPunctuation" -> "\\p{Pd}"
    "Pe" | "ClosePunctuation" -> "\\p{Pe}"
    "Pf" | "FinalPunctuation" -> "\\p{Pf}"
    "Pi" | "InitialPunctuation" -> "\\p{Pi}"
    "Po" | "OtherPunctuation" -> "\\p{Po}"
    "Ps" | "OpenPunctuation" -> "\\p{Ps}"
    "S" | "Symbol" -> "\\p{S}"
    "Sc" | "CurrencySymbol" -> "\\p{Sc}"
    "Sk" | "ModifierSymbol" -> "\\p{Sk}"
    "Sm" | "MathSymbol" -> "\\p{Sm}"
    "So" | "OtherSymbol" -> "\\p{So}"
    "Z" | "Separator" -> "\\p{Z}"
    "Zl" | "LineSeparator" -> "\\p{Zl}"
    "Zp" | "ParagraphSeparator" -> "\\p{Zp}"
    "Zs" | "SpaceSeparator" -> "\\p{Zs}"
    "C" | "Other" -> "\\p{C}"
    "Cc" | "Control" -> "\\p{Cc}"
    "Cf" | "Format" -> "\\p{Cf}"
    "Cn" | "Unassigned" -> "\\p{Cn}"
    "Co" | "PrivateUse" -> "\\p{Co}"
    "Cs" | "Surrogate" -> "\\p{Cs}"
    _ -> "(?!)"
  }
}

// ---------------------------------------------------------------------------
// Raw literal content → regex string
// ---------------------------------------------------------------------------

// Convert raw literal content to a regex fragment usable outside `[...]`.
fn raw_to_regex(content: String) -> String {
  process_raw(content, False, "")
}

// Convert raw literal content (which must be exactly one decoded character)
// to a string safe for use inside `[...]` (v-flag character class).
fn raw_to_class_char(content: String) -> String {
  process_raw(content, True, "")
}

fn process_raw(s: String, in_cc: Bool, acc: String) -> String {
  case string.pop_grapheme(s) {
    Error(_) -> acc
    Ok(#("\\", rest)) -> process_raw_escape(rest, in_cc, acc)
    Ok(#(c, rest)) -> {
      let escaped = case in_cc {
        True -> class_escape(c)
        False -> regex_escape(c)
      }
      process_raw(rest, in_cc, acc <> escaped)
    }
  }
}

fn process_raw_escape(s: String, in_cc: Bool, acc: String) -> String {
  case string.pop_grapheme(s) {
    Error(_) -> acc
    Ok(#(c, rest)) -> {
      let fragment = case c {
        "n" -> "\\n"
        "t" -> "\\t"
        "r" -> "\\r"
        "a" -> "\\x07"
        "f" -> "\\f"
        "v" -> "\\v"
        "\\" -> "\\\\"
        "'" -> "'"
        "\"" -> "\""
        "u" -> {
          let #(hex, _) = take_chars(rest, 4)
          "\\u" <> hex
        }
        _ -> c
      }
      // For \u, we already consumed the 4 hex digits above; skip them.
      let rest2 = case c {
        "u" -> string.drop_start(rest, 4)
        _ -> rest
      }
      process_raw(rest2, in_cc, acc <> fragment)
    }
  }
}

fn regex_escape(c: String) -> String {
  case c {
    "\\" | "." | "^" | "$" | "*" | "+" | "?" | "(" | ")" | "[" | "]" | "{"
    | "}" | "|" -> "\\" <> c
    _ -> c
  }
}

fn class_escape(c: String) -> String {
  case c {
    "\\" | "]" | "^" | "-" | "(" | ")" | "[" | "{" | "}" | "/" | "|" | "&" ->
      "\\" <> c
    _ -> c
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

// ---------------------------------------------------------------------------
// Wrapping helpers
// ---------------------------------------------------------------------------

// Wrap `s` in `(?:...)` if a quantifier cannot be applied directly to it.
fn wrap_if_needed(s: String) -> String {
  case is_regex_atom(s) {
    True -> s
    False -> "(?:" <> s <> ")"
  }
}

// True when `s` is a single regex atom: one plain char, a character class
// `[...]`, an escape sequence `\X`, a property `\p{...}`, or a group `(?...`.
fn is_regex_atom(s: String) -> Bool {
  let len = string.length(s)
  case len {
    0 | 1 -> True
    _ ->
      string.starts_with(s, "[")
      || string.starts_with(s, "(?")
      || string.starts_with(s, "\\")
  }
}

// ---------------------------------------------------------------------------
// Interpolation name collector (for definition dependency ordering)
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

fn interpolations_in_range_item(item: RangeItem) -> List(String) {
  case item {
    SingleAtom(atom) -> interpolations_in_atom(atom)
    CharRange(_, _) -> []
  }
}

fn interpolations_in_atom(atom: Atom) -> List(String) {
  case atom {
    Literal(_) | CharClass(_) | PositionAssertion(_) -> []
    Interpolation(name) -> [name]
    Group(expr) -> interpolations_in_expression(expr)
  }
}

// ---------------------------------------------------------------------------
// Capture validator collection
// ---------------------------------------------------------------------------

// Walk the expression tree and collect (captureName, regexFragment) pairs for
// every named capture. The fragment is the fully-resolved regex for that
// capture's body and is suitable for use as `^(?:fragment)$`.
pub fn collect_capture_validators(
  expr: Expression,
  defs: Dict(String, String),
  class_defs: Dict(String, String),
) -> List(#(String, String)) {
  let Alternation(seqs) = expr
  list.flat_map(seqs, fn(seq) {
    collect_validators_in_sequence(seq, defs, class_defs)
  })
}

fn collect_validators_in_sequence(
  seq: Sequence,
  defs: Dict(String, String),
  class_defs: Dict(String, String),
) -> List(#(String, String)) {
  let Sequence(items) = seq
  list.flat_map(items, fn(cap) {
    collect_validators_in_capture(cap, defs, class_defs)
  })
}

fn collect_validators_in_capture(
  cap: Capture,
  defs: Dict(String, String),
  class_defs: Dict(String, String),
) -> List(#(String, String)) {
  let body = compile_repetition(cap.inner, defs, class_defs, [])
  let own = case cap.name {
    None -> []
    Some(name) -> [#(name, body)]
  }
  let nested = collect_validators_in_repetition(cap.inner, defs, class_defs)
  list.append(own, nested)
}

fn collect_validators_in_repetition(
  rep: Repetition,
  defs: Dict(String, String),
  class_defs: Dict(String, String),
) -> List(#(String, String)) {
  collect_validators_in_exclusion(rep.inner, defs, class_defs)
}

fn collect_validators_in_exclusion(
  excl: Exclusion,
  defs: Dict(String, String),
  class_defs: Dict(String, String),
) -> List(#(String, String)) {
  collect_validators_in_range_item(excl.base, defs, class_defs)
}

fn collect_validators_in_range_item(
  item: RangeItem,
  defs: Dict(String, String),
  class_defs: Dict(String, String),
) -> List(#(String, String)) {
  case item {
    SingleAtom(atom) -> collect_validators_in_atom(atom, defs, class_defs)
    CharRange(_, _) -> []
  }
}

fn collect_validators_in_atom(
  atom: Atom,
  defs: Dict(String, String),
  class_defs: Dict(String, String),
) -> List(#(String, String)) {
  case atom {
    Group(expr) -> collect_capture_validators(expr, defs, class_defs)
    _ -> []
  }
}

// ---------------------------------------------------------------------------
// RepetitionInfo and compile-with-rep-info variants
//
// These parallel the compile_expression / compile_capture / compile_repetition
// family but thread an integer counter, accumulate RepetitionInfo entries, and
// track a `seen` list of capture names already emitted as named groups.
//
// The `seen` mechanism ensures the FIRST occurrence of any capture name gets
// a `(?<name>...)` group in the main regex; subsequent occurrences (which JS
// regex would reject as duplicate named groups) are suppressed to `(?:...)`.
// This is important for "outer + rep" patterns like:
//   {field} as col (',' {field} as col) * 0..20
// where the outer `col` gets the named group (enabling span-based replacement)
// and the inner `col` is suppressed in the main regex but kept in the sub-regex
// used by the two-pass per-iteration replacement.
// ---------------------------------------------------------------------------

pub type RepetitionInfo {
  RepetitionInfo(
    // Synthetic named group wrapping the whole repetition in the main regex.
    group_name: String,
    // Regex source for one iteration of the repetition (named capture groups
    // present, no suppression). Used for two-pass per-iteration span extraction.
    sub_source: String,
    // Named capture names that appear inside one iteration of the repetition.
    captures: List(String),
  )
}

// Public entry point: compile expression into regex source, RepetitionInfo list,
// and updated counter. `seen` is initialised empty internally.
pub fn compile_expression_with_rep_info(
  expr: Expression,
  defs: Dict(String, String),
  class_defs: Dict(String, String),
  counter: Int,
) -> #(String, List(RepetitionInfo), Int) {
  let #(src, infos, new_ctr, _seen) =
    compile_expression_ri(expr, defs, class_defs, counter, [])
  #(src, infos, new_ctr)
}

// Internal: also returns updated `seen` list so callers can propagate it.
fn compile_expression_ri(
  expr: Expression,
  defs: Dict(String, String),
  class_defs: Dict(String, String),
  counter: Int,
  seen: List(String),
) -> #(String, List(RepetitionInfo), Int, List(String)) {
  let Alternation(seqs) = expr
  let mergeable = case seqs {
    [_, _, ..] -> list.all(seqs, is_class_item)
    _ -> False
  }
  case mergeable {
    True -> #(
      "[" <> string.concat(list.map(seqs, sequence_as_class_body)) <> "]",
      [],
      counter,
      seen,
    )
    False -> {
      let #(rev_parts, infos, final_ctr, final_seen) =
        list.fold(seqs, #([], [], counter, seen), fn(acc, seq) {
          let #(parts, all_infos, ctr, cur_seen) = acc
          let #(s, new_infos, new_ctr, new_seen) =
            compile_sequence_ri(seq, defs, class_defs, ctr, cur_seen)
          #([s, ..parts], list.append(all_infos, new_infos), new_ctr, new_seen)
        })
      #(string.join(list.reverse(rev_parts), "|"), infos, final_ctr, final_seen)
    }
  }
}

fn compile_sequence_ri(
  seq: Sequence,
  defs: Dict(String, String),
  class_defs: Dict(String, String),
  counter: Int,
  seen: List(String),
) -> #(String, List(RepetitionInfo), Int, List(String)) {
  let Sequence(items) = seq
  let #(rev_parts, infos, final_ctr, final_seen) =
    list.fold(items, #([], [], counter, seen), fn(acc, cap) {
      let #(parts, all_infos, ctr, cur_seen) = acc
      let #(s, new_infos, new_ctr, new_seen) =
        compile_capture_ri(cap, defs, class_defs, ctr, cur_seen)
      #([s, ..parts], list.append(all_infos, new_infos), new_ctr, new_seen)
    })
  #(string.join(list.reverse(rev_parts), ""), infos, final_ctr, final_seen)
}

fn compile_capture_ri(
  cap: Capture,
  defs: Dict(String, String),
  class_defs: Dict(String, String),
  counter: Int,
  seen: List(String),
) -> #(String, List(RepetitionInfo), Int, List(String)) {
  let #(body, infos, new_ctr, new_seen) =
    compile_repetition_ri(cap.inner, defs, class_defs, counter, seen)
  case cap.name {
    None -> #(body, infos, new_ctr, new_seen)
    Some(name) ->
      case list.contains(new_seen, name) {
        // Already emitted this name → suppress to avoid duplicate named groups.
        True -> #("(?:" <> body <> ")", infos, new_ctr, new_seen)
        // First occurrence → emit named group and record in seen.
        False -> #(
          "(?<" <> name <> ">" <> body <> ")",
          infos,
          new_ctr,
          [name, ..new_seen],
        )
      }
  }
}

fn compile_repetition_ri(
  rep: Repetition,
  defs: Dict(String, String),
  class_defs: Dict(String, String),
  counter: Int,
  seen: List(String),
) -> #(String, List(RepetitionInfo), Int, List(String)) {
  case rep.count {
    None -> compile_exclusion_ri(rep.inner, defs, class_defs, counter, seen)
    Some(rc) -> {
      let inner_caps = collect_all_capture_names_excl(rep.inner)
      case inner_caps {
        [] -> {
          // No named captures in body; recurse for nested reps but no wrapper.
          let #(body, infos, new_ctr, new_seen) =
            compile_exclusion_ri(rep.inner, defs, class_defs, counter, seen)
          #(wrap_if_needed(body) <> compile_quantifier(rc), infos, new_ctr, new_seen)
        }
        caps -> {
          // Named captures in body — wrap the whole repetition in __rep_N.
          let rep_name = "__rep_" <> int.to_string(counter)
          let #(main_body, inner_infos, new_ctr, new_seen) =
            compile_exclusion_ri(rep.inner, defs, class_defs, counter + 1, seen)
          // Sub-regex: one iteration, no seen-suppression (named groups present).
          let sub_source = compile_exclusion(rep.inner, defs, class_defs, [])
          let main =
            "(?<"
            <> rep_name
            <> ">"
            <> wrap_if_needed(main_body)
            <> compile_quantifier(rc)
            <> ")"
          let info = RepetitionInfo(rep_name, sub_source, caps)
          #(main, [info, ..inner_infos], new_ctr, new_seen)
        }
      }
    }
  }
}

fn compile_exclusion_ri(
  excl: Exclusion,
  defs: Dict(String, String),
  class_defs: Dict(String, String),
  counter: Int,
  seen: List(String),
) -> #(String, List(RepetitionInfo), Int, List(String)) {
  case excl.excluded {
    None -> compile_range_item_ri(excl.base, defs, class_defs, counter, seen)
    Some(excl_item) -> {
      let base_class = range_item_as_class_operand(excl.base, defs, class_defs)
      let excl_class = range_item_as_class_operand(excl_item, defs, class_defs)
      #("[" <> base_class <> "--" <> excl_class <> "]", [], counter, seen)
    }
  }
}

fn compile_range_item_ri(
  item: RangeItem,
  defs: Dict(String, String),
  class_defs: Dict(String, String),
  counter: Int,
  seen: List(String),
) -> #(String, List(RepetitionInfo), Int, List(String)) {
  case item {
    SingleAtom(atom) -> compile_atom_ri(atom, defs, class_defs, counter, seen)
    CharRange(Literal(from_raw), Literal(to_raw)) -> #(
      "[" <> raw_to_class_char(from_raw) <> "-" <> raw_to_class_char(to_raw) <> "]",
      [],
      counter,
      seen,
    )
    CharRange(_, _) -> #("(?!)", [], counter, seen)
  }
}

fn compile_atom_ri(
  atom: Atom,
  defs: Dict(String, String),
  class_defs: Dict(String, String),
  counter: Int,
  seen: List(String),
) -> #(String, List(RepetitionInfo), Int, List(String)) {
  case atom {
    Literal(raw) -> #(raw_to_regex(raw), [], counter, seen)
    CharClass(name) -> #(char_class_standalone(name), [], counter, seen)
    Interpolation(name) -> #(
      "(?:" <> result.unwrap(dict.get(defs, name), "(?!)") <> ")",
      [],
      counter,
      seen,
    )
    Group(expr) -> {
      let #(inner, infos, new_ctr, new_seen) =
        compile_expression_ri(expr, defs, class_defs, counter, seen)
      #("(?:" <> inner <> ")", infos, new_ctr, new_seen)
    }
    PositionAssertion(name) -> #(compile_position_assertion(name), [], counter, seen)
  }
}
