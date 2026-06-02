package io.ptern

import com.fasterxml.jackson.databind.JsonNode
import com.fasterxml.jackson.databind.ObjectMapper
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.params.ParameterizedTest
import org.junit.jupiter.params.provider.MethodSource
import java.nio.file.Paths
import java.util.stream.Stream

class ApiTest {

    @ParameterizedTest(name = "{0}: {1}")
    @MethodSource("caseStream")
    fun apiCase(fixtureId: String, caseIndex: Int, pattern: String, op: String, caseNode: JsonNode) {
        val ptern = Ptern.compile(pattern)
        executeCaseOp(fixtureId, caseIndex, ptern, op, caseNode)
    }

    private fun executeCaseOp(id: String, idx: Int, ptern: Ptern, op: String, node: JsonNode) {
        val label = "$id[$idx]"
        when (op) {
            "matchesAllOf" -> {
                val result = ptern.matchesAllOf(node["input"].asText())
                assertEquals(node["expect"].asBoolean(), result, label)
            }
            "matchesStartOf" -> {
                val result = ptern.matchesStartOf(node["input"].asText())
                assertEquals(node["expect"].asBoolean(), result, label)
            }
            "matchesEndOf" -> {
                val result = ptern.matchesEndOf(node["input"].asText())
                assertEquals(node["expect"].asBoolean(), result, label)
            }
            "matchesIn" -> {
                val result = ptern.matchesIn(node["input"].asText())
                assertEquals(node["expect"].asBoolean(), result, label)
            }
            "matchAllOf" -> {
                val result = ptern.matchAllOf(node["input"].asText())
                assertOccurrence(label, node["expect"], result)
            }
            "matchStartOf" -> {
                val result = ptern.matchStartOf(node["input"].asText())
                assertOccurrence(label, node["expect"], result)
            }
            "matchEndOf" -> {
                val result = ptern.matchEndOf(node["input"].asText())
                assertOccurrence(label, node["expect"], result)
            }
            "matchFirstIn" -> {
                val result = ptern.matchFirstIn(node["input"].asText())
                assertOccurrence(label, node["expect"], result)
            }
            "matchNextIn" -> {
                val startIndex = node["startIndex"].asInt()
                val result = ptern.matchNextIn(node["input"].asText(), startIndex)
                assertOccurrence(label, node["expect"], result)
            }
            "matchAllIn" -> {
                val results = ptern.matchAllIn(node["input"].asText())
                val expected = node["expect"]
                assertEquals(expected.size(), results.size, "$label: list size")
                for (i in results.indices) assertOccurrence("$label[$i]", expected[i], results[i])
            }
            "replaceAllOf" -> {
                val result = ptern.replaceAllOf(node["input"].asText(), parseReplacements(node))
                assertEquals(node["expect"].asText(), result, label)
            }
            "replaceStartOf" -> {
                val result = ptern.replaceStartOf(node["input"].asText(), parseReplacements(node))
                assertEquals(node["expect"].asText(), result, label)
            }
            "replaceEndOf" -> {
                val result = ptern.replaceEndOf(node["input"].asText(), parseReplacements(node))
                assertEquals(node["expect"].asText(), result, label)
            }
            "replaceFirstIn" -> {
                val result = ptern.replaceFirstIn(node["input"].asText(), parseReplacements(node))
                assertEquals(node["expect"].asText(), result, label)
            }
            "replaceNextIn" -> {
                val startIndex = node["startIndex"].asInt()
                val result = ptern.replaceNextIn(node["input"].asText(), startIndex, parseReplacements(node))
                assertEquals(node["expect"].asText(), result, label)
            }
            "replaceAllIn" -> {
                val result = ptern.replaceAllIn(node["input"].asText(), parseReplacements(node))
                assertEquals(node["expect"].asText(), result, label)
            }
            "substitute" -> {
                val captures = parseReplacements(node["captures"])
                val result = ptern.substitute(captures)
                assertEquals(node["expect"].asText(), result, label)
            }
            else -> throw IllegalArgumentException("Unknown op: $op")
        }
    }

    private fun assertOccurrence(label: String, expected: JsonNode, actual: MatchOccurrence?) {
        if (expected.isNull) {
            assertNull(actual, "$label: expected null")
            return
        }
        val occ = checkNotNull(actual) { "$label: expected non-null MatchOccurrence" }
        assertEquals(expected["index"].asInt(), occ.index, "$label: index")
        assertEquals(expected["length"].asInt(), occ.length, "$label: length")
        val expectedCaptures = expected["captures"]
        val fields = expectedCaptures.fields().asSequence().associate { it.key to it.value.asText() }
        assertEquals(fields, occ.captures, "$label: captures")
    }

    private fun parseReplacements(node: JsonNode): Map<String, ReplacementValue> {
        val replacementsNode = if (node.has("replacements")) node["replacements"] else node
        val result = mutableMapOf<String, ReplacementValue>()
        replacementsNode.fields().forEach { (k, v) ->
            result[k] = ReplacementValue.Scalar(v.asText())
        }
        return result
    }

    companion object {
        private val MAPPER = ObjectMapper()

        @JvmStatic
        fun caseStream(): Stream<org.junit.jupiter.params.provider.Arguments> {
            val fixtureFile = Paths.get("../test-fixtures/api/api.json").toAbsolutePath().toFile()
            val fixtures = MAPPER.readTree(fixtureFile)
            return fixtures.elements().asSequence().flatMap { fixture ->
                val id = fixture["id"].asText()
                val pattern = fixture["pattern"].asText()
                val cases = fixture["cases"]
                cases.elements().asSequence().mapIndexed { idx, caseNode ->
                    org.junit.jupiter.params.provider.Arguments.of(
                        id, idx, pattern, caseNode["op"].asText(), caseNode,
                    )
                }
            }.toList().stream()
        }
    }
}
