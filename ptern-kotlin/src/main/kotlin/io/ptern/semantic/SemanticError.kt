package io.ptern.semantic

sealed class SemanticError {
    data class UndefinedReference(val name: String) : SemanticError()
    data class DuplicateDefinition(val name: String) : SemanticError()
    data class CircularDefinition(val names: List<String>) : SemanticError()
    data class DuplicateCapture(val name: String) : SemanticError()
    data class CaptureDefinitionConflict(val name: String) : SemanticError()
    data class InvalidRangeEndpoint(val content: String) : SemanticError()
    data class InvertedRange(val from: String, val to: String) : SemanticError()
    data class InvertedRepetitionBounds(val min: Int, val max: Int) : SemanticError()
    object InvalidExclusionOperand : SemanticError() { override fun toString() = "InvalidExclusionOperand" }
    data class UnknownAnnotation(val name: String) : SemanticError()
    data class DuplicateAnnotation(val name: String) : SemanticError()
    data class InvalidEscapeSequence(val seq: String) : SemanticError()
    data class UnknownPositionAssertion(val name: String) : SemanticError()
    data class PositionAssertionInRepetition(val name: String) : SemanticError()
    object SubstitutionsIgnoreMatchingWithoutSubstitutable : SemanticError() {
        override fun toString() = "SubstitutionsIgnoreMatchingWithoutSubstitutable"
    }
    object NotSubstitutableBody : SemanticError() { override fun toString() = "NotSubstitutableBody" }
    object BoundedRepetitionNeedsCapture : SemanticError() { override fun toString() = "BoundedRepetitionNeedsCapture" }
    object EmptyLiteral : SemanticError() { override fun toString() = "EmptyLiteral" }
    object EmptyCharacterSet : SemanticError() { override fun toString() = "EmptyCharacterSet" }
    data class AmbiguousRepetitionAdjacency(val branchA: String, val branchB: String) : SemanticError()
    object AmbiguousRepetitionBody : SemanticError() { override fun toString() = "AmbiguousRepetitionBody" }
    object AmbiguousAdjacentRepetition : SemanticError() { override fun toString() = "AmbiguousAdjacentRepetition" }
    object FewestOnExactRepetition : SemanticError() { override fun toString() = "FewestOnExactRepetition" }
    data class UnusedDefinition(val name: String) : SemanticError()
}
