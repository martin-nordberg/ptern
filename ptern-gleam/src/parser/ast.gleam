import gleam/option.{type Option}

/// AST node types produced by the Ptern parser.
///
/// The tree mirrors the grammar's precedence hierarchy from top to bottom:
/// Ptern → definitions/annotations → alternation → sequence → capture →
/// repetition → exclusion → range-item → atom.

/// The top-level parsed document.
pub type ParsedPtern {
  ParsedPtern(
    annotations: List(Annotation),
    definitions: List(Definition),
    body: Expression,
  )
}

/// `!name = true` or `!name = false`.
pub type Annotation {
  Annotation(name: String, value: Bool)
}

/// `name = <expression> ;`
pub type Definition {
  Definition(name: String, body: Expression)
}

/// An expression is one or more sequences joined by `|`.
pub type Expression {
  Alternation(alternatives: List(Sequence))
}

/// A sequence is one or more captures written side-by-side with spaces.
pub type Sequence {
  Sequence(items: List(Capture))
}

/// A capture wraps a repetition and optionally binds a name: `<rep> as name`.
pub type Capture {
  Capture(inner: Repetition, name: Option(String))
}

/// A repetition applies an optional repeat count to an exclusion.
pub type Repetition {
  Repetition(inner: Exclusion, count: Option(RepCount))
}

/// `min` or `min..max`.
pub type RepCount {
  RepCount(min: Int, max: RepUpper)
}

pub type RepUpper {
  /// An exact upper bound: `* 3..10`.
  Exact(Int)
  /// Unbounded: `* 1..?`.
  Unbounded
  /// No range separator — single exact count: `* 4` means exactly 4.
  None
}

/// An exclusion applies an optional set-difference to a range item.
pub type Exclusion {
  Exclusion(base: RangeItem, excluded: Option(RangeItem))
}

/// A range item is either a single atom or a character range `atom..atom`.
pub type RangeItem {
  SingleAtom(atom: Atom)
  CharRange(from: Atom, to: Atom)
}

pub type Atom {
  /// A single- or double-quoted string literal (content is raw, not decoded).
  Literal(content: String)
  /// A character class such as `%Digit` or `%Alpha`.
  CharClass(name: String)
  /// A subpattern interpolation: `{name}`.
  Interpolation(name: String)
  /// A grouped sub-expression: `( expression )`.
  Group(inner: Expression)
  /// A zero-width position assertion: `@word-start`, `@word-end`,
  /// `@line-start`, `@line-end`.
  PositionAssertion(name: String)
}

/// Errors that can occur during parsing.
pub type ParseError {
  /// The token stream ended where more input was expected.
  UnexpectedEndOfInput
  /// A token was found that does not fit the current grammar rule.
  /// `expected` is a human-readable description; `got` is the token's string
  /// representation.
  UnexpectedToken(expected: String, got: String)
}
