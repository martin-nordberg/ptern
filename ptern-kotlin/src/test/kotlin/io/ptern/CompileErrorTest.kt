package io.ptern

import com.fasterxml.jackson.databind.ObjectMapper
import org.junit.jupiter.api.Assertions.assertInstanceOf
import org.junit.jupiter.api.assertThrows
import org.junit.jupiter.params.ParameterizedTest
import org.junit.jupiter.params.provider.MethodSource
import java.nio.file.Paths
import java.util.stream.Stream

class CompileErrorTest {

    @ParameterizedTest(name = "{0}")
    @MethodSource("fixtureStream")
    fun fixture(id: String, pattern: String, expectedError: String) {
        val ex = assertThrows<PternCompileException>("$id: should throw") {
            Ptern.compile(pattern)
        }
        when (expectedError) {
            "lexError" -> assertInstanceOf(CompileError.LexError::class.java, ex.error, "$id: error type")
            "parseError" -> assertInstanceOf(CompileError.ParseError::class.java, ex.error, "$id: error type")
            "semanticErrors" -> assertInstanceOf(CompileError.SemanticErrors::class.java, ex.error, "$id: error type")
            else -> throw IllegalArgumentException("Unknown expected error: $expectedError")
        }
    }

    companion object {
        private val MAPPER = ObjectMapper()

        @JvmStatic
        fun fixtureStream(): Stream<org.junit.jupiter.params.provider.Arguments> {
            val fixtureFile = Paths.get("../test-fixtures/api/compile.json").toAbsolutePath().toFile()
            val fixtures = MAPPER.readTree(fixtureFile)
            return fixtures.elements().asSequence().map { node ->
                org.junit.jupiter.params.provider.Arguments.of(
                    node["id"].asText(),
                    node["pattern"].asText(),
                    node["expect"]["error"].asText(),
                )
            }.toList().stream()
        }
    }
}
