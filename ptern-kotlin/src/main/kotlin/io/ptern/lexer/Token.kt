package io.ptern.lexer

sealed class Token {
    data class SingleQuotedLiteral(val content: String) : Token()
    data class DoubleQuotedLiteral(val content: String) : Token()
    data class CharacterClass(val name: String) : Token()
    data class IntegerToken(val value: Int) : Token()
    data class PositionAssertion(val name: String) : Token()
    data class Identifier(val name: String) : Token()
    data class Whitespace(val hasBlankLine: Boolean) : Token()
    data class Comment(val content: String) : Token()
    object RangeOperator : Token() { override fun toString() = "RangeOperator" }
    object Asterisk : Token() { override fun toString() = "Asterisk" }
    object AlternativeOperator : Token() { override fun toString() = "AlternativeOperator" }
    object Equals : Token() { override fun toString() = "Equals" }
    object LeftBrace : Token() { override fun toString() = "LeftBrace" }
    object RightBrace : Token() { override fun toString() = "RightBrace" }
    object LeftParen : Token() { override fun toString() = "LeftParen" }
    object RightParen : Token() { override fun toString() = "RightParen" }
    object Semicolon : Token() { override fun toString() = "Semicolon" }
    object As : Token() { override fun toString() = "As" }
    object Excluding : Token() { override fun toString() = "Excluding" }
    object True : Token() { override fun toString() = "True" }
    object False : Token() { override fun toString() = "False" }
    object Fewest : Token() { override fun toString() = "Fewest" }
    object Bang : Token() { override fun toString() = "Bang" }
    object QuestionMark : Token() { override fun toString() = "QuestionMark" }
}

fun tokenDisplay(token: Token): String = when (token) {
    is Token.SingleQuotedLiteral -> "'${token.content}'"
    is Token.DoubleQuotedLiteral -> "\"${token.content}\""
    is Token.CharacterClass -> "%${token.name}"
    is Token.IntegerToken -> "${token.value}"
    is Token.PositionAssertion -> "@${token.name}"
    is Token.Identifier -> token.name
    is Token.Whitespace -> "<whitespace>"
    is Token.Comment -> "<comment>"
    Token.RangeOperator -> ".."
    Token.Asterisk -> "*"
    Token.AlternativeOperator -> "|"
    Token.Equals -> "="
    Token.LeftBrace -> "{"
    Token.RightBrace -> "}"
    Token.LeftParen -> "("
    Token.RightParen -> ")"
    Token.Semicolon -> ";"
    Token.As -> "as"
    Token.Excluding -> "excluding"
    Token.True -> "true"
    Token.False -> "false"
    Token.Fewest -> "fewest"
    Token.Bang -> "!"
    Token.QuestionMark -> "?"
}

fun tokensEqual(a: Token, b: Token): Boolean {
    if (a::class != b::class) return false
    return when (a) {
        is Token.SingleQuotedLiteral -> a.content == (b as Token.SingleQuotedLiteral).content
        is Token.DoubleQuotedLiteral -> a.content == (b as Token.DoubleQuotedLiteral).content
        is Token.CharacterClass -> a.name == (b as Token.CharacterClass).name
        is Token.IntegerToken -> a.value == (b as Token.IntegerToken).value
        is Token.PositionAssertion -> a.name == (b as Token.PositionAssertion).name
        is Token.Identifier -> a.name == (b as Token.Identifier).name
        is Token.Whitespace -> a.hasBlankLine == (b as Token.Whitespace).hasBlankLine
        is Token.Comment -> a.content == (b as Token.Comment).content
        else -> true  // singleton objects
    }
}

sealed class LexError {
    data class UnexpectedCharacter(val char: String) : LexError()
    object UnterminatedString : LexError() { override fun toString() = "UnterminatedString" }
    object InlineComment : LexError() { override fun toString() = "InlineComment" }
}

class LexException(val lexError: LexError) : RuntimeException(lexError.toString())
