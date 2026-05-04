/// Errors detected during semantic analysis of a parsed Ptern AST.
///
/// Both passes (constraint validation and name resolution) produce values of
/// this type so that all errors can be collected and reported together.
pub type SemanticError {
  /// `{name}` where `name` is neither a definition nor an in-scope capture.
  UndefinedReference(name: String)

  /// Two definitions share the same name.
  DuplicateDefinition(name: String)

  /// A definition references itself directly or through a cycle.
  /// `names` is the sorted set of definition names forming the cycle.
  CircularDefinition(names: List(String))

  /// The same capture name is used more than once in the body expression.
  DuplicateCapture(name: String)

  /// A capture name is the same as a definition name.
  CaptureDefinitionConflict(name: String)

  /// A `..` range endpoint is not a single-character literal.
  /// `content` is the raw literal content that failed the check.
  InvalidRangeEndpoint(content: String)

  /// A `..` range is inverted: the from-character is after the to-character.
  InvertedRange(from: String, to: String)

  /// A `* m..n` repetition has `m > n`.
  InvertedRepetitionBounds(min: Int, max: Int)

  /// An `excluding` expression has an operand that is not a character set.
  /// Valid operands: a char class, a single-char literal, a char range, or a
  /// flat union group `(A | B | …)` where every alternative is one of those
  /// three forms with no name, repetition count, nested excluding, or
  /// interpolation. Interpolations and all other forms are always invalid.
  InvalidExclusionOperand

  /// An annotation name is not in the set of recognised annotation names.
  UnknownAnnotation(name: String)

  /// The same annotation is set more than once.
  DuplicateAnnotation(name: String)

  /// A string literal contains an unrecognised escape sequence.
  /// `seq` is the raw two-character sequence, e.g. `"\\z"`.
  InvalidEscapeSequence(seq: String)

  /// A `@name` position assertion uses an unrecognised name.
  UnknownPositionAssertion(name: String)

  /// A position assertion (`@word-start` etc.) has a repetition count applied.
  PositionAssertionInRepetition(name: String)

  /// `!substitutions-ignore-matching = true` is set but `!substitutable = true`
  /// is absent or false — the annotation is meaningless without substitution.
  SubstitutionsIgnoreMatchingWithoutSubstitutable

  /// `!substitutable = true` is set but the final body expression (or a
  /// sub-expression outside any named capture) is not substitutable.
  NotSubstitutableBody

  /// A bounded repetition `E * n..m` inside a substitutable context contains
  /// no named capture, so the iteration count cannot be determined at runtime.
  BoundedRepetitionNeedsCapture

  /// A string literal `''` or `""` contains no characters.
  EmptyLiteral

  /// Both sides of `excluding` are structurally identical (e.g. `%Digit excluding %Digit`),
  /// so the resulting character class is always empty.
  EmptyCharacterSet

  /// Inside a variable-length repetition, two branches have overlapping last/first
  /// character sets, so the engine may re-split a previously consumed prefix.
  /// The check is conservative: some safe patterns are also rejected.
  /// Add `!allow-backtracking = true` to opt out.
  AmbiguousRepetitionAdjacency(branch_a: String, branch_b: String)

  /// A variable-length repetition body can overlap itself across iterations
  /// (last-char set ∩ first-char set ≠ ∅), enabling catastrophic backtracking.
  /// Add `!allow-backtracking = true` to opt out.
  AmbiguousRepetitionBody

  /// Two consecutive unbounded repetitions whose character sets overlap: the
  /// engine cannot determine where the first ends and the second begins.
  AmbiguousAdjacentRepetition

  /// `fewest` was applied to an exact-count repetition `* n`. The iteration
  /// count is fixed so there is no choice to minimise.
  FewestOnExactRepetition
}
