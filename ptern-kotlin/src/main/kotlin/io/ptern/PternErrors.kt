package io.ptern

// ---------------------------------------------------------------------------
// Compile errors
// ---------------------------------------------------------------------------

sealed class CompileError {
    data class LexError(val message: String) : CompileError()
    data class ParseError(val message: String) : CompileError()
    data class SemanticErrors(val errors: List<String>) : CompileError()
}

class PternCompileException(val error: CompileError, message: String) : RuntimeException(message)

// ---------------------------------------------------------------------------
// Replacement errors
// ---------------------------------------------------------------------------

sealed class ReplacementError {
    data class InvalidReplacementValue(val name: String) : ReplacementError()
    data class WrongReplacementType(val name: String) : ReplacementError()
    data class ArrayLengthMismatch(val name: String, val expected: Int, val actual: Int) : ReplacementError()
    data class DuplicateRepetitionCapture(val name: String) : ReplacementError()
}

class PternReplacementException(val error: ReplacementError, message: String) : RuntimeException(message)

// ---------------------------------------------------------------------------
// Substitution errors
// ---------------------------------------------------------------------------

sealed class SubstitutionError {
    object NotSubstitutable : SubstitutionError()
    data class MissingCapture(val name: String) : SubstitutionError()
    data class CaptureMismatch(val name: String) : SubstitutionError()
    data class ArrayLengthError(val name: String) : SubstitutionError()
    object NoMatchingBranch : SubstitutionError()
}

class PternSubstitutionException(val error: SubstitutionError, message: String) : RuntimeException(message)
