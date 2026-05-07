import gleam/int
import gleam/list
import gleam/result
import gleam/string
import lexer/token.{
  type LexError, type Token, As, Asterisk, Bang, CharacterClass, Comment,
  DoubleQuotedLiteral, Equals, Excluding, FalseKeyword, Fewest, Identifier,
  Integer, InlineComment, LeftBrace, LeftParen, AlternativeOperator,
  PositionAssertion, QuestionMark, RangeOperator, RightBrace, RightParen,
  Semicolon, SingleQuotedLiteral, TrueKeyword, UnexpectedCharacter,
  UnterminatedString, Whitespace,
}

/// Lex a complete Ptern source string into a flat list of tokens.
///
/// Returns `Ok(tokens)` on success, or `Error(LexError)` if the input
/// contains an unrecognised character, an unterminated string literal,
/// or a `#` that is not the first non-whitespace character on its line.
///
/// Whitespace runs are each collapsed into a single `Whitespace` token.
/// `has_blank_line` is `True` when the run contains a blank line.
/// Comments must start at the beginning of a line and produce a `Comment`
/// token; the trailing newline is emitted separately as `Whitespace`.
/// String literal content retains raw escape sequences; escape decoding
/// is left to a later compilation pass.
pub fn lex(input: String) -> Result(List(Token), LexError) {
  do_lex(input, True, [])
  |> result.map(list.reverse)
}

// Main dispatch loop.  `at_line_start` is True when no non-whitespace
// character has been seen since the last newline (or since the start of
// input).  Tokens are prepended to `acc`; the public `lex` wrapper
// reverses before returning.
fn do_lex(
  input: String,
  at_line_start: Bool,
  acc: List(Token),
) -> Result(List(Token), LexError) {
  case string.pop_grapheme(input) {
    Error(_) -> Ok(acc)
    Ok(#(char, rest)) ->
      case char {
        " " | "\t" -> lex_whitespace(rest, at_line_start, False, acc)
        "\n" | "\r" -> lex_whitespace(rest, True, False, acc)
        "#" ->
          case at_line_start {
            True -> lex_comment(rest, "", acc)
            False -> Error(InlineComment)
          }
        "'" -> lex_single_quoted(rest, "", acc)
        "\"" -> lex_double_quoted(rest, "", acc)
        "%" -> lex_character_class(rest, acc)
        "." -> lex_range_operator(rest, acc)
        "!" -> do_lex(rest, False, [Bang, ..acc])
        "@" -> lex_position_assertion(rest, acc)
        "?" -> do_lex(rest, False, [QuestionMark, ..acc])
        "*" -> do_lex(rest, False, [Asterisk, ..acc])
        "|" -> do_lex(rest, False, [AlternativeOperator, ..acc])
        "=" -> do_lex(rest, False, [Equals, ..acc])
        "{" -> do_lex(rest, False, [LeftBrace, ..acc])
        "}" -> do_lex(rest, False, [RightBrace, ..acc])
        "(" -> do_lex(rest, False, [LeftParen, ..acc])
        ")" -> do_lex(rest, False, [RightParen, ..acc])
        ";" -> do_lex(rest, False, [Semicolon, ..acc])
        _ ->
          case is_digit(char) {
            True -> lex_integer(rest, char, acc)
            False ->
              case is_alpha(char) {
                True -> lex_identifier(rest, char, acc)
                False -> Error(UnexpectedCharacter(char))
              }
          }
      }
  }
}

// Called after the first whitespace character has been consumed.
// `had_newline` tracks whether any `\n`/`\r` has been seen in this run
// (which becomes the next `at_line_start` for `do_lex`).
// `has_blank_line` becomes True when a second `\n` follows after the first,
// possibly with only spaces/tabs in between.
fn lex_whitespace(
  input: String,
  had_newline: Bool,
  has_blank_line: Bool,
  acc: List(Token),
) -> Result(List(Token), LexError) {
  case string.pop_grapheme(input) {
    Ok(#(c, rest)) if c == " " || c == "\t" ->
      lex_whitespace(rest, had_newline, has_blank_line, acc)
    Ok(#(c, rest)) if c == "\n" || c == "\r" ->
      lex_whitespace(rest, True, has_blank_line || had_newline, acc)
    _ ->
      do_lex(input, had_newline, [Whitespace(has_blank_line), ..acc])
  }
}

// Called after the opening `#` has been consumed.  `at_line_start` must be
// True for this to be called (enforced in `do_lex`).
// Collects characters up to (but not including) the line terminator or
// end-of-input, then resumes the main loop — leaving the newline unconsumed
// so it is picked up as a Whitespace token.
fn lex_comment(
  input: String,
  content: String,
  acc: List(Token),
) -> Result(List(Token), LexError) {
  case string.pop_grapheme(input) {
    Error(_) -> Ok([Comment(content), ..acc])
    Ok(#("\n", _)) | Ok(#("\r", _)) ->
      do_lex(input, False, [Comment(content), ..acc])
    Ok(#(char, rest)) -> lex_comment(rest, content <> char, acc)
  }
}

// Called after the opening `'` has been consumed.
fn lex_single_quoted(
  input: String,
  content: String,
  acc: List(Token),
) -> Result(List(Token), LexError) {
  case string.pop_grapheme(input) {
    Error(_) -> Error(UnterminatedString)
    Ok(#("\n", _)) -> Error(UnterminatedString)
    Ok(#("\r", _)) -> Error(UnterminatedString)
    Ok(#("'", rest)) -> do_lex(rest, False, [SingleQuotedLiteral(content), ..acc])
    Ok(#("\\", rest)) -> lex_escape(rest, content, acc, lex_single_quoted)
    Ok(#(char, rest)) -> lex_single_quoted(rest, content <> char, acc)
  }
}

// Called after the opening `"` has been consumed.
fn lex_double_quoted(
  input: String,
  content: String,
  acc: List(Token),
) -> Result(List(Token), LexError) {
  case string.pop_grapheme(input) {
    Error(_) -> Error(UnterminatedString)
    Ok(#("\n", _)) -> Error(UnterminatedString)
    Ok(#("\r", _)) -> Error(UnterminatedString)
    Ok(#("\"", rest)) -> do_lex(rest, False, [DoubleQuotedLiteral(content), ..acc])
    Ok(#("\\", rest)) -> lex_escape(rest, content, acc, lex_double_quoted)
    Ok(#(char, rest)) -> lex_double_quoted(rest, content <> char, acc)
  }
}

// Called after the `\` inside a string literal has been consumed.
fn lex_escape(
  input: String,
  content: String,
  acc: List(Token),
  continue: fn(String, String, List(Token)) -> Result(List(Token), LexError),
) -> Result(List(Token), LexError) {
  case string.pop_grapheme(input) {
    Error(_) -> Error(UnterminatedString)
    Ok(#("u", rest)) ->
      case take_hex_digits(rest, 4) {
        Error(_) -> Error(UnterminatedString)
        Ok(#(digits, rest2)) -> continue(rest2, content <> "\\u" <> digits, acc)
      }
    Ok(#(char, rest)) -> continue(rest, content <> "\\" <> char, acc)
  }
}

fn take_hex_digits(input: String, count: Int) -> Result(#(String, String), Nil) {
  do_take_hex_digits(input, count, "")
}

fn do_take_hex_digits(
  input: String,
  remaining: Int,
  acc: String,
) -> Result(#(String, String), Nil) {
  case remaining {
    0 -> Ok(#(acc, input))
    _ ->
      case string.pop_grapheme(input) {
        Error(_) -> Error(Nil)
        Ok(#(char, rest)) ->
          case is_hex_digit(char) {
            False -> Error(Nil)
            True -> do_take_hex_digits(rest, remaining - 1, acc <> char)
          }
      }
  }
}

// Called after the `%` sigil has been consumed.
fn lex_character_class(
  input: String,
  acc: List(Token),
) -> Result(List(Token), LexError) {
  case string.pop_grapheme(input) {
    Error(_) -> Error(UnexpectedCharacter("%"))
    Ok(#(char, rest)) ->
      case is_upper(char) {
        False -> Error(UnexpectedCharacter(char))
        True -> lex_character_class_rest(rest, char, acc)
      }
  }
}

fn lex_character_class_rest(
  input: String,
  name: String,
  acc: List(Token),
) -> Result(List(Token), LexError) {
  case string.pop_grapheme(input) {
    Ok(#(char, rest)) ->
      case is_alpha(char) {
        True -> lex_character_class_rest(rest, name <> char, acc)
        False -> do_lex(input, False, [CharacterClass(name), ..acc])
      }
    Error(_) -> do_lex(input, False, [CharacterClass(name), ..acc])
  }
}

// Called after the `@` sigil has been consumed.
fn lex_position_assertion(
  input: String,
  acc: List(Token),
) -> Result(List(Token), LexError) {
  case string.pop_grapheme(input) {
    Error(_) -> Error(UnexpectedCharacter("@"))
    Ok(#(char, rest)) ->
      case is_alpha(char) {
        False -> Error(UnexpectedCharacter("@"))
        True -> lex_position_assertion_rest(rest, char, acc)
      }
  }
}

fn lex_position_assertion_rest(
  input: String,
  name: String,
  acc: List(Token),
) -> Result(List(Token), LexError) {
  case string.pop_grapheme(input) {
    Ok(#(char, rest)) ->
      case is_alnum(char) || char == "-" {
        True -> lex_position_assertion_rest(rest, name <> char, acc)
        False -> do_lex(input, False, [PositionAssertion(name), ..acc])
      }
    Error(_) -> do_lex(input, False, [PositionAssertion(name), ..acc])
  }
}

fn lex_integer(
  input: String,
  digits: String,
  acc: List(Token),
) -> Result(List(Token), LexError) {
  case string.pop_grapheme(input) {
    Ok(#(char, rest)) ->
      case is_digit(char) {
        True -> lex_integer(rest, digits <> char, acc)
        False -> finish_integer(digits, input, acc)
      }
    Error(_) -> finish_integer(digits, input, acc)
  }
}

fn finish_integer(
  digits: String,
  rest: String,
  acc: List(Token),
) -> Result(List(Token), LexError) {
  case int.parse(digits) {
    Error(_) -> Error(UnexpectedCharacter(digits))
    Ok(n) -> do_lex(rest, False, [Integer(n), ..acc])
  }
}

fn lex_identifier(
  input: String,
  name: String,
  acc: List(Token),
) -> Result(List(Token), LexError) {
  case string.pop_grapheme(input) {
    Ok(#(char, rest)) ->
      case is_alnum(char) || char == "-" {
        True -> lex_identifier(rest, name <> char, acc)
        False -> finish_identifier(name, input, acc)
      }
    Error(_) -> finish_identifier(name, input, acc)
  }
}

fn finish_identifier(
  name: String,
  rest: String,
  acc: List(Token),
) -> Result(List(Token), LexError) {
  let token = case name {
    "as" -> As
    "excluding" -> Excluding
    "fewest" -> Fewest
    "true" -> TrueKeyword
    "false" -> FalseKeyword
    _ -> Identifier(name)
  }
  do_lex(rest, False, [token, ..acc])
}

// Called after the first `.` has been consumed.
fn lex_range_operator(
  input: String,
  acc: List(Token),
) -> Result(List(Token), LexError) {
  case string.pop_grapheme(input) {
    Ok(#(".", rest)) -> do_lex(rest, False, [RangeOperator, ..acc])
    _ -> Error(UnexpectedCharacter("."))
  }
}

// ---------------------------------------------------------------------------
// Character classification
// ---------------------------------------------------------------------------

fn char_code(char: String) -> Int {
  case string.to_utf_codepoints(char) {
    [cp, ..] -> string.utf_codepoint_to_int(cp)
    _ -> -1
  }
}

fn is_digit(char: String) -> Bool {
  let c = char_code(char)
  c >= 48 && c <= 57
}

fn is_upper(char: String) -> Bool {
  let c = char_code(char)
  c >= 65 && c <= 90
}

fn is_lower(char: String) -> Bool {
  let c = char_code(char)
  c >= 97 && c <= 122
}

fn is_alpha(char: String) -> Bool {
  is_upper(char) || is_lower(char)
}

fn is_alnum(char: String) -> Bool {
  is_alpha(char) || is_digit(char)
}

fn is_hex_digit(char: String) -> Bool {
  let c = char_code(char)
  { c >= 48 && c <= 57 } || { c >= 97 && c <= 102 } || { c >= 65 && c <= 70 }
}
