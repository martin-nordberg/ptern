package io.ptern.runtime

import io.ptern.PternReplacementException
import io.ptern.ReplacementError
import io.ptern.ReplacementValue
import io.ptern.codegen.RepetitionInfo
import java.util.regex.Matcher
import java.util.regex.Pattern

internal class Replacer(
    private val captureNames: Set<String>,
    private val repetitionInfo: List<RepetitionInfo>,
    private val jvmFlags: Int,
) {
    fun applyToMatch(
        input: String,
        m: Matcher,
        replacements: Map<String, ReplacementValue>,
    ): String {
        val spanMap = collectSpans(input, m)
        val patches = buildPatches(spanMap, replacements)
        return applyPatches(input, patches)
    }

    fun applyToAllMatches(
        input: String,
        matcher: Matcher,
        replacements: Map<String, ReplacementValue>,
    ): String {
        val allPatches = mutableListOf<Triple<Int, Int, String>>()
        while (matcher.find()) {
            val spanMap = collectSpans(input, matcher)
            allPatches.addAll(buildPatches(spanMap, replacements))
        }
        return applyPatches(input, allPatches)
    }

    private fun collectSpans(input: String, m: Matcher): Map<String, MutableList<Pair<Int, Int>>> {
        val spanMap = mutableMapOf<String, MutableList<Pair<Int, Int>>>()

        // Direct captures from main matcher
        for (name in captureNames) {
            val s = try { m.start(name) } catch (_: IllegalArgumentException) { -1 }
            if (s >= 0) spanMap.getOrPut(name) { mutableListOf() }.add(s to m.end(name))
        }

        // Repetition captures from sub-matchers
        for (repInfo in repetitionInfo) {
            val repStart = try { m.start(repInfo.groupName) } catch (_: IllegalArgumentException) { -1 }
            if (repStart < 0) continue
            val repEnd = m.end(repInfo.groupName)
            val subPattern = Pattern.compile(repInfo.subSource, jvmFlags)
            val subMatcher = subPattern.matcher(input)
            subMatcher.region(repStart, repEnd)
            while (subMatcher.find()) {
                for (capName in repInfo.captures) {
                    val s = try { subMatcher.start(capName) } catch (_: IllegalArgumentException) { -1 }
                    if (s >= 0) {
                        spanMap.getOrPut(capName) { mutableListOf() }.add(s to subMatcher.end(capName))
                    }
                }
            }
        }

        return spanMap
    }

    private fun buildPatches(
        spanMap: Map<String, List<Pair<Int, Int>>>,
        replacements: Map<String, ReplacementValue>,
    ): List<Triple<Int, Int, String>> {
        val patches = mutableListOf<Triple<Int, Int, String>>()
        for ((name, replValue) in replacements) {
            val spans = spanMap[name] ?: continue
            when (replValue) {
                is ReplacementValue.Scalar -> {
                    for ((s, e) in spans) patches.add(Triple(s, e, replValue.value))
                }
                is ReplacementValue.Array -> {
                    if (replValue.values.size != spans.size) {
                        throw PternReplacementException(
                            ReplacementError.ArrayLengthMismatch(name, spans.size, replValue.values.size),
                            "Array replacement for '$name': expected ${spans.size} values, got ${replValue.values.size}",
                        )
                    }
                    for (i in spans.indices) {
                        patches.add(Triple(spans[i].first, spans[i].second, replValue.values[i]))
                    }
                }
            }
        }
        return patches
    }

    private fun applyPatches(input: String, patches: List<Triple<Int, Int, String>>): String {
        if (patches.isEmpty()) return input
        val sorted = patches.sortedByDescending { it.first }
        val sb = StringBuilder(input)
        for ((s, e, repl) in sorted) sb.replace(s, e, repl)
        return sb.toString()
    }
}
