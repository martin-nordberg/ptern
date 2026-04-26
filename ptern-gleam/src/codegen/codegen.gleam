import codegen/regex
import codegen/substitution
import gleam/dict
import gleam/list
import gleam/option.{type Option, None, Some}
import parser/ast

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
    substitution_plan: Option(substitution.SubstitutionPlan),
  )
}

/// Compile a semantically-validated Ptern AST into a JavaScript regex.
pub fn compile(ptern: ast.ParsedPtern) -> CompiledPtern {
  let flags = regex.determine_flags(ptern)
  let ignore = regex.determine_ignore_matching(ptern.annotations)
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
    True -> regex.find_duplicate_capture_names(ptern.body)
  }
  let defs = regex.compile_definitions(ptern.definitions)
  let source = regex.compile_expression(ptern.body, defs, suppressed)
  let validators = regex.collect_capture_validators(ptern.body, defs)
  let def_bodies =
    list.fold(ptern.definitions, dict.new(), fn(acc, def) {
      dict.insert(acc, def.name, def.body)
    })
  let plan = case is_subst {
    False -> None
    True -> Some(substitution.build_plan(ptern.body, def_bodies))
  }
  CompiledPtern(source, flags, ignore, validators, is_subst, ignore_subst, plan)
}
