import gleam/option.{None, Some}
import lexer/lexer
import parser/ast.{
  Alternation, Annotation, Capture, CharClass, CharRange, Definition, Exact,
  Exclusion, Group, Interpolation, Literal, None as RepNone, ParsedPtern, RepCount,
  Repetition, Sequence, SingleAtom, Unbounded, UnexpectedEndOfInput,
  UnexpectedToken,
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
        Alternation([
          Sequence([
            Capture(
              Repetition(
                Exclusion(SingleAtom(CharClass("Digit")), None),
                Some(RepCount(4, RepNone)),
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
        Alternation([
          Sequence([
            Capture(
              Repetition(
                Exclusion(SingleAtom(Literal("x")), None),
                Some(RepCount(3, Exact(10))),
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
        Alternation([
          Sequence([
            Capture(
              Repetition(
                Exclusion(SingleAtom(CharClass("Digit")), None),
                Some(RepCount(1, Unbounded)),
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
        Alternation([
          Sequence([
            Capture(
              Repetition(
                Exclusion(SingleAtom(CharClass("Digit")), None),
                Some(RepCount(4, RepNone)),
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
        [
          Definition(
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
        [Annotation("case-insensitive", True)],
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
        [Annotation("case-insensitive", False)],
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
// Comments
// ---------------------------------------------------------------------------

pub fn parse_comment_is_ignored_test() {
  parse("# a comment\n'hello'")
  |> should.equal(Ok(simple_atom(Literal("hello"))))
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
  parse("d = %Digit {d}")
  |> should.be_error()
}

pub fn parse_stray_token_test() {
  parse("'a' )")
  |> should.be_error()
}
