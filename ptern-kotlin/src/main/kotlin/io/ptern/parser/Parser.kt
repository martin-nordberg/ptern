package io.ptern.parser

import io.ptern.lexer.Token
import io.ptern.lexer.tokenDisplay
import io.ptern.parser.ast.*

object Parser {
    fun parse(tokens: List<Token>): ParsedPtern {
        val stream = TokenStream(tokens)
        val result = try {
            parsePtern(stream)
        } catch (e: InternalParseFailure) {
            throw ParseException(e.error)
        }
        if (!stream.isEmpty()) {
            val tok = stream.peek()
            val got = if (tok != null) tokenDisplay(tok) else "<unknown>"
            throw ParseException(ParseError.UnexpectedToken("end of input", got))
        }
        return result
    }
}

private class InternalParseFailure(val error: ParseError) : Exception()

private fun fail(error: ParseError): Nothing = throw InternalParseFailure(error)

// ---------------------------------------------------------------------------
// Top-level
// ---------------------------------------------------------------------------

private fun parsePtern(s: TokenStream): ParsedPtern {
    s.skipWhitespace()
    var firstBlock = collectCommentBlock(s)
    val (pternComments, carried0) = resolveLeadingComments(firstBlock, s)
    var carried = carried0
    val (annotations, carried1) = parseAnnotations(s, carried)
    carried = carried1
    val (definitions, carried2) = parseDefinitions(s, carried)
    carried = carried2
    val bodyComments = carried
    val body = parseExpression(s)
    s.skipWhitespace()
    val raw = s.peekRaw()
    if (raw is Token.Comment) fail(ParseError.TrailingComment)
    if (raw != null) fail(ParseError.UnexpectedToken("end of input", tokenDisplay(raw)))
    return ParsedPtern(pternComments, annotations, definitions, bodyComments, body)
}

private fun resolveLeadingComments(
    firstBlock: List<String>,
    s: TokenStream,
): Pair<List<String>, List<String>> {
    val raw = s.peekRaw()
    if (raw is Token.Whitespace && raw.hasBlankLine) {
        s.advance()
        s.skipNonBlankWhitespace()
        val itemBlock = collectCommentBlock(s)
        val raw2 = s.peekRaw()
        if (raw2 is Token.Whitespace && raw2.hasBlankLine) {
            if (itemBlock.isNotEmpty()) fail(ParseError.OrphanedComment)
            return Pair(firstBlock, itemBlock)
        }
        return Pair(firstBlock, itemBlock)
    }
    return Pair(emptyList(), firstBlock)
}

// ---------------------------------------------------------------------------
// Annotations
// ---------------------------------------------------------------------------

private fun parseAnnotations(s: TokenStream, initialCarried: List<String>): Pair<List<PternAnnotation>, List<String>> {
    val acc = mutableListOf<PternAnnotation>()
    var carried = initialCarried
    while (true) {
        s.skipWhitespace()
        if (s.peekRaw() !is Token.Bang) break
        val ann = parseAnnotation(s, carried)
        val nextBlock = collectItemComments(s)
        val raw = s.peekRaw()
        carried = if (raw is Token.Whitespace && raw.hasBlankLine) {
            if (nextBlock.isNotEmpty()) fail(ParseError.OrphanedComment)
            nextBlock
        } else {
            nextBlock
        }
        acc.add(ann)
    }
    return Pair(acc, carried)
}

private fun parseAnnotation(s: TokenStream, comments: List<String>): PternAnnotation {
    s.advance() // consume !
    s.skipWhitespace()
    val name = expectIdentifier(s)
    s.skipWhitespace()
    expectToken(s, Token.Equals)
    s.skipWhitespace()
    val next = s.peek()
    return when (next) {
        Token.True -> { s.advance(); PternAnnotation(comments, name, true) }
        Token.False -> { s.advance(); PternAnnotation(comments, name, false) }
        null -> fail(ParseError.UnexpectedEndOfInput)
        else -> fail(ParseError.UnexpectedToken("true or false", tokenDisplay(next)))
    }
}

// ---------------------------------------------------------------------------
// Definitions
// ---------------------------------------------------------------------------

private fun parseDefinitions(s: TokenStream, initialCarried: List<String>): Pair<List<Definition>, List<String>> {
    val acc = mutableListOf<Definition>()
    var carried = initialCarried
    while (true) {
        s.skipWhitespace()
        val newComments = collectCommentBlock(s)
        val raw = s.peekRaw()
        if (raw is Token.Whitespace && raw.hasBlankLine) {
            if (newComments.isNotEmpty()) fail(ParseError.OrphanedComment)
            break
        }
        val allCarried = carried + newComments
        if (!looksLikeDefinition(s)) {
            carried = allCarried
            break
        }
        val def = parseDefinition(s, allCarried)
        val nextBlock = collectItemComments(s)
        val raw2 = s.peekRaw()
        carried = if (raw2 is Token.Whitespace && raw2.hasBlankLine) {
            if (nextBlock.isNotEmpty()) fail(ParseError.OrphanedComment)
            nextBlock
        } else {
            nextBlock
        }
        acc.add(def)
    }
    return Pair(acc, carried)
}

private fun looksLikeDefinition(s: TokenStream): Boolean {
    val remaining = s.remaining()
    if (remaining.firstOrNull() !is Token.Identifier) return false
    val rest = remaining.drop(1).filter { it !is Token.Whitespace }
    return rest.firstOrNull() is Token.Equals
}

private fun parseDefinition(s: TokenStream, comments: List<String>): Definition {
    val name = expectIdentifier(s)
    s.skipWhitespace()
    expectToken(s, Token.Equals)
    s.skipWhitespace()
    val body = parseExpression(s)
    s.skipWhitespace()
    expectToken(s, Token.Semicolon)
    return Definition(comments, name, body)
}

// ---------------------------------------------------------------------------
// Comment collection helpers
// ---------------------------------------------------------------------------

private fun collectCommentBlock(s: TokenStream): List<String> {
    val acc = mutableListOf<String>()
    while (true) {
        val raw = s.peekRaw()
        if (raw !is Token.Comment) break
        s.advance()
        s.skipNonBlankWhitespace()
        acc.add(raw.content)
    }
    return acc
}

private fun collectItemComments(s: TokenStream): List<String> {
    s.skipNonBlankWhitespace()
    return collectCommentBlock(s)
}

// ---------------------------------------------------------------------------
// Expression (alternation)
// ---------------------------------------------------------------------------

private fun parseExpression(s: TokenStream): Expression {
    val firstSeq = parseSequence(s)
    val alternatives = mutableListOf(firstSeq)
    while (true) {
        val savedPos = s.save()
        s.skipWhitespace()
        if (s.peekRaw() !is Token.AlternativeOperator) { s.restore(savedPos); break }
        s.advance()
        s.skipWhitespace()
        alternatives.add(parseSequence(s))
    }
    return Expression(alternatives)
}

// ---------------------------------------------------------------------------
// Sequence
// ---------------------------------------------------------------------------

private fun parseSequence(s: TokenStream): Sequence {
    val first = parseCapture(s)
    val items = mutableListOf(first)
    while (s.nextIsWhitespace() && nextStartsCapture(s)) {
        s.skipWhitespace()
        if (!startsCapture(s.peek())) break
        items.add(parseCapture(s))
    }
    return Sequence(items)
}

private fun nextStartsCapture(s: TokenStream): Boolean {
    val savedPos = s.save()
    s.skipWhitespace()
    val result = startsCapture(s.peekRaw())
    s.restore(savedPos)
    return result
}

private fun startsCapture(tok: Token?): Boolean = when (tok) {
    is Token.SingleQuotedLiteral,
    is Token.DoubleQuotedLiteral,
    is Token.CharacterClass,
    is Token.PositionAssertion,
    is Token.LeftBrace,
    is Token.LeftParen -> true
    else -> false
}

// ---------------------------------------------------------------------------
// Capture
// ---------------------------------------------------------------------------

private fun parseCapture(s: TokenStream): Capture {
    val rep = parseRepetition(s)
    val savedPos = s.save()
    s.skipWhitespace()
    return if (s.peekRaw() is Token.As) {
        s.advance()
        s.skipWhitespace()
        val name = expectIdentifier(s)
        Capture(rep, name)
    } else {
        s.restore(savedPos)
        Capture(rep, null)
    }
}

// ---------------------------------------------------------------------------
// Repetition
// ---------------------------------------------------------------------------

private fun parseRepetition(s: TokenStream): Repetition {
    val excl = parseExclusion(s)
    val savedPos = s.save()
    s.skipWhitespace()
    if (s.peekRaw() !is Token.Asterisk) { s.restore(savedPos); return Repetition(excl, null) }
    s.advance()
    s.skipWhitespace()
    val count = parseRepCount(s)
    val savedPos2 = s.save()
    s.skipWhitespace()
    return if (s.peekRaw() is Token.Fewest) {
        s.advance()
        Repetition(excl, count.copy(lazy = true))
    } else {
        s.restore(savedPos2)
        Repetition(excl, count)
    }
}

private fun parseRepCount(s: TokenStream): RepCount {
    val next = s.peek()
    if (next !is Token.IntegerToken) {
        if (next != null) fail(ParseError.UnexpectedToken("repetition count (integer)", tokenDisplay(next)))
        fail(ParseError.UnexpectedEndOfInput)
    }
    s.advance()
    val min = next.value
    if (s.peekRaw() !is Token.RangeOperator) {
        return RepCount(min, RepUpper.None, false)
    }
    s.advance()
    val upper = parseRepUpper(s)
    return RepCount(min, upper, false)
}

private fun parseRepUpper(s: TokenStream): RepUpper {
    val next = s.peek()
    return when {
        next is Token.QuestionMark -> { s.advance(); RepUpper.Unbounded }
        next is Token.IntegerToken -> { s.advance(); RepUpper.Exact(next.value) }
        next != null -> fail(ParseError.UnexpectedToken("upper bound (integer or ?)", tokenDisplay(next)))
        else -> fail(ParseError.UnexpectedEndOfInput)
    }
}

// ---------------------------------------------------------------------------
// Exclusion
// ---------------------------------------------------------------------------

private fun parseExclusion(s: TokenStream): Exclusion {
    val base = parseRangeItem(s)
    val savedPos = s.save()
    s.skipWhitespace()
    return if (s.peekRaw() is Token.Excluding) {
        s.advance()
        s.skipWhitespace()
        Exclusion(base, parseRangeItem(s))
    } else {
        s.restore(savedPos)
        Exclusion(base, null)
    }
}

// ---------------------------------------------------------------------------
// Range item
// ---------------------------------------------------------------------------

private fun parseRangeItem(s: TokenStream): RangeItem {
    val from = parseAtom(s)
    return if (s.peekRaw() is Token.RangeOperator) {
        s.advance()
        RangeItem.CharRange(from, parseAtom(s))
    } else {
        RangeItem.SingleAtom(from)
    }
}

// ---------------------------------------------------------------------------
// Atom
// ---------------------------------------------------------------------------

private fun parseAtom(s: TokenStream): Atom {
    val next = s.peek() ?: fail(ParseError.UnexpectedEndOfInput)
    return when (next) {
        is Token.SingleQuotedLiteral -> { s.advance(); Atom.Literal(next.content) }
        is Token.DoubleQuotedLiteral -> { s.advance(); Atom.Literal(next.content) }
        is Token.CharacterClass -> { s.advance(); Atom.CharClass(next.name) }
        is Token.PositionAssertion -> { s.advance(); Atom.PositionAssertion(next.name) }
        is Token.LeftBrace -> parseInterpolation(s)
        is Token.LeftParen -> parseGroup(s)
        else -> fail(ParseError.UnexpectedToken("literal, character class, position assertion, { or (", tokenDisplay(next)))
    }
}

private fun parseInterpolation(s: TokenStream): Atom {
    s.advance() // consume {
    s.skipWhitespace()
    val name = expectIdentifier(s)
    s.skipWhitespace()
    expectToken(s, Token.RightBrace)
    return Atom.Interpolation(name)
}

private fun parseGroup(s: TokenStream): Atom {
    s.advance() // consume (
    s.skipWhitespace()
    val expr = parseExpression(s)
    s.skipWhitespace()
    expectToken(s, Token.RightParen)
    return Atom.Group(expr)
}

// ---------------------------------------------------------------------------
// Utility helpers
// ---------------------------------------------------------------------------

private fun expectIdentifier(s: TokenStream): String {
    val next = s.peek()
    if (next is Token.Identifier) {
        s.advance()
        return next.name
    }
    if (next != null) fail(ParseError.UnexpectedToken("identifier", tokenDisplay(next)))
    fail(ParseError.UnexpectedEndOfInput)
}

private fun expectToken(s: TokenStream, expected: Token) {
    val next = s.peek()
    if (next != null && next::class == expected::class) {
        s.advance()
        return
    }
    val exp = tokenDisplay(expected)
    if (next != null) fail(ParseError.UnexpectedToken(exp, tokenDisplay(next)))
    fail(ParseError.UnexpectedToken(exp, "end of input"))
}
