import gleam/option.{type Option, None, Some}
import lexer/token.{type Token, Comment, Whitespace}

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

/// Return the next non-trivia token (skipping `Whitespace` and `Comment`)
/// without advancing the stream.
pub fn peek(stream: Stream) -> Option(Token) {
  peek_after_trivia(stream.tokens)
}

fn peek_after_trivia(tokens: List(Token)) -> Option(Token) {
  case tokens {
    [] -> None
    [Whitespace, ..rest] -> peek_after_trivia(rest)
    [Comment(_), ..rest] -> peek_after_trivia(rest)
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

/// Drop all leading `Whitespace` and `Comment` tokens.
pub fn skip_trivia(stream: Stream) -> Stream {
  case stream.tokens {
    [Whitespace, ..rest] -> skip_trivia(Stream(rest))
    [Comment(_), ..rest] -> skip_trivia(Stream(rest))
    _ -> stream
  }
}

/// Return `True` if the next raw token (before skipping trivia) is
/// `Whitespace`. Used by the sequence parser to detect the sequence operator.
pub fn next_is_whitespace(stream: Stream) -> Bool {
  case stream.tokens {
    [Whitespace, ..] -> True
    _ -> False
  }
}

/// Consume and return `True` if the next non-trivia token matches `expected`,
/// advancing past it (and any leading trivia). Returns `False` without
/// advancing if the token does not match or the stream is empty.
pub fn eat(stream: Stream, expected: Token) -> #(Bool, Stream) {
  let s = skip_trivia(stream)
  case s.tokens {
    [tok, ..rest] if tok == expected -> #(True, Stream(rest))
    _ -> #(False, stream)
  }
}

/// Consume one raw `Whitespace` token if present. Does NOT skip comments or
/// multiple whitespace tokens — only the immediate next token.
pub fn eat_whitespace(stream: Stream) -> Stream {
  case stream.tokens {
    [Whitespace, ..rest] -> Stream(rest)
    _ -> stream
  }
}

/// Consume all leading whitespace tokens (a run).
pub fn eat_all_whitespace(stream: Stream) -> Stream {
  case stream.tokens {
    [Whitespace, ..rest] -> eat_all_whitespace(Stream(rest))
    _ -> stream
  }
}

/// Produce a human-readable description of a token for error messages.
pub fn token_display(token: Token) -> String {
  case token {
    token.SingleQuotedLiteral(c) -> "'" <> c <> "'"
    token.DoubleQuotedLiteral(c) -> "\"" <> c <> "\""
    token.CharacterClass(n) -> "%" <> n
    token.Integer(n) -> {
      // Convert int to string manually since we can't import gleam/int here
      // (it's a small helper; the parser imports gleam/int itself).
      int_to_string(n)
    }
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
    token.PositionAssertion(name) -> "@" <> name
    token.Bang -> "!"

    token.QuestionMark -> "?"
    token.Identifier(n) -> n
    token.Whitespace -> "<whitespace>"
    token.Comment(_) -> "<comment>"
  }
}

/// Whether the stream has no more tokens (after skipping trivia).
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
  // Walk through the stdlib list of digit chars to build the decimal string.
  // This avoids importing gleam/int in a helper module.
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

