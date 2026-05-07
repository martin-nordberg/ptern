import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import lexer/token.{Fewest}
import parser/ast.{
  type Annotation, type Atom, type Capture, type Definition, type Exclusion,
  type Expression, type ParseError, type ParsedPtern, type RangeItem,
  type RepCount, type RepUpper, type Repetition, type Sequence, Alternation,
  Annotation, Capture, CharClass, CharRange, Definition, Exact, Exclusion,
  Group, Interpolation, Literal, None as RepNone, OrphanedComment, ParsedPtern,
  PositionAssertion, RepCount, Repetition, Sequence, SingleAtom, TrailingComment,
  Unbounded, UnexpectedEndOfInput, UnexpectedToken,
}
import parser/stream.{type Stream}

// ---------------------------------------------------------------------------
// Public entry point
// ---------------------------------------------------------------------------

/// Parse a list of tokens (as returned by the lexer) into a `Ptern` AST.
pub fn parse(tokens: List(token.Token)) -> Result(ParsedPtern, ParseError) {
  let s = stream.new(tokens)
  use #(ptern, s2) <- result.try(parse_ptern(s))
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
// Top-level: ptern comments, annotations, definitions, body
// ---------------------------------------------------------------------------

fn parse_ptern(s: Stream) -> Result(#(ParsedPtern, Stream), ParseError) {
  // Skip all leading whitespace (including blank lines at the top of the file).
  let s = stream.skip_whitespace(s)

  // Collect the very first block of consecutive comment lines.
  let #(first_block, s) = collect_comment_block(s)

  // Determine whether first_block is the ptern-level doc comment (followed by
  // a blank line) or the item-level comment for the first annotation/definition/body.
  use #(ptern_comments, carried, s) <- result.try(
    resolve_leading_comments(first_block, s),
  )

  // Parse annotations, each preceded by its own comment block.
  use #(annotations, carried, s) <- result.try(parse_annotations(s, carried))

  // Parse definitions, each preceded by its own comment block.
  use #(definitions, carried, s) <- result.try(parse_definitions(s, carried))

  // Whatever comments remain are the body's doc comment.
  let body_comments = carried

  // Parse the body expression.
  use #(body, s) <- result.try(parse_expression(s))

  // No trailing comments are allowed after the body.
  let s = stream.skip_whitespace(s)
  case stream.peek_raw(s) {
    Some(token.Comment(_)) -> Error(TrailingComment)
    None ->
      Ok(#(
        ParsedPtern(ptern_comments, annotations, definitions, body_comments, body),
        s,
      ))
    Some(tok) ->
      Error(UnexpectedToken("end of input", stream.token_display(tok)))
  }
}

// After collecting `first_block` from the very top of the file, decide
// whether it is a ptern-level comment (blank line follows) or an item-level
// comment to carry forward.
fn resolve_leading_comments(
  first_block: List(String),
  s: Stream,
) -> Result(#(List(String), List(String), Stream), ParseError) {
  case stream.peek_raw(s) {
    Some(token.Whitespace(True)) -> {
      // Blank line after first_block → first_block is the ptern-level comment.
      let #(_, s) = stream.advance(s)
      let s = stream.skip_non_blank_whitespace(s)
      let #(item_block, s) = collect_comment_block(s)
      // A second comment block followed by another blank line is orphaned.
      case stream.peek_raw(s) {
        Some(token.Whitespace(True)) ->
          case list.is_empty(item_block) {
            True -> Ok(#(first_block, item_block, s))
            False -> Error(OrphanedComment)
          }
        _ -> Ok(#(first_block, item_block, s))
      }
    }
    _ -> Ok(#([], first_block, s))
  }
}

// ---------------------------------------------------------------------------
// Annotations
// ---------------------------------------------------------------------------

fn parse_annotations(
  s: Stream,
  carried: List(String),
) -> Result(#(List(Annotation), List(String), Stream), ParseError) {
  do_parse_annotations(s, carried, [])
}

fn do_parse_annotations(
  s: Stream,
  carried: List(String),
  acc: List(Annotation),
) -> Result(#(List(Annotation), List(String), Stream), ParseError) {
  // Skip all whitespace (blank lines between annotations are fine).
  let s = stream.skip_whitespace(s)
  case stream.peek_raw(s) {
    Some(token.Bang) -> {
      use #(ann, s) <- result.try(parse_annotation(s, carried))
      let #(next_block, s) = collect_item_comments(s)
      case stream.peek_raw(s) {
        Some(token.Whitespace(True)) ->
          case list.is_empty(next_block) {
            True -> do_parse_annotations(s, next_block, [ann, ..acc])
            False -> Error(OrphanedComment)
          }
        _ -> do_parse_annotations(s, next_block, [ann, ..acc])
      }
    }
    _ -> Ok(#(list.reverse(acc), carried, s))
  }
}

fn parse_annotation(
  s: Stream,
  comments: List(String),
) -> Result(#(Annotation, Stream), ParseError) {
  // Consume `!`
  let #(_, s) = stream.advance(s)
  let s = stream.skip_whitespace(s)
  use #(name, s) <- result.try(expect_identifier(s))
  let s = stream.skip_whitespace(s)
  use #(ok, s) <- result.try(expect_token(s, token.Equals))
  let _ = ok
  let s = stream.skip_whitespace(s)
  case stream.peek(s) {
    Some(token.TrueKeyword) -> {
      let #(_, s) = stream.advance(s)
      Ok(#(Annotation(comments, name, True), s))
    }
    Some(token.FalseKeyword) -> {
      let #(_, s) = stream.advance(s)
      Ok(#(Annotation(comments, name, False), s))
    }
    Some(tok) ->
      Error(UnexpectedToken("true or false", stream.token_display(tok)))
    None -> Error(UnexpectedEndOfInput)
  }
}

// ---------------------------------------------------------------------------
// Definitions
// ---------------------------------------------------------------------------

fn parse_definitions(
  s: Stream,
  carried: List(String),
) -> Result(#(List(Definition), List(String), Stream), ParseError) {
  do_parse_definitions(s, carried, [])
}

fn do_parse_definitions(
  s: Stream,
  carried: List(String),
  acc: List(Definition),
) -> Result(#(List(Definition), List(String), Stream), ParseError) {
  // Skip all whitespace (blank lines between definitions are fine).
  let s = stream.skip_whitespace(s)
  // Collect any additional comment lines that may precede this definition.
  let #(new_comments, s) = collect_comment_block(s)
  // A comment block followed by a blank line is orphaned.
  case stream.peek_raw(s) {
    Some(token.Whitespace(True)) ->
      case list.is_empty(new_comments) {
        True -> Ok(#(list.reverse(acc), carried, s))
        False -> Error(OrphanedComment)
      }
    _ -> {
      let all_carried = list.append(carried, new_comments)
      case looks_like_definition(s) {
        False -> Ok(#(list.reverse(acc), all_carried, s))
        True -> {
          use #(def, s) <- result.try(parse_definition(s, all_carried))
          let #(next_block, s) = collect_item_comments(s)
          case stream.peek_raw(s) {
            Some(token.Whitespace(True)) ->
              case list.is_empty(next_block) {
                True -> do_parse_definitions(s, next_block, [def, ..acc])
                False -> Error(OrphanedComment)
              }
            _ -> do_parse_definitions(s, next_block, [def, ..acc])
          }
        }
      }
    }
  }
}

// Lookahead: return `True` when the stream starts with `identifier = …`.
fn looks_like_definition(s: Stream) -> Bool {
  case stream.remaining(s) {
    [token.Identifier(_), ..rest] ->
      case drop_whitespace_tokens(rest) {
        [token.Equals, ..] -> True
        _ -> False
      }
    _ -> False
  }
}

fn drop_whitespace_tokens(tokens: List(token.Token)) -> List(token.Token) {
  case tokens {
    [token.Whitespace(_), ..rest] -> drop_whitespace_tokens(rest)
    other -> other
  }
}

fn parse_definition(
  s: Stream,
  comments: List(String),
) -> Result(#(Definition, Stream), ParseError) {
  use #(name, s) <- result.try(expect_identifier(s))
  let s = stream.skip_whitespace(s)
  use #(_, s) <- result.try(expect_token(s, token.Equals))
  let s = stream.skip_whitespace(s)
  use #(body, s) <- result.try(parse_expression(s))
  let s = stream.skip_whitespace(s)
  use #(_, s) <- result.try(expect_token(s, token.Semicolon))
  Ok(#(Definition(comments, name, body), s))
}

// ---------------------------------------------------------------------------
// Comment collection helpers
// ---------------------------------------------------------------------------

// Collect a block of consecutive Comment tokens, with only non-blank-line
// Whitespace tokens between them.  Stops when a Whitespace(True) (blank line),
// a non-comment/non-whitespace token, or end-of-input is reached.
// Returns the collected comment strings and the stream at the stopping token.
fn collect_comment_block(s: Stream) -> #(List(String), Stream) {
  do_collect_comment_block(s, [])
}

fn do_collect_comment_block(
  s: Stream,
  acc: List(String),
) -> #(List(String), Stream) {
  case stream.peek_raw(s) {
    Some(token.Comment(content)) -> {
      let #(_, s) = stream.advance(s)
      // Skip the non-blank newline that follows the comment line.
      let s = stream.skip_non_blank_whitespace(s)
      do_collect_comment_block(s, [content, ..acc])
    }
    _ -> #(list.reverse(acc), s)
  }
}

// Like collect_comment_block but first skips a non-blank whitespace token
// (the newline following the previous item).  Used after each
// annotation/definition to collect the next item's leading comments.
fn collect_item_comments(s: Stream) -> #(List(String), Stream) {
  let s = stream.skip_non_blank_whitespace(s)
  collect_comment_block(s)
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
  let s2 = stream.skip_whitespace(s)
  case stream.peek_raw(s2) {
    Some(token.AlternativeOperator) -> {
      let #(_, s2) = stream.advance(s2)
      let s2 = stream.skip_whitespace(s2)
      use #(seq, s3) <- result.try(parse_sequence(s2))
      collect_alternatives(s3, [seq, ..acc])
    }
    _ -> Ok(#(Alternation(list.reverse(acc)), s))
  }
}

// ---------------------------------------------------------------------------
// Sequence: captures separated by whitespace
// ---------------------------------------------------------------------------

fn parse_sequence(s: Stream) -> Result(#(Sequence, Stream), ParseError) {
  use #(first, s) <- result.try(parse_capture(s))
  collect_sequence(s, [first])
}

fn collect_sequence(
  s: Stream,
  acc: List(Capture),
) -> Result(#(Sequence, Stream), ParseError) {
  case stream.next_is_whitespace(s) && next_starts_capture(s) {
    False -> Ok(#(Sequence(list.reverse(acc)), s))
    True -> {
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

// Look past whitespace to decide if the next non-whitespace token could start
// a capture.  Comments stop the lookahead — they are not part of sequences.
fn next_starts_capture(s: Stream) -> Bool {
  let s2 = stream.skip_whitespace(s)
  starts_capture(stream.peek_raw(s2))
}

fn starts_capture(tok: Option(token.Token)) -> Bool {
  case tok {
    Some(token.SingleQuotedLiteral(_)) -> True
    Some(token.DoubleQuotedLiteral(_)) -> True
    Some(token.CharacterClass(_)) -> True
    Some(token.PositionAssertion(_)) -> True
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
  let s2 = stream.skip_whitespace(s)
  case stream.peek_raw(s2) {
    Some(token.As) -> {
      let #(_, s2) = stream.advance(s2)
      let s2 = stream.skip_whitespace(s2)
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
  let s2 = stream.skip_whitespace(s)
  case stream.peek_raw(s2) {
    Some(token.Asterisk) -> {
      let #(_, s2) = stream.advance(s2)
      let s2 = stream.skip_whitespace(s2)
      use #(count, s3) <- result.try(parse_rep_count(s2))
      let s4 = stream.skip_whitespace(s3)
      case stream.peek_raw(s4) {
        Some(Fewest) -> {
          let #(_, s4) = stream.advance(s4)
          Ok(#(Repetition(excl, Some(RepCount(count.min, count.max, True))), s4))
        }
        _ -> Ok(#(Repetition(excl, Some(count)), s3))
      }
    }
    _ -> Ok(#(Repetition(excl, None), s))
  }
}

fn parse_rep_count(s: Stream) -> Result(#(RepCount, Stream), ParseError) {
  case stream.peek(s) {
    Some(token.Integer(min)) -> {
      let #(_, s) = stream.advance(s)
      case stream.peek_raw(s) {
        Some(token.RangeOperator) -> {
          let #(_, s) = stream.advance(s)
          use #(upper, s) <- result.try(parse_rep_upper(s))
          Ok(#(RepCount(min, upper, False), s))
        }
        _ -> Ok(#(RepCount(min, RepNone, False), s))
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
  let s2 = stream.skip_whitespace(s)
  case stream.peek_raw(s2) {
    Some(token.Excluding) -> {
      let #(_, s2) = stream.advance(s2)
      let s2 = stream.skip_whitespace(s2)
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
    Some(token.PositionAssertion(name)) -> {
      let #(_, s) = stream.advance(s)
      Ok(#(PositionAssertion(name), s))
    }
    Some(token.LeftBrace) -> parse_interpolation(s)
    Some(token.LeftParen) -> parse_group(s)
    Some(tok) ->
      Error(UnexpectedToken(
        "literal, character class, position assertion, { or (",
        stream.token_display(tok),
      ))
    None -> Error(UnexpectedEndOfInput)
  }
}

fn parse_interpolation(s: Stream) -> Result(#(Atom, Stream), ParseError) {
  let #(_, s) = stream.advance(s)
  let s = stream.skip_whitespace(s)
  use #(name, s) <- result.try(expect_identifier(s))
  let s = stream.skip_whitespace(s)
  use #(_, s) <- result.try(expect_token(s, token.RightBrace))
  Ok(#(Interpolation(name), s))
}

fn parse_group(s: Stream) -> Result(#(Atom, Stream), ParseError) {
  let #(_, s) = stream.advance(s)
  let s = stream.skip_whitespace(s)
  use #(expr, s) <- result.try(parse_expression(s))
  let s = stream.skip_whitespace(s)
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
