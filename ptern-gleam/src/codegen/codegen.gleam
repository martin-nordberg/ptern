import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import parser/ast.{
  type Atom, type Capture, type Definition, type Exclusion, type Expression,
  type ParsedPtern, type RangeItem, type RepCount, type Repetition, type Sequence,
  Alternation, CharClass, CharRange, Exact, Group, Interpolation, Literal,
  PositionAssertion, RepCount, Sequence, SingleAtom, Unbounded,
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

/// The output of compiling a Ptern pattern.
pub type CompiledPtern {
  CompiledPtern(
    /// The regex source string (no delimiters). Pass to `new RegExp(source, flags)`.
    source: String,
    /// The regex flags to use, always including `"v"` (Unicode sets mode).
    flags: String,
    /// Whether `!replacements-ignore-matching = true` was set.
    ignore_matching: Bool,
    /// Per-capture regex fragments: [(captureName, fragment), ...].
    /// Each fragment is suitable for wrapping as `^(?:fragment)$` to validate a replacement value.
    capture_validators: List(#(String, String)),
    /// Whether `!substitutable = true` was set.
    is_substitutable: Bool,
    /// Whether `!substitutions-ignore-matching = true` was set.
    ignore_substitution_matching: Bool,
    /// The substitution plan, present only when is_substitutable is True.
    substitution_plan: Option(SubstitutionPlan),
  )
}

/// Compile a semantically-validated Ptern AST into a JavaScript regex.
pub fn compile(ptern: ParsedPtern) -> CompiledPtern {
  let flags = determine_flags(ptern)
  let ignore = determine_ignore_matching(ptern.annotations)
  let def_bodies =
    list.fold(ptern.definitions, dict.new(), fn(acc, def) {
      dict.insert(acc, def.name, def.body)
    })
  let is_subst =
    list.any(ptern.annotations, fn(a) { a.name == "substitutable" && a.value })
  let ignore_subst =
    list.any(ptern.annotations, fn(a) {
      a.name == "substitutions-ignore-matching" && a.value
    })
  // When substitutable, duplicate capture names are allowed (same name in
  // multiple positions). The compiled regex cannot have duplicate named groups,
  // so suppress the names of any capture that appears more than once.
  let suppressed = case is_subst {
    False -> []
    True -> find_duplicate_capture_names(ptern.body)
  }
  let defs = compile_definitions(ptern.definitions)
  let source = compile_expression_sup(ptern.body, defs, suppressed)
  let validators = collect_capture_validators(ptern.body, defs)
  let cap_reps = collect_capture_reps_in_expr(ptern.body)
  let plan = case is_subst {
    False -> None
    True -> Some(build_plan_expr(ptern.body, def_bodies, cap_reps))
  }
  CompiledPtern(source, flags, ignore, validators, is_subst, ignore_subst, plan)
}

fn find_duplicate_capture_names(expr: Expression) -> List(String) {
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
// Flags
// ---------------------------------------------------------------------------

fn determine_flags(ptern: ParsedPtern) -> String {
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

fn determine_ignore_matching(annotations: List(ast.Annotation)) -> Bool {
  list.any(annotations, fn(a) {
    a.name == "replacements-ignore-matching" && a.value
  })
}

// ---------------------------------------------------------------------------
// Definition compilation (recursive, memoised)
// ---------------------------------------------------------------------------

fn compile_definitions(defs: List(Definition)) -> Dict(String, String) {
  let def_bodies: Dict(String, Expression) =
    list.fold(defs, dict.new(), fn(m, def) { dict.insert(m, def.name, def.body) })

  list.fold(defs, dict.new(), fn(compiled, def) {
    compile_def_memo(def.name, def_bodies, compiled)
  })
}

fn compile_def_memo(
  name: String,
  def_bodies: Dict(String, Expression),
  compiled: Dict(String, String),
) -> Dict(String, String) {
  case dict.get(compiled, name) {
    Ok(_) -> compiled
    Error(_) -> {
      let assert Ok(body) = dict.get(def_bodies, name)
      let deps = interpolations_in_expression(body)
      let compiled2 =
        list.fold(deps, compiled, fn(c, dep) {
          case dict.has_key(def_bodies, dep) {
            True -> compile_def_memo(dep, def_bodies, c)
            False -> c
          }
        })
      let regex = compile_expression(body, compiled2)
      dict.insert(compiled2, name, regex)
    }
  }
}

// ---------------------------------------------------------------------------
// Expression → regex string
// ---------------------------------------------------------------------------

// Compile with a list of capture names that should be made unnamed in the
// compiled regex (used when !substitutable allows duplicate capture names).
fn compile_expression_sup(
  expr: Expression,
  defs: Dict(String, String),
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
      list.map(seqs, fn(seq) { compile_sequence_sup(seq, defs, suppressed) })
      |> string.join("|")
  }
}

fn compile_sequence_sup(
  seq: Sequence,
  defs: Dict(String, String),
  suppressed: List(String),
) -> String {
  let Sequence(items) = seq
  list.map(items, fn(cap) { compile_capture_sup(cap, defs, suppressed) })
  |> string.join("")
}

fn compile_capture_sup(
  cap: Capture,
  defs: Dict(String, String),
  suppressed: List(String),
) -> String {
  let body = compile_repetition_sup(cap.inner, defs, suppressed)
  case cap.name {
    None -> body
    Some(name) ->
      case list.contains(suppressed, name) {
        True -> "(?:" <> body <> ")"
        False -> "(?<" <> name <> ">" <> body <> ")"
      }
  }
}

fn compile_repetition_sup(
  rep: Repetition,
  defs: Dict(String, String),
  suppressed: List(String),
) -> String {
  let body = compile_exclusion_sup(rep.inner, defs, suppressed)
  case rep.count {
    None -> body
    Some(rc) -> wrap_if_needed(body) <> compile_quantifier(rc)
  }
}

fn compile_exclusion_sup(
  excl: Exclusion,
  defs: Dict(String, String),
  suppressed: List(String),
) -> String {
  case excl.excluded {
    None -> compile_range_item_sup(excl.base, defs, suppressed)
    Some(excl_item) -> {
      let base_class = range_item_as_class_operand(excl.base, defs)
      let excl_class = range_item_as_class_operand(excl_item, defs)
      "[" <> base_class <> "--" <> excl_class <> "]"
    }
  }
}

fn compile_range_item_sup(
  item: RangeItem,
  defs: Dict(String, String),
  suppressed: List(String),
) -> String {
  case item {
    SingleAtom(atom) -> compile_atom_sup(atom, defs, suppressed)
    CharRange(Literal(from_raw), Literal(to_raw)) ->
      "[" <> raw_to_class_char(from_raw) <> "-" <> raw_to_class_char(to_raw) <> "]"
    CharRange(_, _) -> "(?!)"
  }
}

fn compile_atom_sup(
  atom: Atom,
  defs: Dict(String, String),
  suppressed: List(String),
) -> String {
  case atom {
    Literal(raw) -> raw_to_regex(raw)
    CharClass(name) -> char_class_standalone(name)
    Interpolation(name) ->
      "(?:" <> result.unwrap(dict.get(defs, name), "(?!)") <> ")"
    Group(expr) -> "(?:" <> compile_expression_sup(expr, defs, suppressed) <> ")"
    PositionAssertion(name) -> compile_position_assertion(name)
  }
}

fn compile_expression(expr: Expression, defs: Dict(String, String)) -> String {
  let Alternation(seqs) = expr
  let mergeable = case seqs {
    [_, _, ..] -> list.all(seqs, is_class_item)
    _ -> False
  }
  case mergeable {
    True -> "[" <> string.concat(list.map(seqs, sequence_as_class_body)) <> "]"
    False ->
      list.map(seqs, fn(seq) { compile_sequence(seq, defs) })
      |> string.join("|")
  }
}

fn compile_sequence(seq: Sequence, defs: Dict(String, String)) -> String {
  let Sequence(items) = seq
  list.map(items, fn(cap) { compile_capture(cap, defs) })
  |> string.join("")
}

fn compile_capture(cap: Capture, defs: Dict(String, String)) -> String {
  let body = compile_repetition(cap.inner, defs)
  case cap.name {
    None -> body
    Some(name) -> "(?<" <> name <> ">" <> body <> ")"
  }
}

fn compile_repetition(rep: Repetition, defs: Dict(String, String)) -> String {
  let body = compile_exclusion(rep.inner, defs)
  case rep.count {
    None -> body
    Some(rc) -> wrap_if_needed(body) <> compile_quantifier(rc)
  }
}

fn compile_exclusion(excl: Exclusion, defs: Dict(String, String)) -> String {
  case excl.excluded {
    None -> compile_range_item_standalone(excl.base, defs)
    Some(excl_item) -> {
      let base_class = range_item_as_class_operand(excl.base, defs)
      let excl_class = range_item_as_class_operand(excl_item, defs)
      "[" <> base_class <> "--" <> excl_class <> "]"
    }
  }
}

// ---------------------------------------------------------------------------
// Range items
// ---------------------------------------------------------------------------

fn compile_range_item_standalone(
  item: RangeItem,
  defs: Dict(String, String),
) -> String {
  case item {
    SingleAtom(atom) -> compile_atom_standalone(atom, defs)
    CharRange(Literal(from_raw), Literal(to_raw)) ->
      "[" <> raw_to_class_char(from_raw) <> "-" <> raw_to_class_char(to_raw) <> "]"
    CharRange(_, _) -> "(?!)"
  }
}

// Return a `[...]` or `\p{...}` or `\d`-style string suitable as one
// operand of a `--` set-subtraction inside a `v`-flag character class.
fn range_item_as_class_operand(
  item: RangeItem,
  defs: Dict(String, String),
) -> String {
  case item {
    SingleAtom(CharClass(name)) -> char_class_standalone(name)
    SingleAtom(Literal(raw)) -> "[" <> raw_to_class_char(raw) <> "]"
    CharRange(Literal(from_raw), Literal(to_raw)) ->
      "[" <> raw_to_class_char(from_raw) <> "-" <> raw_to_class_char(to_raw) <> "]"
    SingleAtom(atom) -> "[" <> compile_atom_standalone(atom, defs) <> "]"
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
      <> range_item_as_class_operand(excl.base, dict.new())
      <> "--"
      <> range_item_as_class_operand(excl_item, dict.new())
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

fn compile_atom_standalone(atom: Atom, defs: Dict(String, String)) -> String {
  case atom {
    Literal(raw) -> raw_to_regex(raw)
    CharClass(name) -> char_class_standalone(name)
    Interpolation(name) ->
      "(?:" <> result.unwrap(dict.get(defs, name), "(?!)") <> ")"
    Group(expr) -> "(?:" <> compile_expression(expr, defs) <> ")"
    PositionAssertion(name) -> compile_position_assertion(name)
  }
}

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
// Interpolation name collector (for dependency ordering)
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
fn collect_capture_validators(
  expr: Expression,
  defs: Dict(String, String),
) -> List(#(String, String)) {
  let Alternation(seqs) = expr
  list.flat_map(seqs, fn(seq) { collect_validators_in_sequence(seq, defs) })
}

fn collect_validators_in_sequence(
  seq: Sequence,
  defs: Dict(String, String),
) -> List(#(String, String)) {
  let Sequence(items) = seq
  list.flat_map(items, fn(cap) { collect_validators_in_capture(cap, defs) })
}

fn collect_validators_in_capture(
  cap: Capture,
  defs: Dict(String, String),
) -> List(#(String, String)) {
  let body = compile_repetition(cap.inner, defs)
  let own = case cap.name {
    None -> []
    Some(name) -> [#(name, body)]
  }
  let nested = collect_validators_in_repetition(cap.inner, defs)
  list.append(own, nested)
}

fn collect_validators_in_repetition(
  rep: Repetition,
  defs: Dict(String, String),
) -> List(#(String, String)) {
  collect_validators_in_exclusion(rep.inner, defs)
}

fn collect_validators_in_exclusion(
  excl: Exclusion,
  defs: Dict(String, String),
) -> List(#(String, String)) {
  collect_validators_in_range_item(excl.base, defs)
}

fn collect_validators_in_range_item(
  item: RangeItem,
  defs: Dict(String, String),
) -> List(#(String, String)) {
  case item {
    SingleAtom(atom) -> collect_validators_in_atom(atom, defs)
    CharRange(_, _) -> []
  }
}

fn collect_validators_in_atom(
  atom: Atom,
  defs: Dict(String, String),
) -> List(#(String, String)) {
  case atom {
    Group(expr) -> collect_capture_validators(expr, defs)
    _ -> []
  }
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
// Substitution plan builder
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
    Some(RepCount(n, ast.None)) -> PlanFixedRep(inner, n)
    Some(RepCount(n, Exact(m))) -> PlanBoundedRep(inner, n, Some(m))
    Some(RepCount(n, Unbounded)) -> PlanBoundedRep(inner, n, None)
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

// Decode a raw literal content string (with escape sequences) to its actual
// text value, for embedding in PlanLiteral nodes.
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
