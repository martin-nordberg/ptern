import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import parser/ast.{
  type Atom, type Capture, type Definition, type Exclusion, type Expression,
  type Ptern, type RangeItem, type RepCount, type Repetition, type Sequence,
  Alternation, CharClass, CharRange, Exact, Group, Interpolation, Literal,
  RepCount, Sequence, SingleAtom, Unbounded,
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// The output of compiling a Ptern pattern.
pub type CompiledPtern {
  CompiledPtern(
    /// The regex source string (no delimiters). Pass to `new RegExp(source, flags)`.
    source: String,
    /// The regex flags to use, always including `"v"` (Unicode sets mode).
    flags: String,
  )
}

/// Compile a semantically-validated Ptern AST into a JavaScript regex.
pub fn compile(ptern: Ptern) -> CompiledPtern {
  let flags = determine_flags(ptern.annotations)
  let defs = compile_definitions(ptern.definitions)
  let source = compile_expression(ptern.body, defs)
  CompiledPtern(source, flags)
}

// ---------------------------------------------------------------------------
// Flags
// ---------------------------------------------------------------------------

fn determine_flags(annotations: List(ast.Annotation)) -> String {
  let case_insensitive =
    list.any(annotations, fn(a) { a.name == "case-insensitive" && a.value })
  case case_insensitive {
    True -> "vi"
    False -> "v"
  }
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
    Literal(_) | CharClass(_) -> []
    Interpolation(name) -> [name]
    Group(expr) -> interpolations_in_expression(expr)
  }
}
