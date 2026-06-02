package io.ptern.formatter

import com.fasterxml.jackson.databind.JsonNode
import com.fasterxml.jackson.databind.ObjectMapper
import io.ptern.Ptern
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.assertThrows
import org.junit.jupiter.params.ParameterizedTest
import org.junit.jupiter.params.provider.MethodSource
import java.nio.file.Paths
import java.util.stream.Stream

class FormatterTest {

    @ParameterizedTest(name = "{0}")
    @MethodSource("fixtureStream")
    fun fixture(id: String, input: String, optNode: JsonNode?, expect: JsonNode) {
        val opts = parseOptions(optNode)

        if (expect.isObject && expect.has("error")) {
            val ex = assertThrows<PternFormatException>("$id: should throw") {
                Ptern.format(input, opts)
            }
            when (expect["error"].asText()) {
                "lexError" -> assert(ex.formatError is FormatError.FormatLexError) { "$id: expected FormatLexError, got ${ex.formatError}" }
                "parseError" -> assert(ex.formatError is FormatError.FormatParseError) { "$id: expected FormatParseError, got ${ex.formatError}" }
                "invalidLineWidth" -> assert(ex.formatError is FormatError.InvalidLineWidth) { "$id: expected InvalidLineWidth, got ${ex.formatError}" }
                else -> throw IllegalArgumentException("Unknown error kind: ${expect["error"].asText()}")
            }
        } else {
            val result = Ptern.format(input, opts)
            assertEquals(expect.asText(), result, "id=$id")
        }
    }

    private fun parseOptions(node: JsonNode?): FormatOptions {
        if (node == null || node.isNull) return FormatOptions()
        return FormatOptions(
            lineWidth = if (node.has("lineWidth")) node["lineWidth"].asInt() else 80,
            compact = if (node.has("compact")) node["compact"].asBoolean() else false,
            aligned = if (node.has("aligned")) node["aligned"].asBoolean() else true,
            reordered = if (node.has("reordered")) node["reordered"].asBoolean() else false,
        )
    }

    companion object {
        private val MAPPER = ObjectMapper()

        @JvmStatic
        fun fixtureStream(): Stream<org.junit.jupiter.params.provider.Arguments> {
            val file = Paths.get("../test-fixtures/format/format.json").toAbsolutePath().toFile()
            return MAPPER.readTree(file).elements().asSequence().map { node ->
                org.junit.jupiter.params.provider.Arguments.of(
                    node["id"].asText(),
                    node["input"].asText(),
                    node["options"],
                    node["expect"],
                )
            }.toList().stream()
        }
    }
}
