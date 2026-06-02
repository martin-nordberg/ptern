package io.ptern.semantic

import io.ptern.lexer.Lexer
import io.ptern.parser.Parser
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class ValidatorTest {

    private fun validate(source: String): List<SemanticError> {
        val tokens = Lexer.lex(source)
        val parsed = Parser.parse(tokens)
        return Validator.validate(parsed)
    }

    @Test fun `valid pattern has no errors`() {
        assertTrue(validate("'hello'").isEmpty())
    }

    @Test fun `unknown annotation is flagged`() {
        val errs = validate("!bogus = true\n'x'")
        assertTrue(errs.any { it is SemanticError.UnknownAnnotation && it.name == "bogus" })
    }

    @Test fun `duplicate annotation is flagged`() {
        val errs = validate("!case-insensitive = true\n!case-insensitive = false\n'x'")
        assertTrue(errs.any { it is SemanticError.DuplicateAnnotation && it.name == "case-insensitive" })
    }

    @Test fun `empty literal is flagged`() {
        val errs = validate("''")
        assertTrue(errs.any { it is SemanticError.EmptyLiteral })
    }

    @Test fun `invalid escape sequence is flagged`() {
        val errs = validate("'\\q'")
        assertTrue(errs.any { it is SemanticError.InvalidEscapeSequence && it.seq == "\\q" })
    }

    @Test fun `valid escape sequences pass`() {
        assertTrue(validate("'\\n\\t\\r\\\\\\\"'").isEmpty())
    }

    @Test fun `inverted range is flagged`() {
        val errs = validate("'z'..'a'")
        assertTrue(errs.any { it is SemanticError.InvertedRange })
    }

    @Test fun `valid range passes`() {
        assertTrue(validate("'a'..'z'").isEmpty())
    }

    @Test fun `inverted repetition bounds flagged`() {
        val errs = validate("%Digit * 10..3")
        assertTrue(errs.any { it is SemanticError.InvertedRepetitionBounds })
    }

    @Test fun `fewest on exact repetition flagged`() {
        val errs = validate("%Digit * 4 fewest")
        assertTrue(errs.any { it is SemanticError.FewestOnExactRepetition })
    }

    @Test fun `unknown position assertion flagged`() {
        val errs = validate("@bogus-pos")
        assertTrue(errs.any { it is SemanticError.UnknownPositionAssertion && it.name == "bogus-pos" })
    }

    @Test fun `position assertion in repetition flagged`() {
        val errs = validate("@word-start * 3")
        assertTrue(errs.any { it is SemanticError.PositionAssertionInRepetition })
    }

    @Test fun `invalid exclusion operand flagged`() {
        val errs = validate("%Digit excluding ('1' * 2)")
        assertTrue(errs.any { it is SemanticError.InvalidExclusionOperand })
    }

    @Test fun `empty character set flagged`() {
        val errs = validate("'x' excluding 'x'")
        assertTrue(errs.any { it is SemanticError.EmptyCharacterSet })
    }

    @Test fun `substitutions-ignore-matching without substitutable flagged`() {
        val errs = validate("!substitutions-ignore-matching = true\n'x'")
        assertTrue(errs.any { it is SemanticError.SubstitutionsIgnoreMatchingWithoutSubstitutable })
    }

    @Test fun `not-substitutable body flagged when substitutable set`() {
        val errs = validate("!substitutable = true\n%Digit")
        assertTrue(errs.any { it is SemanticError.NotSubstitutableBody })
    }
}
