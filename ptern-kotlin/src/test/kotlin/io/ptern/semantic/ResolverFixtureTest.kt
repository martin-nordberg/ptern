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

class ResolverFixtureTest {

    @ParameterizedTest(name = "{0}")
    @MethodSource("fixtureStream")
    fun fixture(id: String, pattern: String, expect: JsonNode) {
        val tokens = Lexer.lex(pattern)
        val parsed = Parser.parse(tokens)
        // DuplicateCapture errors are intentionally filtered (handled by codegen)
        val errors = Resolver.resolve(parsed).filterNot { it is SemanticError.DuplicateCapture }

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
        "undefinedReference" -> error is SemanticError.UndefinedReference
        "duplicateDefinition" -> error is SemanticError.DuplicateDefinition
        "circularDefinition" -> error is SemanticError.CircularDefinition
        "duplicateCapture" -> error is SemanticError.DuplicateCapture
        "captureDefinitionConflict" -> error is SemanticError.CaptureDefinitionConflict
        "unusedDefinition" -> error is SemanticError.UnusedDefinition
        else -> false
    }

    companion object {
        private val MAPPER = ObjectMapper()

        @JvmStatic
        fun fixtureStream(): Stream<org.junit.jupiter.params.provider.Arguments> {
            val file = Paths.get("../test-fixtures/semantic/resolver.json").toAbsolutePath().toFile()
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
