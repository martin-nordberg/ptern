import gleam/option.{type Option, None, Some}
import lexer/token.{type Token, Whitespace}

/// A cursor over a flat list of tokens.
///
/// The stream is immutable: every operation returns a new stream value rather
/// than mutating state. This makes backtracking straightforward and keeps the
/// parser functions pure.
pub opaque type Stream {
  Stream(tokens: List(Token))
}

/// Create a stream from a token list (as returned by the lexer).
pub fn new(tokens: List(Token)) -> Stream {
  Stream(tokens)
}

/// Return the remaining raw tokens (including whitespace and comments).
pub fn remaining(stream: Stream) -> List(Token) {
  stream.tokens
}

/// Return the next raw token without advancing, or `None` if the stream is
/// empty.
pub fn peek_raw(stream: Stream) -> Option(Token) {
  case stream.tokens {
    [] -> None
    [tok, ..] -> Some(tok)
  }
}

/// Return the next non-whitespace token (skipping `Whitespace` tokens of
/// either kind) without advancing the stream.
/// Comments are NOT skipped — they are structural nodes, not trivia.
pub fn peek(stream: Stream) -> Option(Token) {
  peek_after_whitespace(stream.tokens)
}

fn peek_after_whitespace(tokens: List(Token)) -> Option(Token) {
  case tokens {
    [] -> None
    [Whitespace(_), ..rest] -> peek_after_whitespace(rest)
    [tok, ..] -> Some(tok)
  }
}

/// Consume and return the next raw token, or `None` if the stream is empty.
pub fn advance(stream: Stream) -> #(Option(Token), Stream) {
  case stream.tokens {
    [] -> #(None, stream)
    [tok, ..rest] -> #(Some(tok), Stream(rest))
  }
}

/// Drop all leading `Whitespace` tokens (both blank-line and non-blank).
/// Comments are NOT dropped — use this inside constructs where no comment
/// should appear.
pub fn skip_whitespace(stream: Stream) -> Stream {
  case stream.tokens {
    [Whitespace(_), ..rest] -> skip_whitespace(Stream(rest))
    _ -> stream
  }
}

/// Drop a leading `Whitespace(False)` token if present.
/// Stops at `Whitespace(True)` (blank-line whitespace).
/// Used when collecting comment blocks: blank lines end a block.
pub fn skip_non_blank_whitespace(stream: Stream) -> Stream {
  case stream.tokens {
    [Whitespace(False), ..rest] -> Stream(rest)
    _ -> stream
  }
}

/// Return `True` if the next raw token (before skipping whitespace) is
/// `Whitespace`. Used by the sequence parser to detect the sequence operator.
pub fn next_is_whitespace(stream: Stream) -> Bool {
  case stream.tokens {
    [Whitespace(_), ..] -> True
    _ -> False
  }
}

/// Consume and return `True` if the next non-whitespace token matches
/// `expected`, advancing past it (and any leading whitespace). Returns
/// `False` without advancing if the token does not match or the stream is
/// empty.
pub fn eat(stream: Stream, expected: Token) -> #(Bool, Stream) {
  let s = skip_whitespace(stream)
  case s.tokens {
    [tok, ..rest] if tok == expected -> #(True, Stream(rest))
    _ -> #(False, stream)
  }
}

/// Consume one raw `Whitespace` token if present. Does NOT skip multiple
/// whitespace tokens — only the immediate next token.
pub fn eat_whitespace(stream: Stream) -> Stream {
  case stream.tokens {
    [Whitespace(_), ..rest] -> Stream(rest)
    _ -> stream
  }
}

/// Consume all leading whitespace tokens (a run).
pub fn eat_all_whitespace(stream: Stream) -> Stream {
  case stream.tokens {
    [Whitespace(_), ..rest] -> eat_all_whitespace(Stream(rest))
    _ -> stream
  }
}

/// Produce a human-readable description of a token for error messages.
pub fn token_display(token: Token) -> String {
  case token {
    token.SingleQuotedLiteral(c) -> "'" <> c <> "'"
    token.DoubleQuotedLiteral(c) -> "\"" <> c <> "\""
    token.CharacterClass(n) -> "%" <> n
    token.Integer(n) -> int_to_string(n)
    token.RangeOperator -> ".."
    token.Asterisk -> "*"
    token.AlternativeOperator -> "|"
    token.Equals -> "="
    token.LeftBrace -> "{"
    token.RightBrace -> "}"
    token.LeftParen -> "("
    token.RightParen -> ")"
    token.Semicolon -> ";"
    token.As -> "as"
    token.Excluding -> "excluding"
    token.TrueKeyword -> "true"
    token.FalseKeyword -> "false"
    token.Fewest -> "fewest"
    token.PositionAssertion(name) -> "@" <> name
    token.Bang -> "!"
    token.QuestionMark -> "?"
    token.Identifier(n) -> n
    token.Whitespace(_) -> "<whitespace>"
    token.Comment(_) -> "<comment>"
  }
}

/// Whether the stream has no more tokens (after skipping whitespace).
pub fn is_empty(stream: Stream) -> Bool {
  case peek(stream) {
    None -> True
    Some(_) -> False
  }
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

fn int_to_string(n: Int) -> String {
  case n < 0 {
    True -> "-" <> non_negative_to_string(0 - n)
    False -> non_negative_to_string(n)
  }
}

fn non_negative_to_string(n: Int) -> String {
  let digit = case n % 10 {
    0 -> "0"
    1 -> "1"
    2 -> "2"
    3 -> "3"
    4 -> "4"
    5 -> "5"
    6 -> "6"
    7 -> "7"
    8 -> "8"
    _ -> "9"
  }
  case n < 10 {
    True -> digit
    False -> non_negative_to_string(n / 10) <> digit
  }
}
