package io.ptern

import io.ptern.codegen.RepetitionInfo
import io.ptern.codegen.SubstitutionPlan
import io.ptern.codegen.compile
import io.ptern.lexer.LexException
import io.ptern.parser.ast.ParseException
import io.ptern.runtime.Replacer
import io.ptern.runtime.Substituter
import io.ptern.semantic.Resolver
import io.ptern.semantic.SemanticError
import io.ptern.semantic.Validator
import io.ptern.semantic.checkBacktracking
import io.ptern.semantic.computePternBounds
import java.util.regex.Matcher
import java.util.regex.Pattern

private val NAMED_GROUP_RE = Regex("""\(\?<([A-Za-z][A-Za-z0-9]*)>""")

class Ptern private constructor(
    val minLength: Int,
    val maxLength: Int?,
    val captureNames: Set<String>,
    private val allOfPattern: Pattern,
    private val startOfPattern: Pattern,
    private val endOfPattern: Pattern,
    private val scanPattern: Pattern,
    private val jvmFlags: Int,
    private val repetitionInfo: List<RepetitionInfo>,
    private val syntheticGroupNames: Set<String>,
    private val substitutionPlan: SubstitutionPlan?,
    private val ignoreMatching: Boolean,
    private val ignoreSubstitutionMatching: Boolean,
    private val captureValidators: List<Pair<String, String>>,
) {
    companion object {
        @JvmStatic
        fun compile(pattern: String): Ptern {
            // 1. Lex
            val tokens = try {
                io.ptern.lexer.Lexer.lex(pattern)
            } catch (e: LexException) {
                throw PternCompileException(
                    CompileError.LexError(e.message ?: "Lex error"),
                    "Lex error: ${e.message}",
                )
            }

            // 2. Parse
            val parsed = try {
                io.ptern.parser.Parser.parse(tokens)
            } catch (e: ParseException) {
                throw PternCompileException(
                    CompileError.ParseError(e.message ?: "Parse error"),
                    "Parse error: ${e.message}",
                )
            }

            // 3. Validate
            val validatorErrors = Validator.validate(parsed)
            if (validatorErrors.isNotEmpty()) {
                throw PternCompileException(
                    CompileError.SemanticErrors(validatorErrors.map { it.toString() }),
                    "Semantic errors: ${validatorErrors.joinToString("; ")}",
                )
            }

            // 4. Resolve (filter DuplicateCapture — handled by regex emitter)
            val resolverErrors = Resolver.resolve(parsed)
                .filterNot { it is SemanticError.DuplicateCapture }
            if (resolverErrors.isNotEmpty()) {
                throw PternCompileException(
                    CompileError.SemanticErrors(resolverErrors.map { it.toString() }),
                    "Semantic errors: ${resolverErrors.joinToString("; ")}",
                )
            }

            // 5. Backtracking check
            val btErrors = checkBacktracking(parsed)
            if (btErrors.isNotEmpty()) {
                throw PternCompileException(
                    CompileError.SemanticErrors(btErrors.map { it.toString() }),
                    "Backtracking errors: ${btErrors.joinToString("; ")}",
                )
            }

            // 6. Codegen
            val compiled = compile(parsed)

            // 7. Bounds
            val bounds = computePternBounds(parsed)

            // Build JVM patterns
            val jvmFlags = toJvmFlags(compiled.flags)
            val src = compiled.source
            val allOf = Pattern.compile("""\A(?:$src)\z""", jvmFlags)
            val startOf = Pattern.compile("""\A(?:$src)""", jvmFlags)
            val endOf = Pattern.compile("""(?:$src)\z""", jvmFlags)
            val scan = Pattern.compile("""(?:$src)""", jvmFlags)

            val captureNames = extractCaptureNames(src, compiled.syntheticGroupNames)

            return Ptern(
                minLength = bounds.min,
                maxLength = bounds.max,
                captureNames = captureNames,
                allOfPattern = allOf,
                startOfPattern = startOf,
                endOfPattern = endOf,
                scanPattern = scan,
                jvmFlags = jvmFlags,
                repetitionInfo = compiled.repetitionInfo,
                syntheticGroupNames = compiled.syntheticGroupNames,
                substitutionPlan = compiled.substitutionPlan,
                ignoreMatching = compiled.ignoreMatching,
                ignoreSubstitutionMatching = compiled.ignoreSubstitutionMatching,
                captureValidators = compiled.captureValidators,
            )
        }

        private fun toJvmFlags(options: Set<RegexOption>): Int {
            var f = 0
            if (RegexOption.IGNORE_CASE in options) f = f or Pattern.CASE_INSENSITIVE
            if (RegexOption.MULTILINE in options) f = f or Pattern.MULTILINE
            return f
        }

        private fun extractCaptureNames(source: String, syntheticNames: Set<String>): Set<String> =
            NAMED_GROUP_RE.findAll(source)
                .map { it.groupValues[1] }
                .filterNot { it in syntheticNames }
                .toSet()
    }

    // -------------------------------------------------------------------------
    // Boolean match operations
    // -------------------------------------------------------------------------

    fun matchesAllOf(input: String): Boolean = allOfPattern.matcher(input).find()

    fun matchesStartOf(input: String): Boolean = startOfPattern.matcher(input).find()

    fun matchesEndOf(input: String): Boolean = endOfPattern.matcher(input).find()

    fun matchesIn(input: String): Boolean = scanPattern.matcher(input).find()

    // -------------------------------------------------------------------------
    // MatchOccurrence operations
    // -------------------------------------------------------------------------

    fun matchAllOf(input: String): MatchOccurrence? {
        val m = allOfPattern.matcher(input)
        return if (m.find()) buildOccurrence(m) else null
    }

    fun matchStartOf(input: String): MatchOccurrence? {
        val m = startOfPattern.matcher(input)
        return if (m.find()) buildOccurrence(m) else null
    }

    fun matchEndOf(input: String): MatchOccurrence? {
        val m = endOfPattern.matcher(input)
        return if (m.find()) buildOccurrence(m) else null
    }

    fun matchFirstIn(input: String): MatchOccurrence? {
        val m = scanPattern.matcher(input)
        return if (m.find()) buildOccurrence(m) else null
    }

    fun matchNextIn(input: String, startIndex: Int): MatchOccurrence? {
        val m = scanPattern.matcher(input)
        return if (m.find(startIndex)) buildOccurrence(m) else null
    }

    fun matchAllIn(input: String): List<MatchOccurrence> {
        val m = scanPattern.matcher(input)
        val results = mutableListOf<MatchOccurrence>()
        while (m.find()) results.add(buildOccurrence(m))
        return results
    }

    // -------------------------------------------------------------------------
    // Replace operations
    // -------------------------------------------------------------------------

    fun replaceAllOf(input: String, replacements: Map<String, ReplacementValue>): String =
        replaceSingle(input, allOfPattern.matcher(input), replacements)

    fun replaceStartOf(input: String, replacements: Map<String, ReplacementValue>): String =
        replaceSingle(input, startOfPattern.matcher(input), replacements)

    fun replaceEndOf(input: String, replacements: Map<String, ReplacementValue>): String =
        replaceSingle(input, endOfPattern.matcher(input), replacements)

    fun replaceFirstIn(input: String, replacements: Map<String, ReplacementValue>): String =
        replaceSingle(input, scanPattern.matcher(input), replacements)

    fun replaceNextIn(input: String, startIndex: Int, replacements: Map<String, ReplacementValue>): String {
        val m = scanPattern.matcher(input)
        if (!m.find(startIndex)) return input
        return replacer().applyToMatch(input, m, replacements)
    }

    fun replaceAllIn(input: String, replacements: Map<String, ReplacementValue>): String =
        replacer().applyToAllMatches(input, scanPattern.matcher(input), replacements)

    // -------------------------------------------------------------------------
    // Substitute
    // -------------------------------------------------------------------------

    fun substitute(captures: Map<String, ReplacementValue>): String {
        val plan = substitutionPlan ?: throw PternSubstitutionException(
            SubstitutionError.NotSubstitutable,
            "Pattern is not substitutable (missing !substitutable = true annotation)",
        )
        return Substituter(captureValidators, ignoreSubstitutionMatching).evaluate(plan, captures)
    }

    // -------------------------------------------------------------------------
    // Helpers
    // -------------------------------------------------------------------------

    private fun buildOccurrence(m: Matcher): MatchOccurrence {
        val captures = mutableMapOf<String, String>()
        for (name in captureNames) {
            val v = try { m.group(name) } catch (_: IllegalArgumentException) { null }
            if (v != null) captures[name] = v
        }
        return MatchOccurrence(m.start(), m.end() - m.start(), captures)
    }

    private fun replacer() = Replacer(captureNames, repetitionInfo, jvmFlags)

    private fun replaceSingle(input: String, m: Matcher, replacements: Map<String, ReplacementValue>): String {
        if (!m.find()) return input
        return replacer().applyToMatch(input, m, replacements)
    }
}
