package io.ptern.lexer

import com.fasterxml.jackson.databind.JsonNode
import com.fasterxml.jackson.databind.ObjectMapper
import org.junit.jupiter.api.Assertions.*
import org.junit.jupiter.params.ParameterizedTest
import org.junit.jupiter.params.provider.MethodSource
import java.nio.file.Paths
import java.util.stream.Stream

class LexerTest {

    @ParameterizedTest(name = "{0}")
    @MethodSource("fixtureStream")
    fun fixture(id: String, input: String, expect: JsonNode) {
        if (expect.isObject && expect.has("error")) {
            // Error case
            val ex = assertThrows(LexException::class.java) { Lexer.lex(input) }
            val kind = expect["error"].asText()
            val actual = errorKind(ex.lexError)
            assertEquals(kind, actual, "id=$id: wrong error kind")
        } else {
            // Success case — expect is an array of token JSON nodes
            val tokens = Lexer.lex(input)
            assertEquals(expect.size(), tokens.size, "id=$id: token count mismatch")
            for (i in tokens.indices) {
                assertTokenMatches(id, i, expect[i], tokens[i])
            }
        }
    }

    private fun errorKind(e: LexError): String = when (e) {
        is LexError.UnexpectedCharacter -> "unexpectedCharacter"
        LexError.UnterminatedString -> "unterminatedString"
        LexError.InlineComment -> "inlineComment"
    }

    private fun assertTokenMatches(id: String, i: Int, node: JsonNode, token: Token) {
        val kind = node["kind"].asText()
        val msg = "id=$id token[$i]"
        when (kind) {
            "singleQuotedLiteral" -> {
                assertTrue(token is Token.SingleQuotedLiteral, "$msg: expected SingleQuotedLiteral, got $token")
                assertEquals(node["content"].asText(), (token as Token.SingleQuotedLiteral).content, msg)
            }
            "doubleQuotedLiteral" -> {
                assertTrue(token is Token.DoubleQuotedLiteral, "$msg: expected DoubleQuotedLiteral, got $token")
                assertEquals(node["content"].asText(), (token as Token.DoubleQuotedLiteral).content, msg)
            }
            "characterClass" -> {
                assertTrue(token is Token.CharacterClass, "$msg: expected CharacterClass, got $token")
                assertEquals(node["name"].asText(), (token as Token.CharacterClass).name, msg)
            }
            "integer" -> {
                assertTrue(token is Token.IntegerToken, "$msg: expected IntegerToken, got $token")
                assertEquals(node["value"].asInt(), (token as Token.IntegerToken).value, msg)
            }
            "positionAssertion" -> {
                assertTrue(token is Token.PositionAssertion, "$msg: expected PositionAssertion, got $token")
                assertEquals(node["name"].asText(), (token as Token.PositionAssertion).name, msg)
            }
            "identifier" -> {
                assertTrue(token is Token.Identifier, "$msg: expected Identifier, got $token")
                assertEquals(node["name"].asText(), (token as Token.Identifier).name, msg)
            }
            "whitespace" -> {
                assertTrue(token is Token.Whitespace, "$msg: expected Whitespace, got $token")
                assertEquals(node["hasBlankLine"].asBoolean(), (token as Token.Whitespace).hasBlankLine, msg)
            }
            "comment" -> {
                assertTrue(token is Token.Comment, "$msg: expected Comment, got $token")
                assertEquals(node["content"].asText(), (token as Token.Comment).content, msg)
            }
            "rangeOperator" -> assertTrue(token is Token.RangeOperator, "$msg: expected RangeOperator")
            "asterisk" -> assertTrue(token is Token.Asterisk, "$msg: expected Asterisk")
            "alternativeOperator" -> assertTrue(token is Token.AlternativeOperator, "$msg: expected AlternativeOperator")
            "equals" -> assertTrue(token is Token.Equals, "$msg: expected Equals")
            "leftBrace" -> assertTrue(token is Token.LeftBrace, "$msg: expected LeftBrace")
            "rightBrace" -> assertTrue(token is Token.RightBrace, "$msg: expected RightBrace")
            "leftParen" -> assertTrue(token is Token.LeftParen, "$msg: expected LeftParen")
            "rightParen" -> assertTrue(token is Token.RightParen, "$msg: expected RightParen")
            "semicolon" -> assertTrue(token is Token.Semicolon, "$msg: expected Semicolon")
            "as" -> assertTrue(token is Token.As, "$msg: expected As")
            "excluding" -> assertTrue(token is Token.Excluding, "$msg: expected Excluding")
            "true" -> assertTrue(token is Token.True, "$msg: expected True")
            "false" -> assertTrue(token is Token.False, "$msg: expected False")
            "fewest" -> assertTrue(token is Token.Fewest, "$msg: expected Fewest")
            "bang" -> assertTrue(token is Token.Bang, "$msg: expected Bang")
            "questionMark" -> assertTrue(token is Token.QuestionMark, "$msg: expected QuestionMark")
            else -> fail("$msg: unknown token kind '$kind' in fixture")
        }
    }

    companion object {
        private val MAPPER = ObjectMapper()

        @JvmStatic
        fun fixtureStream(): Stream<org.junit.jupiter.params.provider.Arguments> {
            val fixtureFile = Paths.get("../test-fixtures/lexer/lexer.json").toAbsolutePath().toFile()
            val fixtures = MAPPER.readTree(fixtureFile)
            return fixtures.elements().asSequence().map { node ->
                org.junit.jupiter.params.provider.Arguments.of(
                    node["id"].asText(),
                    node["input"].asText(),
                    node["expect"],
                )
            }.toList().stream()
        }
    }
}
