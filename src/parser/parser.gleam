import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import lexer/token
import parser/ast.{
  type Annotation, type Atom, type Capture, type Definition, type Exclusion,
  type Expression, type ParseError, type Ptern, type RangeItem, type RepCount,
  type RepUpper, type Repetition, type Sequence, Alternation, Annotation,
  Capture, CharClass, CharRange, Definition, Exact, Exclusion, Group,
  Interpolation, Literal, None as RepNone, Ptern, RepCount, Repetition,
  Sequence, SingleAtom, Unbounded, UnexpectedEndOfInput, UnexpectedToken,
}
import parser/stream.{type Stream}

// ---------------------------------------------------------------------------
// Public entry point
// ---------------------------------------------------------------------------

/// Parse a list of tokens (as returned by the lexer) into a `Ptern` AST.
pub fn parse(tokens: List(token.Token)) -> Result(Ptern, ParseError) {
  let s = stream.new(tokens)
  use #(ptern, s2) <- result.try(parse_ptern(s))
  // There must be no meaningful tokens remaining after the body expression.
  case stream.is_empty(s2) {
    True -> Ok(ptern)
    False -> {
      let tok = stream.peek(s2)
      Error(UnexpectedToken(
        "end of input",
        option.unwrap(option.map(tok, stream.token_display), "<unknown>"),
      ))
    }
  }
}

// ---------------------------------------------------------------------------
// Top-level: annotations, definitions, body
// ---------------------------------------------------------------------------

fn parse_ptern(s: Stream) -> Result(#(Ptern, Stream), ParseError) {
  use #(annotations, s) <- result.try(parse_annotations(s, []))
  use #(definitions, s) <- result.try(parse_definitions(s, []))
  use #(body, s) <- result.try(parse_expression(s))
  Ok(#(Ptern(annotations, definitions, body), s))
}

// Greedily consume annotations: `@ identifier = true|false`.
fn parse_annotations(
  s: Stream,
  acc: List(Annotation),
) -> Result(#(List(Annotation), Stream), ParseError) {
  let s = stream.skip_trivia(s)
  case stream.peek(s) {
    Some(token.At) -> {
      use #(ann, s2) <- result.try(parse_annotation(s))
      parse_annotations(s2, [ann, ..acc])
    }
    _ -> Ok(#(list.reverse(acc), s))
  }
}

fn parse_annotation(s: Stream) -> Result(#(Annotation, Stream), ParseError) {
  // Consume `@`
  let #(_, s) = stream.advance(s)
  // Skip any whitespace between `@` and the name (not expected but tolerated)
  let s = stream.skip_trivia(s)
  use #(name, s) <- result.try(expect_identifier(s))
  let s = stream.skip_trivia(s)
  use #(ok, s) <- result.try(expect_token(s, token.Equals))
  let _ = ok
  let s = stream.skip_trivia(s)
  case stream.peek(s) {
    Some(token.TrueKeyword) -> {
      let #(_, s) = stream.advance(s)
      Ok(#(Annotation(name, True), s))
    }
    Some(token.FalseKeyword) -> {
      let #(_, s) = stream.advance(s)
      Ok(#(Annotation(name, False), s))
    }
    Some(tok) ->
      Error(UnexpectedToken("true or false", stream.token_display(tok)))
    None -> Error(UnexpectedEndOfInput)
  }
}

// Greedily consume definitions: `identifier = expression ;`.
// We distinguish definitions from body by lookahead: if the token after the
// identifier is `=`, it's a definition.
fn parse_definitions(
  s: Stream,
  acc: List(Definition),
) -> Result(#(List(Definition), Stream), ParseError) {
  let s = stream.skip_trivia(s)
  case looks_like_definition(s) {
    False -> Ok(#(list.reverse(acc), s))
    True -> {
      use #(def, s2) <- result.try(parse_definition(s))
      parse_definitions(s2, [def, ..acc])
    }
  }
}

// Lookahead: return `True` when the stream starts with `identifier = …`.
fn looks_like_definition(s: Stream) -> Bool {
  case stream.remaining(s) {
    // Leading whitespace/comments are already stripped before this call.
    [token.Identifier(_), ..rest] ->
      case drop_trivia_tokens(rest) {
        [token.Equals, ..] -> True
        _ -> False
      }
    _ -> False
  }
}

fn drop_trivia_tokens(tokens: List(token.Token)) -> List(token.Token) {
  case tokens {
    [token.Whitespace, ..rest] -> drop_trivia_tokens(rest)
    [token.Comment(_), ..rest] -> drop_trivia_tokens(rest)
    other -> other
  }
}

fn parse_definition(s: Stream) -> Result(#(Definition, Stream), ParseError) {
  use #(name, s) <- result.try(expect_identifier(s))
  let s = stream.skip_trivia(s)
  use #(_, s) <- result.try(expect_token(s, token.Equals))
  let s = stream.skip_trivia(s)
  use #(body, s) <- result.try(parse_expression(s))
  let s = stream.skip_trivia(s)
  use #(_, s) <- result.try(expect_token(s, token.Semicolon))
  Ok(#(Definition(name, body), s))
}

// ---------------------------------------------------------------------------
// Expression: alternation (lowest precedence)
// ---------------------------------------------------------------------------

fn parse_expression(s: Stream) -> Result(#(Expression, Stream), ParseError) {
  parse_alternation(s)
}

fn parse_alternation(s: Stream) -> Result(#(Expression, Stream), ParseError) {
  use #(first, s) <- result.try(parse_sequence(s))
  collect_alternatives(s, [first])
}

fn collect_alternatives(
  s: Stream,
  acc: List(Sequence),
) -> Result(#(Expression, Stream), ParseError) {
  // Skip trivia, then check for `|`.
  let s2 = stream.skip_trivia(s)
  case stream.peek_raw(s2) {
    Some(token.AlternativeOperator) -> {
      let #(_, s2) = stream.advance(s2)
      let s2 = stream.skip_trivia(s2)
      use #(seq, s3) <- result.try(parse_sequence(s2))
      collect_alternatives(s3, [seq, ..acc])
    }
    _ -> Ok(#(Alternation(list.reverse(acc)), s))
  }
}

// ---------------------------------------------------------------------------
// Sequence: captures separated by whitespace
// ---------------------------------------------------------------------------

// A sequence is at least one capture. Additional captures are separated by a
// `Whitespace` token, but ONLY when the token after the whitespace still looks
// like the start of a capture. We must not consume whitespace that precedes a
// `|`, `)`, `as`, `excluding`, `*`, `=`, `;`, or end-of-input.
fn parse_sequence(s: Stream) -> Result(#(Sequence, Stream), ParseError) {
  use #(first, s) <- result.try(parse_capture(s))
  collect_sequence(s, [first])
}

fn collect_sequence(
  s: Stream,
  acc: List(Capture),
) -> Result(#(Sequence, Stream), ParseError) {
  // Only continue if there's a whitespace token immediately next AND the
  // token after the whitespace starts a new capture (atom).
  case stream.next_is_whitespace(s) && next_starts_capture(s) {
    False -> Ok(#(Sequence(list.reverse(acc)), s))
    True -> {
      // Consume the whitespace separator (comments interspersed are allowed).
      let s = stream.eat_all_whitespace(s)
      case starts_capture(stream.peek(s)) {
        False -> Ok(#(Sequence(list.reverse(acc)), s))
        True -> {
          use #(cap, s2) <- result.try(parse_capture(s))
          collect_sequence(s2, [cap, ..acc])
        }
      }
    }
  }
}

// Look past whitespace to decide if the next non-trivia token could start a
// capture (i.e. could be the first token of an atom).
fn next_starts_capture(s: Stream) -> Bool {
  // Temporarily eat all whitespace and comments to see what's next.
  let s2 = stream.skip_trivia(s)
  starts_capture(stream.peek_raw(s2))
}

fn starts_capture(tok: Option(token.Token)) -> Bool {
  case tok {
    Some(token.SingleQuotedLiteral(_)) -> True
    Some(token.DoubleQuotedLiteral(_)) -> True
    Some(token.CharacterClass(_)) -> True
    Some(token.LeftBrace) -> True
    Some(token.LeftParen) -> True
    _ -> False
  }
}

// ---------------------------------------------------------------------------
// Capture: `repetition (as identifier)?`
// ---------------------------------------------------------------------------

fn parse_capture(s: Stream) -> Result(#(Capture, Stream), ParseError) {
  use #(rep, s) <- result.try(parse_repetition(s))
  // Check for `as` keyword (may be preceded by whitespace).
  let s2 = stream.skip_trivia(s)
  case stream.peek_raw(s2) {
    Some(token.As) -> {
      let #(_, s2) = stream.advance(s2)
      let s2 = stream.skip_trivia(s2)
      use #(name, s3) <- result.try(expect_identifier(s2))
      Ok(#(Capture(rep, Some(name)), s3))
    }
    _ -> Ok(#(Capture(rep, None), s))
  }
}

// ---------------------------------------------------------------------------
// Repetition: `exclusion (* rep-count)?`
// ---------------------------------------------------------------------------

fn parse_repetition(s: Stream) -> Result(#(Repetition, Stream), ParseError) {
  use #(excl, s) <- result.try(parse_exclusion(s))
  let s2 = stream.skip_trivia(s)
  case stream.peek_raw(s2) {
    Some(token.Asterisk) -> {
      let #(_, s2) = stream.advance(s2)
      let s2 = stream.skip_trivia(s2)
      use #(count, s3) <- result.try(parse_rep_count(s2))
      Ok(#(Repetition(excl, Some(count)), s3))
    }
    _ -> Ok(#(Repetition(excl, None), s))
  }
}

fn parse_rep_count(s: Stream) -> Result(#(RepCount, Stream), ParseError) {
  case stream.peek(s) {
    Some(token.Integer(min)) -> {
      let #(_, s) = stream.advance(s)
      // Check for `..` range separator immediately after the integer (no
      // trivia allowed between integer and `..` to avoid ambiguity).
      case stream.peek_raw(s) {
        Some(token.RangeOperator) -> {
          let #(_, s) = stream.advance(s)
          use #(upper, s) <- result.try(parse_rep_upper(s))
          Ok(#(RepCount(min, upper), s))
        }
        _ -> Ok(#(RepCount(min, RepNone), s))
      }
    }
    Some(tok) ->
      Error(UnexpectedToken("repetition count (integer)", stream.token_display(tok)))
    None -> Error(UnexpectedEndOfInput)
  }
}

fn parse_rep_upper(s: Stream) -> Result(#(RepUpper, Stream), ParseError) {
  case stream.peek(s) {
    Some(token.QuestionMark) -> {
      let #(_, s) = stream.advance(s)
      Ok(#(Unbounded, s))
    }
    Some(token.Integer(n)) -> {
      let #(_, s) = stream.advance(s)
      Ok(#(Exact(n), s))
    }
    Some(tok) ->
      Error(UnexpectedToken(
        "upper bound (integer or ?)",
        stream.token_display(tok),
      ))
    None -> Error(UnexpectedEndOfInput)
  }
}

// ---------------------------------------------------------------------------
// Exclusion: `range-item (excluding range-item)?`
// ---------------------------------------------------------------------------

fn parse_exclusion(s: Stream) -> Result(#(Exclusion, Stream), ParseError) {
  use #(base, s) <- result.try(parse_range_item(s))
  let s2 = stream.skip_trivia(s)
  case stream.peek_raw(s2) {
    Some(token.Excluding) -> {
      let #(_, s2) = stream.advance(s2)
      let s2 = stream.skip_trivia(s2)
      use #(excl, s3) <- result.try(parse_range_item(s2))
      Ok(#(Exclusion(base, Some(excl)), s3))
    }
    _ -> Ok(#(Exclusion(base, None), s))
  }
}

// ---------------------------------------------------------------------------
// Range item: `atom (.. atom)?`
// ---------------------------------------------------------------------------

fn parse_range_item(s: Stream) -> Result(#(RangeItem, Stream), ParseError) {
  use #(from, s) <- result.try(parse_atom(s))
  // `..` must appear immediately after the atom (no trivia), because trivia
  // can appear between captures in a sequence and we must not confuse them.
  case stream.peek_raw(s) {
    Some(token.RangeOperator) -> {
      let #(_, s) = stream.advance(s)
      use #(to, s) <- result.try(parse_atom(s))
      Ok(#(CharRange(from, to), s))
    }
    _ -> Ok(#(SingleAtom(from), s))
  }
}

// ---------------------------------------------------------------------------
// Atom: literal | char-class | interpolation | group
// ---------------------------------------------------------------------------

fn parse_atom(s: Stream) -> Result(#(Atom, Stream), ParseError) {
  case stream.peek(s) {
    Some(token.SingleQuotedLiteral(content)) -> {
      let #(_, s) = stream.advance(s)
      Ok(#(Literal(content), s))
    }
    Some(token.DoubleQuotedLiteral(content)) -> {
      let #(_, s) = stream.advance(s)
      Ok(#(Literal(content), s))
    }
    Some(token.CharacterClass(name)) -> {
      let #(_, s) = stream.advance(s)
      Ok(#(CharClass(name), s))
    }
    Some(token.LeftBrace) -> parse_interpolation(s)
    Some(token.LeftParen) -> parse_group(s)
    Some(tok) ->
      Error(UnexpectedToken(
        "literal, character class, { or (",
        stream.token_display(tok),
      ))
    None -> Error(UnexpectedEndOfInput)
  }
}

fn parse_interpolation(s: Stream) -> Result(#(Atom, Stream), ParseError) {
  // Consume `{`
  let #(_, s) = stream.advance(s)
  let s = stream.skip_trivia(s)
  use #(name, s) <- result.try(expect_identifier(s))
  let s = stream.skip_trivia(s)
  use #(_, s) <- result.try(expect_token(s, token.RightBrace))
  Ok(#(Interpolation(name), s))
}

fn parse_group(s: Stream) -> Result(#(Atom, Stream), ParseError) {
  // Consume `(`
  let #(_, s) = stream.advance(s)
  let s = stream.skip_trivia(s)
  use #(expr, s) <- result.try(parse_expression(s))
  let s = stream.skip_trivia(s)
  use #(_, s) <- result.try(expect_token(s, token.RightParen))
  Ok(#(Group(expr), s))
}

// ---------------------------------------------------------------------------
// Utility helpers
// ---------------------------------------------------------------------------

fn expect_identifier(s: Stream) -> Result(#(String, Stream), ParseError) {
  case stream.peek(s) {
    Some(token.Identifier(name)) -> {
      let #(_, s) = stream.advance(s)
      Ok(#(name, s))
    }
    Some(tok) -> Error(UnexpectedToken("identifier", stream.token_display(tok)))
    None -> Error(UnexpectedEndOfInput)
  }
}

fn expect_token(
  s: Stream,
  expected: token.Token,
) -> Result(#(token.Token, Stream), ParseError) {
  case stream.peek(s) {
    Some(tok) if tok == expected -> {
      let #(_, s) = stream.advance(s)
      Ok(#(tok, s))
    }
    Some(tok) ->
      Error(UnexpectedToken(
        stream.token_display(expected),
        stream.token_display(tok),
      ))
    None ->
      Error(UnexpectedToken(stream.token_display(expected), "end of input"))
  }
}
