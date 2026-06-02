package io.ptern.parser

import io.ptern.lexer.Token
import io.ptern.lexer.tokenDisplay
import io.ptern.lexer.tokensEqual

class TokenStream(private val tokens: List<Token>) {
    var pos: Int = 0

    fun peekRaw(): Token? = tokens.getOrNull(pos)

    /** Next non-whitespace token without advancing. */
    fun peek(): Token? {
        var i = pos
        while (i < tokens.size) {
            val t = tokens[i]
            if (t !is Token.Whitespace) return t
            i++
        }
        return null
    }

    fun advance(): Token? = tokens.getOrNull(pos)?.also { pos++ }

    fun skipWhitespace() {
        while (pos < tokens.size && tokens[pos] is Token.Whitespace) pos++
    }

    /** Skip a single non-blank-line whitespace token if present; stop at blank-line whitespace. */
    fun skipNonBlankWhitespace() {
        val t = tokens.getOrNull(pos)
        if (t is Token.Whitespace && !t.hasBlankLine) pos++
    }

    fun nextIsWhitespace(): Boolean = tokens.getOrNull(pos) is Token.Whitespace

    /** Advance past whitespace then consume `expected` if it matches. Returns true and advances on match. */
    fun eat(expected: Token): Boolean {
        val savedPos = pos
        skipWhitespace()
        val t = tokens.getOrNull(pos)
        if (t != null && tokensEqual(t, expected)) {
            pos++
            return true
        }
        pos = savedPos
        return false
    }

    fun isEmpty(): Boolean = peek() == null

    fun remaining(): List<Token> = tokens.subList(pos, tokens.size)

    fun save(): Int = pos
    fun restore(savedPos: Int) { pos = savedPos }

    fun display(token: Token): String = tokenDisplay(token)
}
