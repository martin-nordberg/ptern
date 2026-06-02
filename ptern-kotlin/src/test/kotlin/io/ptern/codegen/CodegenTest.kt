package io.ptern.codegen

import com.fasterxml.jackson.databind.ObjectMapper
import io.ptern.lexer.Lexer
import io.ptern.parser.Parser
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.params.ParameterizedTest
import org.junit.jupiter.params.provider.MethodSource
import java.nio.file.Paths
import java.util.stream.Stream

class CodegenTest {

    @ParameterizedTest(name = "{0}")
    @MethodSource("fixtureStream")
    fun fixture(id: String, pattern: String, expectedSource: String, expectedFlags: Set<RegexOption>) {
        val tokens = Lexer.lex(pattern)
        val parsed = Parser.parse(tokens)
        val compiled = compile(parsed)
        assertEquals(expectedSource, compiled.source, "id=$id: source mismatch")
        assertEquals(expectedFlags, compiled.flags, "id=$id: flags mismatch")
    }

    companion object {
        private val MAPPER = ObjectMapper()

        @JvmStatic
        fun fixtureStream(): Stream<org.junit.jupiter.params.provider.Arguments> {
            val fixtureFile = Paths.get("../test-fixtures/codegen/codegen.json").toAbsolutePath().toFile()
            val fixtures = MAPPER.readTree(fixtureFile)
            return fixtures.elements().asSequence().map { node ->
                val expectNode = node["expect"]
                // Use jvmSource if present (set-difference syntax differs between JS and JVM)
                val source = if (expectNode.has("jvmSource"))
                    expectNode["jvmSource"].asText()
                else
                    expectNode["source"].asText()
                val flags = parseFlags(expectNode["flags"].asText())
                org.junit.jupiter.params.provider.Arguments.of(
                    node["id"].asText(),
                    node["pattern"].asText(),
                    source,
                    flags,
                )
            }.toList().stream()
        }

        // Parse a JS-style flags string (e.g. "vim") into a Set<RegexOption>.
        // The "v" flag is JS-specific (Unicode sets mode); JVM doesn't need it.
        private fun parseFlags(flags: String): Set<RegexOption> = buildSet {
            if ('i' in flags) add(RegexOption.IGNORE_CASE)
            if ('m' in flags) add(RegexOption.MULTILINE)
        }
    }
}
