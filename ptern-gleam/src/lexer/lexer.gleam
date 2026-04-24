import gleam/int
import gleam/list
import gleam/result
import gleam/string
import lexer/token.{
  type LexError, type Token, As, At, Asterisk, Bang, CharacterClass, Comment,
  DoubleQuotedLiteral, Equals, Excluding, FalseKeyword, Identifier, Integer,
  LeftBrace, LeftParen, AlternativeOperator, PositionAssertion, QuestionMark,
  RangeOperator, RightBrace, RightParen, Semicolon, SingleQuotedLiteral,
  TrueKeyword, UnexpectedCharacter, UnterminatedString, Whitespace,
}

/// Lex a complete Ptern source string into a flat list of tokens.
///
/// Returns `Ok(tokens)` on success, or `Error(LexError)` if the input
/// contains an unrecognised character or an unterminated string literal.
///
/// Whitespace runs are each collapsed into a single `Whitespace` token.
/// Comments run from `#` to the end of the line and produce a `Comment`
/// token; the trailing newline is emitted separately as `Whitespace`.
/// String literal content retains raw escape sequences; escape decoding
/// is left to a later compilation pass.
pub fn lex(input: String) -> Result(List(Token), LexError) {
  do_lex(input, [])
  |> result.map(list.reverse)
}

// Main dispatch loop. Tokens are prepended to `acc` (i.e. stored in reverse
// order); the public `lex` wrapper reverses the list before returning.
fn do_lex(input: String, acc: List(Token)) -> Result(List(Token), LexError) {
  case string.pop_grapheme(input) {
    Error(_) -> Ok(acc)
    Ok(#(char, rest)) ->
      case char {
        " " | "\t" | "\n" | "\r" -> lex_whitespace(rest, acc)
        "#" -> lex_comment(rest, "", acc)
        "'" -> lex_single_quoted(rest, "", acc)
        "\"" -> lex_double_quoted(rest, "", acc)
        "%" -> lex_character_class(rest, acc)
        "." -> lex_range_operator(rest, acc)
        "!" -> do_lex(rest, [Bang, ..acc])
        "@" -> lex_position_assertion(rest, acc)
        "?" -> do_lex(rest, [QuestionMark, ..acc])
        "*" -> do_lex(rest, [Asterisk, ..acc])
        "|" -> do_lex(rest, [AlternativeOperator, ..acc])
        "=" -> do_lex(rest, [Equals, ..acc])
        "{" -> do_lex(rest, [LeftBrace, ..acc])
        "}" -> do_lex(rest, [RightBrace, ..acc])
        "(" -> do_lex(rest, [LeftParen, ..acc])
        ")" -> do_lex(rest, [RightParen, ..acc])
        ";" -> do_lex(rest, [Semicolon, ..acc])
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
// Continues consuming whitespace so the entire run becomes one token.
fn lex_whitespace(
  input: String,
  acc: List(Token),
) -> Result(List(Token), LexError) {
  case string.pop_grapheme(input) {
    Ok(#(char, rest)) ->
      case char == " " || char == "\t" || char == "\n" || char == "\r" {
        True -> lex_whitespace(rest, acc)
        False -> do_lex(input, [Whitespace, ..acc])
      }
    Error(_) -> do_lex(input, [Whitespace, ..acc])
  }
}

// Called after the opening `#` has been consumed.
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
    Ok(#("\n", _)) | Ok(#("\r", _)) -> do_lex(input, [Comment(content), ..acc])
    Ok(#(char, rest)) -> lex_comment(rest, content <> char, acc)
  }
}

// Called after the opening `'` has been consumed.
// Collects characters until the matching closing `'`, handling backslash
// escapes along the way. Bare newlines and end-of-input are errors.
fn lex_single_quoted(
  input: String,
  content: String,
  acc: List(Token),
) -> Result(List(Token), LexError) {
  case string.pop_grapheme(input) {
    Error(_) -> Error(UnterminatedString)
    Ok(#("\n", _)) -> Error(UnterminatedString)
    Ok(#("\r", _)) -> Error(UnterminatedString)
    Ok(#("'", rest)) -> do_lex(rest, [SingleQuotedLiteral(content), ..acc])
    Ok(#("\\", rest)) -> lex_escape(rest, content, acc, lex_single_quoted)
    Ok(#(char, rest)) -> lex_single_quoted(rest, content <> char, acc)
  }
}

// Called after the opening `"` has been consumed.
// Mirrors lex_single_quoted but closes on `"`.
fn lex_double_quoted(
  input: String,
  content: String,
  acc: List(Token),
) -> Result(List(Token), LexError) {
  case string.pop_grapheme(input) {
    Error(_) -> Error(UnterminatedString)
    Ok(#("\n", _)) -> Error(UnterminatedString)
    Ok(#("\r", _)) -> Error(UnterminatedString)
    Ok(#("\"", rest)) -> do_lex(rest, [DoubleQuotedLiteral(content), ..acc])
    Ok(#("\\", rest)) -> lex_escape(rest, content, acc, lex_double_quoted)
    Ok(#(char, rest)) -> lex_double_quoted(rest, content <> char, acc)
  }
}

// Called after the `\` inside a string literal has been consumed.
// Handles the character immediately following the backslash:
//   - `\uABCD`  — four-hex-digit Unicode escape, stored as `\uABCD`
//   - `\<char>` — any other escape (e.g. `\n`, `\'`), stored as `\<char>`
// Raw escape text is appended to `content`; actual decoding is deferred.
// `continue` is the calling string lexer (single- or double-quoted), used
// to resume scanning after the escape sequence.
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

// Consume exactly `count` hex digits from the front of `input`.
// Returns the digits and the remaining input, or Error(Nil) if fewer
// than `count` hex digits are available.
fn take_hex_digits(input: String, count: Int) -> Result(#(String, String), Nil) {
  do_take_hex_digits(input, count, "")
}

// Tail-recursive worker for take_hex_digits.
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
// The first character must be an ASCII uppercase letter (the start of the
// class name), followed by zero or more lowercase letters.
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

// Continues consuming letters after the initial uppercase letter of a
// character class name, accepting both lowercase and uppercase (to support
// PascalCase names such as `%LowercaseLetter`), then emits the completed
// CharacterClass token.
fn lex_character_class_rest(
  input: String,
  name: String,
  acc: List(Token),
) -> Result(List(Token), LexError) {
  case string.pop_grapheme(input) {
    Ok(#(char, rest)) ->
      case is_alpha(char) {
        True -> lex_character_class_rest(rest, name <> char, acc)
        False -> do_lex(input, [CharacterClass(name), ..acc])
      }
    Error(_) -> do_lex(input, [CharacterClass(name), ..acc])
  }
}

// Called after the `@` sigil has been consumed.
// Reads the following identifier (letters, digits, hyphens) and produces a
// PositionAssertion token. A bare `@` with no identifier falls back to At.
fn lex_position_assertion(
  input: String,
  acc: List(Token),
) -> Result(List(Token), LexError) {
  case string.pop_grapheme(input) {
    Error(_) -> do_lex(input, [At, ..acc])
    Ok(#(char, rest)) ->
      case is_alpha(char) {
        False -> do_lex(input, [At, ..acc])
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
        False -> do_lex(input, [PositionAssertion(name), ..acc])
      }
    Error(_) -> do_lex(input, [PositionAssertion(name), ..acc])
  }
}

// Accumulates digit characters into `digits`, then delegates to
// finish_integer once a non-digit (or end-of-input) is encountered.
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

// Parses the accumulated digit string and emits an Integer token.
// `rest` is the unconsumed input passed back to the main loop.
fn finish_integer(
  digits: String,
  rest: String,
  acc: List(Token),
) -> Result(List(Token), LexError) {
  case int.parse(digits) {
    Error(_) -> Error(UnexpectedCharacter(digits))
    Ok(n) -> do_lex(rest, [Integer(n), ..acc])
  }
}

// Accumulates letters, digits, and hyphens into `name`, then delegates
// to finish_identifier once the identifier ends.
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

// Checks whether the accumulated name is a keyword (`as`, `excluding`,
// `true`, `false`), emits the appropriate token, and resumes the main loop.
fn finish_identifier(
  name: String,
  rest: String,
  acc: List(Token),
) -> Result(List(Token), LexError) {
  let token = case name {
    "as" -> As
    "excluding" -> Excluding
    "true" -> TrueKeyword
    "false" -> FalseKeyword
    _ -> Identifier(name)
  }
  do_lex(rest, [token, ..acc])
}

// Called after the first `.` has been consumed. The range operator is
// always `..`; a lone `.` is not a valid token.
fn lex_range_operator(
  input: String,
  acc: List(Token),
) -> Result(List(Token), LexError) {
  case string.pop_grapheme(input) {
    Ok(#(".", rest)) -> do_lex(rest, [RangeOperator, ..acc])
    _ -> Error(UnexpectedCharacter("."))
  }
}

// ---------------------------------------------------------------------------
// Character classification
//
// Gleam's `>=` / `<=` operators only work on Int, not String, so all range
// checks are performed on Unicode codepoint integers.
// ---------------------------------------------------------------------------

// Returns the Unicode codepoint of a single-grapheme string, or -1 if the
// string is empty (which should never happen in normal lexer use).
fn char_code(char: String) -> Int {
  case string.to_utf_codepoints(char) {
    [cp, ..] -> string.utf_codepoint_to_int(cp)
    _ -> -1
  }
}

// `0`–`9`  (codepoints 48–57)
fn is_digit(char: String) -> Bool {
  let c = char_code(char)
  c >= 48 && c <= 57
}

// `A`–`Z`  (codepoints 65–90)
fn is_upper(char: String) -> Bool {
  let c = char_code(char)
  c >= 65 && c <= 90
}

// `a`–`z`  (codepoints 97–122)
fn is_lower(char: String) -> Bool {
  let c = char_code(char)
  c >= 97 && c <= 122
}

// Any ASCII letter.
fn is_alpha(char: String) -> Bool {
  is_upper(char) || is_lower(char)
}

// Any ASCII letter or digit.
fn is_alnum(char: String) -> Bool {
  is_alpha(char) || is_digit(char)
}

// `0`–`9`, `a`–`f`, `A`–`F`  (used when lexing `\uABCD` escapes)
fn is_hex_digit(char: String) -> Bool {
  let c = char_code(char)
  { c >= 48 && c <= 57 } || { c >= 97 && c <= 102 } || { c >= 65 && c <= 70 }
}
