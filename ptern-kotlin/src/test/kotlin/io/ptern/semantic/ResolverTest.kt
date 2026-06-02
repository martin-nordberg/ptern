package io.ptern.semantic

import io.ptern.lexer.Lexer
import io.ptern.parser.Parser
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class ResolverTest {

    private fun resolve(source: String): List<SemanticError> {
        val tokens = Lexer.lex(source)
        val parsed = Parser.parse(tokens)
        return Resolver.resolve(parsed)
    }

    @Test fun `valid pattern has no resolve errors`() {
        assertTrue(resolve("'hello'").isEmpty())
    }

    @Test fun `undefined reference in body flagged`() {
        val errs = resolve("{foo}")
        assertTrue(errs.any { it is SemanticError.UndefinedReference && it.name == "foo" })
    }

    @Test fun `defined reference resolves cleanly`() {
        assertTrue(resolve("foo = 'x' ; {foo}").isEmpty())
    }

    @Test fun `duplicate definition flagged`() {
        val errs = resolve("foo = 'a' ; foo = 'b' ; {foo}")
        assertTrue(errs.any { it is SemanticError.DuplicateDefinition && it.name == "foo" })
    }

    @Test fun `circular definition flagged`() {
        val errs = resolve("foo = {bar} ; bar = {foo} ; {foo}")
        assertTrue(errs.any { it is SemanticError.CircularDefinition })
    }

    @Test fun `duplicate capture names flagged`() {
        val errs = resolve("'a' as x 'b' as x")
        assertTrue(errs.any { it is SemanticError.DuplicateCapture && it.name == "x" })
    }

    @Test fun `capture definition conflict flagged`() {
        val errs = resolve("x = 'a' ; {x} as x")
        assertTrue(errs.any { it is SemanticError.CaptureDefinitionConflict && it.name == "x" })
    }

    @Test fun `backreference to earlier capture resolves`() {
        assertTrue(resolve("'a' as x {x}").isEmpty())
    }

    @Test fun `unused definition flagged`() {
        val errs = resolve("foo = 'a' ; bar = 'b' ; {foo}")
        assertTrue(errs.any { it is SemanticError.UnusedDefinition && it.name == "bar" })
    }

    @Test fun `all definitions used passes`() {
        assertTrue(resolve("foo = 'a' ; bar = {foo} ; {bar}").isEmpty())
    }

    @Test fun `undefined reference inside definition body flagged`() {
        val errs = resolve("foo = {notDefined} ; {foo}")
        assertTrue(errs.any { it is SemanticError.UndefinedReference && it.name == "notDefined" })
    }
}
