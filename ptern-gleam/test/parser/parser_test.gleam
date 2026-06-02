import gleam/option.{None, Some}
import lexer/lexer
import parser/ast.{
  Alternation, Annotation, Capture, CharClass, CharRange, Definition, Exact,
  Exclusion, Group, Interpolation, Literal, None as RepNone, OrphanedComment,
  ParsedPtern, PositionAssertion, RepCount, Repetition, Sequence, SingleAtom,
  TrailingComment, Unbounded, UnexpectedEndOfInput, UnexpectedToken,
}
import parser/parser
import gleeunit/should

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn parse(input: String) {
  let assert Ok(tokens) = lexer.lex(input)
  parser.parse(tokens)
}

fn simple_atom(atom) {
  ParsedPtern(
    [],
    [],
    [],
    [],
    Alternation([
      Sequence([
        Capture(
          Repetition(Exclusion(SingleAtom(atom), None), None),
          None,
        ),
      ]),
    ]),
  )
}

// ---------------------------------------------------------------------------
// Atoms
// ---------------------------------------------------------------------------

pub fn parse_single_quoted_literal_test() {
  parse("'hello'")
  |> should.equal(Ok(simple_atom(Literal("hello"))))
}

pub fn parse_double_quoted_literal_test() {
  parse("\"world\"")
  |> should.equal(Ok(simple_atom(Literal("world"))))
}

pub fn parse_char_class_test() {
  parse("%Digit")
  |> should.equal(Ok(simple_atom(CharClass("Digit"))))
}

pub fn parse_interpolation_test() {
  parse("{my-pat}")
  |> should.equal(Ok(simple_atom(Interpolation("my-pat"))))
}

pub fn parse_group_test() {
  parse("('a')")
  |> should.equal(
    Ok(
      simple_atom(Group(
        Alternation([
          Sequence([
            Capture(
              Repetition(Exclusion(SingleAtom(Literal("a")), None), None),
              None,
            ),
          ]),
        ]),
      )),
    ),
  )
}

pub fn parse_position_assertion_test() {
  parse("@word-start")
  |> should.equal(Ok(simple_atom(PositionAssertion("word-start"))))
}

// ---------------------------------------------------------------------------
// Range items
// ---------------------------------------------------------------------------

pub fn parse_char_range_test() {
  parse("'a'..'z'")
  |> should.equal(
    Ok(
      ParsedPtern(
        [],
        [],
        [],
        [],
        Alternation([
          Sequence([
            Capture(
              Repetition(
                Exclusion(CharRange(Literal("a"), Literal("z")), None),
                None,
              ),
              None,
            ),
          ]),
        ]),
      ),
    ),
  )
}

// ---------------------------------------------------------------------------
// Exclusion
// ---------------------------------------------------------------------------

pub fn parse_exclusion_test() {
  parse("%Digit excluding '8'..'9'")
  |> should.equal(
    Ok(
      ParsedPtern(
        [],
        [],
        [],
        [],
        Alternation([
          Sequence([
            Capture(
              Repetition(
                Exclusion(
                  SingleAtom(CharClass("Digit")),
                  Some(CharRange(Literal("8"), Literal("9"))),
                ),
                None,
              ),
              None,
            ),
          ]),
        ]),
      ),
    ),
  )
}

// ---------------------------------------------------------------------------
// Repetition
// ---------------------------------------------------------------------------

pub fn parse_exact_repetition_test() {
  parse("%Digit * 4")
  |> should.equal(
    Ok(
      ParsedPtern(
        [],
        [],
        [],
        [],
        Alternation([
          Sequence([
            Capture(
              Repetition(
                Exclusion(SingleAtom(CharClass("Digit")), None),
                Some(RepCount(4, RepNone, False)),
              ),
              None,
            ),
          ]),
        ]),
      ),
    ),
  )
}

pub fn parse_bounded_repetition_test() {
  parse("'x' * 3..10")
  |> should.equal(
    Ok(
      ParsedPtern(
        [],
        [],
        [],
        [],
        Alternation([
          Sequence([
            Capture(
              Repetition(
                Exclusion(SingleAtom(Literal("x")), None),
                Some(RepCount(3, Exact(10), False)),
              ),
              None,
            ),
          ]),
        ]),
      ),
    ),
  )
}

pub fn parse_unbounded_repetition_test() {
  parse("%Digit * 1..?")
  |> should.equal(
    Ok(
      ParsedPtern(
        [],
        [],
        [],
        [],
        Alternation([
          Sequence([
            Capture(
              Repetition(
                Exclusion(SingleAtom(CharClass("Digit")), None),
                Some(RepCount(1, Unbounded, False)),
              ),
              None,
            ),
          ]),
        ]),
      ),
    ),
  )
}

// ---------------------------------------------------------------------------
// Capture
// ---------------------------------------------------------------------------

pub fn parse_named_capture_test() {
  parse("%Digit * 4 as year")
  |> should.equal(
    Ok(
      ParsedPtern(
        [],
        [],
        [],
        [],
        Alternation([
          Sequence([
            Capture(
              Repetition(
                Exclusion(SingleAtom(CharClass("Digit")), None),
                Some(RepCount(4, RepNone, False)),
              ),
              Some("year"),
            ),
          ]),
        ]),
      ),
    ),
  )
}

// ---------------------------------------------------------------------------
// Sequence
// ---------------------------------------------------------------------------

pub fn parse_sequence_test() {
  parse("'a' 'b'")
  |> should.equal(
    Ok(
      ParsedPtern(
        [],
        [],
        [],
        [],
        Alternation([
          Sequence([
            Capture(
              Repetition(Exclusion(SingleAtom(Literal("a")), None), None),
              None,
            ),
            Capture(
              Repetition(Exclusion(SingleAtom(Literal("b")), None), None),
              None,
            ),
          ]),
        ]),
      ),
    ),
  )
}

// ---------------------------------------------------------------------------
// Alternation
// ---------------------------------------------------------------------------

pub fn parse_alternation_test() {
  parse("'a' | 'b'")
  |> should.equal(
    Ok(
      ParsedPtern(
        [],
        [],
        [],
        [],
        Alternation([
          Sequence([
            Capture(
              Repetition(Exclusion(SingleAtom(Literal("a")), None), None),
              None,
            ),
          ]),
          Sequence([
            Capture(
              Repetition(Exclusion(SingleAtom(Literal("b")), None), None),
              None,
            ),
          ]),
        ]),
      ),
    ),
  )
}

pub fn parse_three_alternatives_test() {
  parse("'a' | 'b' | 'c'")
  |> should.equal(
    Ok(
      ParsedPtern(
        [],
        [],
        [],
        [],
        Alternation([
          Sequence([
            Capture(
              Repetition(Exclusion(SingleAtom(Literal("a")), None), None),
              None,
            ),
          ]),
          Sequence([
            Capture(
              Repetition(Exclusion(SingleAtom(Literal("b")), None), None),
              None,
            ),
          ]),
          Sequence([
            Capture(
              Repetition(Exclusion(SingleAtom(Literal("c")), None), None),
              None,
            ),
          ]),
        ]),
      ),
    ),
  )
}

// ---------------------------------------------------------------------------
// Definitions
// ---------------------------------------------------------------------------

pub fn parse_definition_test() {
  parse("d = %Digit; {d}")
  |> should.equal(
    Ok(
      ParsedPtern(
        [],
        [],
        [
          Definition(
            [],
            "d",
            Alternation([
              Sequence([
                Capture(
                  Repetition(
                    Exclusion(SingleAtom(CharClass("Digit")), None),
                    None,
                  ),
                  None,
                ),
              ]),
            ]),
          ),
        ],
        [],
        Alternation([
          Sequence([
            Capture(
              Repetition(Exclusion(SingleAtom(Interpolation("d")), None), None),
              None,
            ),
          ]),
        ]),
      ),
    ),
  )
}

// ---------------------------------------------------------------------------
// Annotations
// ---------------------------------------------------------------------------

pub fn parse_annotation_true_test() {
  parse("!case-insensitive = true\n'x'")
  |> should.equal(
    Ok(
      ParsedPtern(
        [],
        [Annotation([], "case-insensitive", True)],
        [],
        [],
        Alternation([
          Sequence([
            Capture(
              Repetition(Exclusion(SingleAtom(Literal("x")), None), None),
              None,
            ),
          ]),
        ]),
      ),
    ),
  )
}

pub fn parse_annotation_false_test() {
  parse("!case-insensitive = false\n%Digit")
  |> should.equal(
    Ok(
      ParsedPtern(
        [],
        [Annotation([], "case-insensitive", False)],
        [],
        [],
        Alternation([
          Sequence([
            Capture(
              Repetition(
                Exclusion(SingleAtom(CharClass("Digit")), None),
                None,
              ),
              None,
            ),
          ]),
        ]),
      ),
    ),
  )
}

// ---------------------------------------------------------------------------
// Doc comments
// ---------------------------------------------------------------------------

pub fn parse_body_doc_comment_test() {
  // A comment immediately above the body attaches as body_comments.
  parse("# a body comment\n'hello'")
  |> should.equal(
    Ok(
      ParsedPtern(
        [],
        [],
        [],
        [" a body comment"],
        Alternation([
          Sequence([
            Capture(
              Repetition(Exclusion(SingleAtom(Literal("hello")), None), None),
              None,
            ),
          ]),
        ]),
      ),
    ),
  )
}

pub fn parse_ptern_level_comment_test() {
  // A comment block followed by a blank line is a ptern-level comment.
  parse("# ptern doc\n\n'hello'")
  |> should.equal(
    Ok(
      ParsedPtern(
        [" ptern doc"],
        [],
        [],
        [],
        Alternation([
          Sequence([
            Capture(
              Repetition(Exclusion(SingleAtom(Literal("hello")), None), None),
              None,
            ),
          ]),
        ]),
      ),
    ),
  )
}

pub fn parse_annotation_doc_comment_test() {
  // A comment immediately above an annotation attaches to that annotation.
  parse("# docs\n!case-insensitive = true\n'x'")
  |> should.equal(
    Ok(
      ParsedPtern(
        [],
        [Annotation([" docs"], "case-insensitive", True)],
        [],
        [],
        Alternation([
          Sequence([
            Capture(
              Repetition(Exclusion(SingleAtom(Literal("x")), None), None),
              None,
            ),
          ]),
        ]),
      ),
    ),
  )
}

pub fn parse_definition_doc_comment_test() {
  // A comment immediately above a definition attaches to that definition.
  parse("# the digit def\nd = %Digit;\n{d}")
  |> should.equal(
    Ok(
      ParsedPtern(
        [],
        [],
        [
          Definition(
            [" the digit def"],
            "d",
            Alternation([
              Sequence([
                Capture(
                  Repetition(
                    Exclusion(SingleAtom(CharClass("Digit")), None),
                    None,
                  ),
                  None,
                ),
              ]),
            ]),
          ),
        ],
        [],
        Alternation([
          Sequence([
            Capture(
              Repetition(Exclusion(SingleAtom(Interpolation("d")), None), None),
              None,
            ),
          ]),
        ]),
      ),
    ),
  )
}

pub fn parse_ptern_comment_plus_item_comments_test() {
  // Ptern-level comment + per-item comments all parse correctly.
  parse("# ptern doc\n\n# ann doc\n!case-insensitive = true\n'x'")
  |> should.equal(
    Ok(
      ParsedPtern(
        [" ptern doc"],
        [Annotation([" ann doc"], "case-insensitive", True)],
        [],
        [],
        Alternation([
          Sequence([
            Capture(
              Repetition(Exclusion(SingleAtom(Literal("x")), None), None),
              None,
            ),
          ]),
        ]),
      ),
    ),
  )
}

pub fn parse_multiline_body_comment_test() {
  // Multiple consecutive comment lines above the body all attach.
  parse("# line one\n# line two\n'x'")
  |> should.equal(
    Ok(
      ParsedPtern(
        [],
        [],
        [],
        [" line one", " line two"],
        Alternation([
          Sequence([
            Capture(
              Repetition(Exclusion(SingleAtom(Literal("x")), None), None),
              None,
            ),
          ]),
        ]),
      ),
    ),
  )
}

pub fn parse_orphaned_comment_between_items_is_error_test() {
  // Comment after an annotation, followed by a blank line, then the body.
  parse("!case-insensitive = true\n# orphaned\n\n'x'")
  |> should.equal(Error(OrphanedComment))
}

pub fn parse_trailing_comment_is_error_test() {
  // Comment after the body expression → TrailingComment.
  parse("'x'\n# trailing")
  |> should.equal(Error(TrailingComment))
}

pub fn parse_orphaned_comment_before_body_is_error_test() {
  // Comment between definition and body with a blank line → OrphanedComment.
  parse("d = %Digit;\n# orphaned\n\n{d}")
  |> should.equal(Error(OrphanedComment))
}

// ---------------------------------------------------------------------------
// Complex / integration
// ---------------------------------------------------------------------------

pub fn parse_iso_date_test() {
  let input =
    "yyyy = %Digit * 4;\n"
    <> "mm = ('0' '1'..'9') | ('1' '0'..'2');\n"
    <> "dd = ('0' '1'..'9') | ('1'..'2' %Digit) | ('3' '0'..'1');\n"
    <> "{yyyy} as year '-' {mm} as month '-' {dd} as day"

  let result = parse(input)
  should.be_ok(result)
}

pub fn parse_group_in_alternation_test() {
  parse("('a' | 'b') 'c'")
  |> should.be_ok()
}

// ---------------------------------------------------------------------------
// Error cases
// ---------------------------------------------------------------------------

pub fn parse_empty_input_returns_error_test() {
  parse("")
  |> should.equal(Error(UnexpectedEndOfInput))
}

pub fn parse_unclosed_group_test() {
  parse("('a'")
  |> should.equal(
    Error(UnexpectedToken(")", "end of input")),
  )
}

pub fn parse_missing_semicolon_test() {
  // Body "d = %Digit {d}" is parsed as definition body = sequence(%Digit, {d});
  // the parser then expects ";" but reaches end of input.
  parse("d = %Digit {d}")
  |> should.equal(Error(UnexpectedToken(";", "end of input")))
}

pub fn parse_stray_token_test() {
  parse("'a' )")
  |> should.be_error()
}

// ---------------------------------------------------------------------------
// Fewest (lazy repetition)
// ---------------------------------------------------------------------------

pub fn parse_fewest_unbounded_test() {
  parse("%Any * 1..? fewest")
  |> should.equal(
    Ok(
      ParsedPtern(
        [],
        [],
        [],
        [],
        Alternation([
          Sequence([
            Capture(
              Repetition(
                Exclusion(SingleAtom(CharClass("Any")), None),
                Some(RepCount(1, Unbounded, True)),
              ),
              None,
            ),
          ]),
        ]),
      ),
    ),
  )
}

pub fn parse_fewest_optional_test() {
  parse("%Any * 0..1 fewest")
  |> should.equal(
    Ok(
      ParsedPtern(
        [],
        [],
        [],
        [],
        Alternation([
          Sequence([
            Capture(
              Repetition(
                Exclusion(SingleAtom(CharClass("Any")), None),
                Some(RepCount(0, Exact(1), True)),
              ),
              None,
            ),
          ]),
        ]),
      ),
    ),
  )
}

pub fn parse_fewest_bounded_test() {
  parse("%Any * 3..10 fewest")
  |> should.equal(
    Ok(
      ParsedPtern(
        [],
        [],
        [],
        [],
        Alternation([
          Sequence([
            Capture(
              Repetition(
                Exclusion(SingleAtom(CharClass("Any")), None),
                Some(RepCount(3, Exact(10), True)),
              ),
              None,
            ),
          ]),
        ]),
      ),
    ),
  )
}
