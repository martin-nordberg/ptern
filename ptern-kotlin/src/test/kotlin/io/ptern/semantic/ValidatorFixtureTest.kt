package io.ptern.semantic

import com.fasterxml.jackson.databind.JsonNode
import com.fasterxml.jackson.databind.ObjectMapper
import io.ptern.lexer.Lexer
import io.ptern.parser.Parser
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.params.ParameterizedTest
import org.junit.jupiter.params.provider.MethodSource
import java.nio.file.Paths
import java.util.stream.Stream

class ValidatorFixtureTest {

    @ParameterizedTest(name = "{0}")
    @MethodSource("fixtureStream")
    fun fixture(id: String, pattern: String, expect: JsonNode) {
        val tokens = Lexer.lex(pattern)
        val parsed = Parser.parse(tokens)
        val errors = Validator.validate(parsed)

        if (expect.isTextual && expect.asText() == "ok") {
            assertTrue(errors.isEmpty(), "id=$id: expected no errors, got: $errors")
        } else {
            val errorKind = expect["error"].asText()
            assertTrue(
                errors.any { matchesKind(it, errorKind) },
                "id=$id: expected error '$errorKind' in $errors",
            )
        }
    }

    private fun matchesKind(error: SemanticError, kind: String): Boolean = when (kind) {
        "emptyLiteral" -> error is SemanticError.EmptyLiteral
        "invalidEscapeSequence" -> error is SemanticError.InvalidEscapeSequence
        "invertedRange" -> error is SemanticError.InvertedRange
        "invalidRangeEndpoint" -> error is SemanticError.InvalidRangeEndpoint
        "invertedRepetitionBounds" -> error is SemanticError.InvertedRepetitionBounds
        "fewestOnExactRepetition" -> error is SemanticError.FewestOnExactRepetition
        "unknownAnnotation" -> error is SemanticError.UnknownAnnotation
        "duplicateAnnotation" -> error is SemanticError.DuplicateAnnotation
        "unknownPositionAssertion" -> error is SemanticError.UnknownPositionAssertion
        "positionAssertionInRepetition" -> error is SemanticError.PositionAssertionInRepetition
        "emptyCharacterSet" -> error is SemanticError.EmptyCharacterSet
        "invalidExclusionOperand" -> error is SemanticError.InvalidExclusionOperand
        "substitutionsIgnoreMatchingWithoutSubstitutable" -> error is SemanticError.SubstitutionsIgnoreMatchingWithoutSubstitutable
        "notSubstitutableBody" -> error is SemanticError.NotSubstitutableBody
        else -> false
    }

    companion object {
        private val MAPPER = ObjectMapper()

        @JvmStatic
        fun fixtureStream(): Stream<org.junit.jupiter.params.provider.Arguments> {
            val file = Paths.get("../test-fixtures/semantic/validator.json").toAbsolutePath().toFile()
            return MAPPER.readTree(file).elements().asSequence().map { node ->
                org.junit.jupiter.params.provider.Arguments.of(
                    node["id"].asText(),
                    node["pattern"].asText(),
                    node["expect"],
                )
            }.toList().stream()
        }
    }
}
