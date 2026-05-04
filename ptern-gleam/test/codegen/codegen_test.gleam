import codegen/codegen.{type CompiledPtern}
import gleeunit/should
import lexer/lexer
import parser/parser
import ptern

// ---------------------------------------------------------------------------
// Helper: parse and compile in one step
// ---------------------------------------------------------------------------

fn compile(input: String) -> CompiledPtern {
  let assert Ok(tokens) = lexer.lex(input)
  let assert Ok(ptern) = parser.parse(tokens)
  codegen.compile(ptern)
}

fn source(input: String) -> String {
  compile(input).source
}

fn flags(input: String) -> String {
  compile(input).flags
}

// ---------------------------------------------------------------------------
// Flags
// ---------------------------------------------------------------------------

pub fn default_flags_are_v_test() {
  flags("'x'") |> should.equal("v")
}

pub fn case_insensitive_true_adds_i_flag_test() {
  flags("!case-insensitive = true\n'x'") |> should.equal("vi")
}

pub fn case_insensitive_false_no_i_flag_test() {
  flags("!case-insensitive = false\n'x'") |> should.equal("v")
}

// ---------------------------------------------------------------------------
// Literals
// ---------------------------------------------------------------------------

pub fn plain_literal_test() {
  source("'hello'") |> should.equal("hello")
}

pub fn literal_dot_is_escaped_test() {
  source("'a.b'") |> should.equal("a\\.b")
}

pub fn literal_parens_are_escaped_test() {
  source("'(x)'") |> should.equal("\\(x\\)")
}

pub fn literal_pipe_is_escaped_test() {
  source("'a|b'") |> should.equal("a\\|b")
}

pub fn literal_star_is_escaped_test() {
  source("'a*'") |> should.equal("a\\*")
}

pub fn literal_backslash_escape_test() {
  source("'\\\\'") |> should.equal("\\\\")
}

pub fn literal_newline_escape_test() {
  source("'\\n'") |> should.equal("\\n")
}

pub fn literal_tab_escape_test() {
  source("'\\t'") |> should.equal("\\t")
}

pub fn literal_single_quote_escape_test() {
  source("'it\\'s'") |> should.equal("it's")
}

pub fn literal_unicode_escape_test() {
  source("'\\u0041'") |> should.equal("\\u0041")
}

// ---------------------------------------------------------------------------
// Character classes
// ---------------------------------------------------------------------------

pub fn digit_class_test() {
  source("%Digit") |> should.equal("[0-9]")
}

pub fn alpha_class_test() {
  source("%Alpha") |> should.equal("[A-Za-z]")
}

pub fn alnum_class_test() {
  source("%Alnum") |> should.equal("[A-Za-z0-9]")
}

pub fn lower_class_test() {
  source("%Lower") |> should.equal("[a-z]")
}

pub fn upper_class_test() {
  source("%Upper") |> should.equal("[A-Z]")
}

pub fn word_class_test() {
  source("%Word") |> should.equal("[A-Za-z0-9_]")
}

pub fn xdigit_class_test() {
  source("%Xdigit") |> should.equal("[0-9A-Fa-f]")
}

pub fn any_class_test() {
  source("%Any") |> should.equal("[\\s\\S]")
}

pub fn unicode_letter_class_test() {
  source("%L") |> should.equal("\\p{L}")
}

pub fn unicode_letter_long_name_test() {
  source("%Letter") |> should.equal("\\p{L}")
}

pub fn unicode_lowercase_letter_test() {
  source("%Ll") |> should.equal("\\p{Ll}")
}

pub fn unicode_number_class_test() {
  source("%N") |> should.equal("\\p{N}")
}

// ---------------------------------------------------------------------------
// Character ranges
// ---------------------------------------------------------------------------

pub fn char_range_test() {
  source("'a'..'z'") |> should.equal("[a-z]")
}

pub fn char_range_digits_test() {
  source("'0'..'9'") |> should.equal("[0-9]")
}

// ---------------------------------------------------------------------------
// Repetition
// ---------------------------------------------------------------------------

pub fn exact_repetition_test() {
  source("%Digit * 4") |> should.equal("[0-9]{4}")
}

pub fn bounded_repetition_test() {
  source("%Digit * 1..10") |> should.equal("[0-9]{1,10}")
}

pub fn unbounded_repetition_test() {
  source("%Digit * 1..?") |> should.equal("[0-9]+")
}

pub fn zero_or_more_repetition_test() {
  source("%Digit * 0..?") |> should.equal("[0-9]*")
}

pub fn optional_repetition_test() {
  source("%Digit * 0..1") |> should.equal("[0-9]?")
}

pub fn multi_char_literal_repetition_wraps_test() {
  source("'ab' * 3") |> should.equal("(?:ab){3}")
}

pub fn group_repetition_test() {
  source("('a' | 'b') * 3") |> should.equal("(?:[ab]){3}")
}

// ---------------------------------------------------------------------------
// Sequence
// ---------------------------------------------------------------------------

pub fn sequence_test() {
  source("'a' 'b' 'c'") |> should.equal("abc")
}

pub fn mixed_sequence_test() {
  source("'x' %Digit") |> should.equal("x[0-9]")
}

// ---------------------------------------------------------------------------
// Alternation
// ---------------------------------------------------------------------------

pub fn alternation_test() {
  source("'a' | 'b'") |> should.equal("[ab]")
}

pub fn three_way_alternation_test() {
  source("'a' | 'b' | 'c'") |> should.equal("[abc]")
}

// ---------------------------------------------------------------------------
// Capture
// ---------------------------------------------------------------------------

pub fn named_capture_test() {
  source("%Digit * 4 as year") |> should.equal("(?<year>[0-9]{4})")
}

pub fn named_capture_literal_test() {
  source("'hello' as greeting") |> should.equal("(?<greeting>hello)")
}

// ---------------------------------------------------------------------------
// Exclusion
// ---------------------------------------------------------------------------

pub fn exclusion_digit_range_test() {
  source("%Digit excluding '8'..'9'")
  |> should.equal("[[0-9]--[8-9]]")
}

pub fn exclusion_alpha_char_test() {
  source("%Alpha excluding 'x'")
  |> should.equal("[[A-Za-z]--[x]]")
}

pub fn exclusion_range_from_range_test() {
  source("'a'..'z' excluding 'x'")
  |> should.equal("[[a-z]--[x]]")
}

pub fn exclusion_group_single_chars_test() {
  source("%Digit excluding ('1'|'3'|'5'|'7'|'9')")
  |> should.equal("[[0-9]--[13579]]")
}

pub fn exclusion_group_with_range_test() {
  source("%Alpha excluding ('a'..'e' | 'x')")
  |> should.equal("[[A-Za-z]--[[a-e]x]]")
}

pub fn exclusion_group_single_alt_test() {
  source("'a'..'z' excluding ('x')")
  |> should.equal("[[a-z]--[x]]")
}

pub fn exclusion_interpolation_grouped_body_test() {
  source("oddDigit = ('1'|'3'|'5'|'7'|'9');\n%Digit excluding {oddDigit}")
  |> should.equal("[[0-9]--[13579]]")
}

pub fn exclusion_interpolation_flat_body_test() {
  source("odds = '1'|'3'|'5';\n%Alpha excluding {odds}")
  |> should.equal("[[A-Za-z]--[135]]")
}

pub fn exclusion_interpolation_charclass_body_test() {
  source("d = %Digit;\n%Alpha excluding {d}")
  |> should.equal("[[A-Za-z]--[[0-9]]]")
}

// ---------------------------------------------------------------------------
// Groups
// ---------------------------------------------------------------------------

pub fn group_test() {
  source("('a' | 'b')") |> should.equal("(?:[ab])")
}

pub fn nested_group_test() {
  source("(('a' | 'b') 'c')") |> should.equal("(?:(?:[ab])c)")
}

// ---------------------------------------------------------------------------
// Definitions and interpolations
// ---------------------------------------------------------------------------

pub fn definition_interpolation_test() {
  source("d = %Digit; {d}")
  |> should.equal("(?:[0-9])")
}

pub fn definition_repeated_test() {
  source("d = %Digit * 4; {d} '-' {d}")
  |> should.equal("(?:[0-9]{4})-(?:[0-9]{4})")
}

pub fn definition_chain_test() {
  source("a = 'x'; b = {a} 'y'; {b}")
  |> should.equal("(?:(?:x)y)")
}

pub fn definition_with_capture_test() {
  source("yyyy = %Digit * 4; {yyyy} as year")
  |> should.equal("(?<year>(?:[0-9]{4}))")
}

// ---------------------------------------------------------------------------
// Integration: real-world patterns
// ---------------------------------------------------------------------------

pub fn iso_date_test() {
  let input =
    "yyyy = %Digit * 4;\n"
    <> "mm = ('0' '1'..'9') | ('1' '0'..'2');\n"
    <> "dd = ('0' '1'..'9') | ('1'..'2' %Digit) | ('3' '0'..'1');\n"
    <> "{yyyy} as year '-' {mm} as month '-' {dd} as day"

  let result = compile(input)
  result.flags |> should.equal("v")
  // Check that it contains named capture groups
  result.source |> should.not_equal("")
  result.source
  |> should.equal(
    "(?<year>(?:[0-9]{4}))-(?<month>(?:(?:0[1-9])|(?:1[0-2])))-(?<day>(?:(?:0[1-9])|(?:[1-2][0-9])|(?:3[0-1])))",
  )
}

pub fn semantic_version_test() {
  let input = "num = %Digit * 1..10; {num} as major '.' {num} as minor '.' {num} as patch"
  let result = compile(input)
  result.source
  |> should.equal(
    "(?<major>(?:[0-9]{1,10}))\\.(?<minor>(?:[0-9]{1,10}))\\.(?<patch>(?:[0-9]{1,10}))",
  )
}

pub fn zip_code_test() {
  source("%Digit * 5 ('-' %Digit * 4) * 0..1")
  |> should.equal("[0-9]{5}(?:-[0-9]{4})?")
}

// ---------------------------------------------------------------------------
// Position assertions
// ---------------------------------------------------------------------------

pub fn word_start_compiles_to_word_boundary_test() {
  source("@word-start %Alpha * 1..?") |> should.equal("\\b[A-Za-z]+")
}

pub fn word_end_compiles_to_word_boundary_test() {
  source("%Alpha * 1..? @word-end") |> should.equal("[A-Za-z]+\\b")
}

pub fn word_boundaries_around_word_test() {
  source("@word-start %Alpha * 1..? @word-end") |> should.equal("\\b[A-Za-z]+\\b")
}

pub fn line_start_compiles_to_caret_test() {
  source("@line-start %Digit * 1..?") |> should.equal("^[0-9]+")
}

pub fn line_end_compiles_to_dollar_test() {
  source("%Digit * 1..? @line-end") |> should.equal("[0-9]+$")
}

pub fn multiline_annotation_adds_m_flag_test() {
  flags("!multiline = true\n'x'") |> should.equal("vm")
}

pub fn multiline_with_case_insensitive_test() {
  flags("!multiline = true\n!case-insensitive = true\n'x'") |> should.equal("vim")
}

pub fn line_start_auto_enables_multiline_flag_test() {
  flags("@line-start %Alpha * 1..?") |> should.equal("vm")
}

pub fn line_end_auto_enables_multiline_flag_test() {
  flags("%Alpha * 1..? @line-end") |> should.equal("vm")
}

pub fn word_boundary_does_not_add_multiline_flag_test() {
  flags("@word-start %Alpha * 1..? @word-end") |> should.equal("v")
}

pub fn line_boundary_in_definition_auto_enables_multiline_test() {
  flags("row = @line-start %Alpha * 1..? @line-end; {row}") |> should.equal("vm")
}

// ---------------------------------------------------------------------------
// Backreferences
// ---------------------------------------------------------------------------

pub fn backreference_emits_k_syntax_test() {
  source("%Alpha * 1..? as word '-' {word}")
  |> should.equal("(?<word>[A-Za-z]+)-\\k<word>")
}

pub fn backreference_after_definition_interp_emits_correctly_test() {
  // {num} is a definition interpolation; {tag} is a capture backreference
  source("num = %Digit * 1..3; {num} as tag ':' {tag}")
  |> should.equal("(?<tag>(?:[0-9]{1,3})):\\k<tag>")
}

pub fn exclusion_interp_nested_alts_probe_test() {
  // Does (('1'|'3')|('7'|'9')) work as a definition body for excluding?
  // Expected: validator rejects it → compile returns Error
  let result = ptern.compile("oddDigitExcept5 = (('1'|'3')|('7'|'9'));\n%Digit excluding {oddDigitExcept5}")
  case result {
    Error(_) -> "rejected"
    Ok(_) -> "accepted"
  }
  |> should.equal("rejected")
}

pub fn exclusion_interp_range_alts_probe_test() {
  // Does ('a'..'m' | 'n'..'z') as a definition body work?
  source("rangeAlt = ('a'..'m' | 'n'..'z');\n%Alpha excluding {rangeAlt}")
  |> should.equal("[[A-Za-z]--[[a-m][n-z]]]")
}

// ---------------------------------------------------------------------------
// Fewest (lazy quantifiers)
// ---------------------------------------------------------------------------

pub fn fewest_one_or_more_test() {
  source("%Any * 1..? fewest") |> should.equal("[\\s\\S]+?")
}

pub fn fewest_zero_or_more_test() {
  source("%Any * 0..? fewest") |> should.equal("[\\s\\S]*?")
}

pub fn fewest_optional_test() {
  source("%Any * 0..1 fewest") |> should.equal("[\\s\\S]??")
}

pub fn fewest_bounded_test() {
  source("%Any * 3..10 fewest") |> should.equal("[\\s\\S]{3,10}?")
}

pub fn fewest_at_least_n_test() {
  source("%Any * 3..? fewest") |> should.equal("[\\s\\S]{3,}?")
}

pub fn greedy_remains_default_test() {
  source("%Any * 1..?") |> should.equal("[\\s\\S]+")
}
