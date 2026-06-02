package io.ptern.lexer

object Lexer {
    fun lex(input: String): List<Token> = LexState(input).lex()
}

private class LexState(private val input: String) {
    private var pos: Int = 0
    private val tokens = mutableListOf<Token>()
    private var atLineStart: Boolean = true

    fun lex(): List<Token> {
        while (pos < input.length) {
            lexNext()
        }
        return tokens
    }

    private fun lexNext() {
        val c = input[pos++]
        when (c) {
            ' ', '\t' -> lexWhitespace(atLineStart, false)
            '\n', '\r' -> lexWhitespace(true, false)
            '#' -> {
                if (!atLineStart) throw LexException(LexError.InlineComment)
                lexComment()
            }
            '\'' -> lexQuoted('\'')
            '"' -> lexQuoted('"')
            '%' -> lexCharacterClass()
            '.' -> lexRangeOperator()
            '@' -> lexPositionAssertion()
            '!' -> emit(Token.Bang)
            '?' -> emit(Token.QuestionMark)
            '*' -> emit(Token.Asterisk)
            '|' -> emit(Token.AlternativeOperator)
            '=' -> emit(Token.Equals)
            '{' -> emit(Token.LeftBrace)
            '}' -> emit(Token.RightBrace)
            '(' -> emit(Token.LeftParen)
            ')' -> emit(Token.RightParen)
            ';' -> emit(Token.Semicolon)
            else -> when {
                c.isAsciiDigit() -> lexInteger(c)
                c.isAsciiAlpha() -> lexIdentifier(c)
                else -> throw LexException(LexError.UnexpectedCharacter(c.toString()))
            }
        }
    }

    private fun emit(token: Token) {
        tokens.add(token)
        atLineStart = false
    }

    // -------------------------------------------------------------------------
    // Whitespace
    // -------------------------------------------------------------------------

    private fun lexWhitespace(initialHadNewline: Boolean, initialHasBlankLine: Boolean) {
        var hadNewline = initialHadNewline
        var hasBlankLine = initialHasBlankLine
        while (pos < input.length) {
            when (input[pos]) {
                ' ', '\t' -> pos++
                '\n', '\r' -> { hasBlankLine = hasBlankLine || hadNewline; hadNewline = true; pos++ }
                else -> break
            }
        }
        tokens.add(Token.Whitespace(hasBlankLine))
        atLineStart = hadNewline
    }

    // -------------------------------------------------------------------------
    // Comments
    // -------------------------------------------------------------------------

    private fun lexComment() {
        val content = StringBuilder()
        while (pos < input.length) {
            val c = input[pos]
            if (c == '\n' || c == '\r') break  // leave newline for whitespace handling
            content.append(c)
            pos++
        }
        tokens.add(Token.Comment(content.toString()))
        atLineStart = false
    }

    // -------------------------------------------------------------------------
    // String literals
    // -------------------------------------------------------------------------

    private fun lexQuoted(quote: Char) {
        val content = StringBuilder()
        while (true) {
            if (pos >= input.length) throw LexException(LexError.UnterminatedString)
            val c = input[pos++]
            when {
                c == '\n' || c == '\r' -> throw LexException(LexError.UnterminatedString)
                c == quote -> {
                    val token = if (quote == '\'')
                        Token.SingleQuotedLiteral(content.toString())
                    else
                        Token.DoubleQuotedLiteral(content.toString())
                    emit(token)
                    return
                }
                c == '\\' -> lexEscape(content)
                else -> content.append(c)
            }
        }
    }

    private fun lexEscape(sb: StringBuilder) {
        if (pos >= input.length) throw LexException(LexError.UnterminatedString)
        val c = input[pos++]
        if (c == 'u') {
            if (pos + 4 > input.length) throw LexException(LexError.UnterminatedString)
            val hex = input.substring(pos, pos + 4)
            if (!hex.all { it.isAsciiHexDigit() }) throw LexException(LexError.UnterminatedString)
            sb.append("\\u").append(hex)
            pos += 4
        } else {
            sb.append('\\').append(c)
        }
    }

    // -------------------------------------------------------------------------
    // Character class:  %Upper alphas*
    // -------------------------------------------------------------------------

    private fun lexCharacterClass() {
        if (pos >= input.length || !input[pos].isAsciiUpper()) {
            throw LexException(LexError.UnexpectedCharacter("%"))
        }
        val name = StringBuilder()
        name.append(input[pos++])
        while (pos < input.length && input[pos].isAsciiAlpha()) {
            name.append(input[pos++])
        }
        emit(Token.CharacterClass(name.toString()))
    }

    // -------------------------------------------------------------------------
    // Position assertion:  @alpha (alnum | '-')*
    // -------------------------------------------------------------------------

    private fun lexPositionAssertion() {
        if (pos >= input.length || !input[pos].isAsciiAlpha()) {
            throw LexException(LexError.UnexpectedCharacter("@"))
        }
        val name = StringBuilder()
        name.append(input[pos++])
        while (pos < input.length && (input[pos].isAsciiAlnum() || input[pos] == '-')) {
            name.append(input[pos++])
        }
        emit(Token.PositionAssertion(name.toString()))
    }

    // -------------------------------------------------------------------------
    // Integer
    // -------------------------------------------------------------------------

    private fun lexInteger(first: Char) {
        val digits = StringBuilder()
        digits.append(first)
        while (pos < input.length && input[pos].isAsciiDigit()) {
            digits.append(input[pos++])
        }
        val n = digits.toString().toIntOrNull()
            ?: throw LexException(LexError.UnexpectedCharacter(digits.toString()))
        emit(Token.IntegerToken(n))
    }

    // -------------------------------------------------------------------------
    // Identifier / keyword
    // -------------------------------------------------------------------------

    private fun lexIdentifier(first: Char) {
        val name = StringBuilder()
        name.append(first)
        while (pos < input.length && (input[pos].isAsciiAlnum() || input[pos] == '-')) {
            name.append(input[pos++])
        }
        val token = when (name.toString()) {
            "as" -> Token.As
            "excluding" -> Token.Excluding
            "fewest" -> Token.Fewest
            "true" -> Token.True
            "false" -> Token.False
            else -> Token.Identifier(name.toString())
        }
        emit(token)
    }

    // -------------------------------------------------------------------------
    // Range operator: first '.' already consumed, expect second '.'
    // -------------------------------------------------------------------------

    private fun lexRangeOperator() {
        if (pos < input.length && input[pos] == '.') {
            pos++
            emit(Token.RangeOperator)
        } else {
            throw LexException(LexError.UnexpectedCharacter("."))
        }
    }
}

private fun Char.isAsciiDigit() = this in '0'..'9'
private fun Char.isAsciiUpper() = this in 'A'..'Z'
private fun Char.isAsciiLower() = this in 'a'..'z'
private fun Char.isAsciiAlpha() = isAsciiUpper() || isAsciiLower()
private fun Char.isAsciiAlnum() = isAsciiAlpha() || isAsciiDigit()
private fun Char.isAsciiHexDigit() = isAsciiDigit() || this in 'a'..'f' || this in 'A'..'F'
