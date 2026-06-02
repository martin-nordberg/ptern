package io.ptern.formatter

sealed class FormatError {
    object InvalidLineWidth : FormatError() { override fun toString() = "InvalidLineWidth" }
    data class FormatLexError(val message: String) : FormatError()
    data class FormatParseError(val message: String) : FormatError()
}

class PternFormatException(val formatError: FormatError, message: String) : RuntimeException(message)
