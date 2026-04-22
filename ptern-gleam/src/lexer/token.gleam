/// The complete set of tokens produced by the Ptern lexer.
///
/// Whitespace is included as a token because a space between two sub-patterns
/// is the sequence operator — it is not insignificant trivia. The parser is
/// responsible for deciding when whitespace is meaningful and when it can be
/// ignored (e.g. around `=` or `;`).
///
/// String literal content is stored raw (escape sequences are not decoded);
/// a later compilation pass is responsible for interpreting escapes.
pub type Token {
  /// A single-quoted string literal, e.g. `'hello'`.
  /// `content` is the raw text between the quotes, with escape sequences
  /// left intact (e.g. `'it\'s'` yields content `it\'s`).
  SingleQuotedLiteral(content: String)

  /// A double-quoted string literal, e.g. `"hello"`.
  /// `content` is the raw text between the quotes, with escape sequences
  /// left intact.
  DoubleQuotedLiteral(content: String)

  /// A Unicode or POSIX character class, e.g. `%Digit` or `%Alpha`.
  /// `name` is the identifier after the `%` sigil (e.g. `"Digit"`).
  CharacterClass(name: String)

  /// A non-negative integer literal, e.g. `4` or `1000`.
  /// Used as a repetition count: `%Digit * 4` or `'x' * 1..10`.
  Integer(value: Int)

  /// The range operator `..`, used in character-class ranges (`'a'..'z'`)
  /// and bounded repetition (`* 3..10`).
  RangeOperator

  /// The repetition operator `*`, e.g. `%Digit * 4`.
  Asterisk

  /// The alternative operator `|`, e.g. `'a' | 'b'`.
  AlternativeOperator

  /// The assignment operator `=`, used in subpattern definitions:
  /// `yyyy = %Digit * 4;`
  Equals

  /// `{` — opens a subpattern interpolation, e.g. `{yyyy}`.
  LeftBrace

  /// `}` — closes a subpattern interpolation.
  RightBrace

  /// `(` — opens a precedence-override group, e.g. `('a' | 'b')`.
  LeftParen

  /// `)` — closes a precedence-override group.
  RightParen

  /// `;` — terminates a subpattern definition, e.g. `yyyy = %Digit * 4;`.
  Semicolon

  /// The keyword `as`, used for named captures: `%Digit * 4 as year`.
  As

  /// The keyword `excluding`, used for set difference:
  /// `%Digit excluding '8'..'9'`.
  Excluding

  /// The keyword `true`, used as an annotation value:
  /// `@case-insensitive = true`.
  TrueKeyword

  /// The keyword `false`, used as an annotation value:
  /// `@case-insensitive = false`.
  FalseKeyword

  /// `@` — introduces an annotation, e.g. `@case-insensitive = true`.
  At

  /// `?` — used as the upper bound of an unbounded repetition, e.g. `* 1..?`.
  QuestionMark

  /// A user-defined name, e.g. a subpattern name like `yyyy` or `my-pattern`.
  /// Identifiers start with a letter and may contain letters, digits, and
  /// hyphens (but not as the first character).
  Identifier(name: String)

  /// One or more consecutive whitespace characters (spaces, tabs, newlines).
  /// A single `Whitespace` token is emitted for each unbroken run.
  /// Whitespace between two sub-patterns acts as the sequence operator.
  Whitespace

  /// A single-line comment introduced by `#`, e.g. `# this is a comment`.
  /// `content` is the text after the `#` up to (but not including) the
  /// line terminator.
  Comment(content: String)
}

/// Errors that can occur during lexing.
pub type LexError {
  /// A character was encountered that does not begin any valid token.
  UnexpectedCharacter(String)

  /// A string literal was opened but never closed before end-of-input or a
  /// bare newline.
  UnterminatedString
}
