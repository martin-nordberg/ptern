import gleam/option.{type Option}

/// AST node types produced by the Ptern parser.
///
/// The tree mirrors the grammar's precedence hierarchy from top to bottom:
/// Ptern → definitions/annotations → alternation → sequence → capture →
/// repetition → exclusion → range-item → atom.

/// The top-level parsed document.
pub type ParsedPtern {
  ParsedPtern(
    /// A block of whole-line `#` comments at the very top of the source,
    /// separated from the first annotation/definition/body by a blank line.
    /// Empty list when no ptern-level comment is present.
    ptern_comments: List(String),
    annotations: List(Annotation),
    definitions: List(Definition),
    /// A block of whole-line `#` comments immediately above the body
    /// expression (no blank line between them and the body).
    body_comments: List(String),
    body: Expression,
  )
}

/// `!name = true` or `!name = false`.
pub type Annotation {
  Annotation(
    /// Doc-comment lines immediately above this annotation (no blank line
    /// between the last comment and the `!`).
    comments: List(String),
    name: String,
    value: Bool,
  )
}

/// `name = <expression> ;`
pub type Definition {
  Definition(
    /// Doc-comment lines immediately above this definition (no blank line
    /// between the last comment and the name).
    comments: List(String),
    name: String,
    body: Expression,
  )
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

/// `min` or `min..max`, with an optional `fewest` modifier for lazy matching.
pub type RepCount {
  RepCount(min: Int, max: RepUpper, lazy: Bool)
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
  /// A comment block was not immediately followed by an annotation,
  /// definition, or body expression (a blank line appeared between the
  /// comment and the item it was meant to document).
  OrphanedComment
  /// One or more comment lines appear after the body expression.
  TrailingComment
}
