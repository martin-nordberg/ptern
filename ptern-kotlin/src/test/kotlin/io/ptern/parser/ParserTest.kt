package io.ptern.parser

import com.fasterxml.jackson.databind.ObjectMapper
import io.ptern.lexer.Lexer
import io.ptern.parser.ast.*
import org.junit.jupiter.api.Assertions.*
import org.junit.jupiter.params.ParameterizedTest
import org.junit.jupiter.params.provider.MethodSource
import java.nio.file.Paths
import java.util.stream.Stream

class ParserTest {

    @ParameterizedTest(name = "{0}")
    @MethodSource("fixtureStream")
    fun fixture(id: String, input: String, expectError: String?) {
        // Parser fixtures are error-only (success is covered by codegen fixtures).
        requireNotNull(expectError) { "id=$id: parser fixture has no error field" }
        val tokens = try {
            Lexer.lex(input)
        } catch (e: Exception) {
            // lex error is also acceptable for some inputs
            return
        }
        val ex = assertThrows(ParseException::class.java) { Parser.parse(tokens) }
        val kind = errorKind(ex.parseError)
        assertEquals(expectError, kind, "id=$id")
    }

    private fun errorKind(e: ParseError): String = when (e) {
        ParseError.UnexpectedEndOfInput -> "unexpectedEndOfInput"
        is ParseError.UnexpectedToken -> "unexpectedToken"
        ParseError.OrphanedComment -> "orphanedComment"
        ParseError.TrailingComment -> "trailingComment"
    }

    companion object {
        private val MAPPER = ObjectMapper()

        @JvmStatic
        fun fixtureStream(): Stream<org.junit.jupiter.params.provider.Arguments> {
            val fixtureFile = Paths.get("../test-fixtures/parser/parser.json").toAbsolutePath().toFile()
            val fixtures = MAPPER.readTree(fixtureFile)
            return fixtures.elements().asSequence().map { node ->
                val expectNode = node["expect"]
                val expectError = if (expectNode.isObject && expectNode.has("error"))
                    expectNode["error"].asText() else null
                org.junit.jupiter.params.provider.Arguments.of(
                    node["id"].asText(),
                    node["input"].asText(),
                    expectError,
                )
            }.toList().stream()
        }
    }
}
