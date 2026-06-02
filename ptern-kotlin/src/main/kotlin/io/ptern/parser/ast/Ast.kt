package io.ptern.parser.ast

// ---------------------------------------------------------------------------
// Repetition bounds
// ---------------------------------------------------------------------------

sealed class RepUpper {
    data class Exact(val value: Int) : RepUpper()
    object Unbounded : RepUpper() { override fun toString() = "Unbounded" }
    object None : RepUpper() { override fun toString() = "None" }
}

data class RepCount(val min: Int, val max: RepUpper, val lazy: Boolean)

// ---------------------------------------------------------------------------
// AST node types
// ---------------------------------------------------------------------------

sealed class Atom {
    data class Literal(val content: String) : Atom()
    data class CharClass(val name: String) : Atom()
    data class Interpolation(val name: String) : Atom()
    data class Group(val inner: Expression) : Atom()
    data class PositionAssertion(val name: String) : Atom()
}

sealed class RangeItem {
    data class SingleAtom(val atom: Atom) : RangeItem()
    data class CharRange(val from: Atom, val to: Atom) : RangeItem()
}

data class Exclusion(val base: RangeItem, val excluded: RangeItem?)

data class Repetition(val inner: Exclusion, val count: RepCount?)

data class Capture(val inner: Repetition, val name: String?)

data class Sequence(val items: List<Capture>)

data class Expression(val alternatives: List<Sequence>)

// ---------------------------------------------------------------------------
// Top-level structure
// ---------------------------------------------------------------------------

data class PternAnnotation(val comments: List<String>, val name: String, val value: Boolean)

data class Definition(val comments: List<String>, val name: String, val body: Expression)

data class ParsedPtern(
    val pternComments: List<String>,
    val annotations: List<PternAnnotation>,
    val definitions: List<Definition>,
    val bodyComments: List<String>,
    val body: Expression,
)

// ---------------------------------------------------------------------------
// Parse errors
// ---------------------------------------------------------------------------

sealed class ParseError {
    object UnexpectedEndOfInput : ParseError() { override fun toString() = "UnexpectedEndOfInput" }
    data class UnexpectedToken(val expected: String, val got: String) : ParseError()
    object OrphanedComment : ParseError() { override fun toString() = "OrphanedComment" }
    object TrailingComment : ParseError() { override fun toString() = "TrailingComment" }
}

class ParseException(val parseError: ParseError) : RuntimeException(parseError.toString())
