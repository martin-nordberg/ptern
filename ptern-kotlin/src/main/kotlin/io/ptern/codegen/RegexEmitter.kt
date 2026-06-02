package io.ptern.codegen

import io.ptern.parser.ast.*

// ---------------------------------------------------------------------------
// Flags — returns Kotlin Set<RegexOption> (JVM has no v flag; i/m map directly)
// ---------------------------------------------------------------------------

internal fun determineFlags(ptern: ParsedPtern): Set<RegexOption> {
    val anns = ptern.annotations
    val caseInsensitive = anns.any { it.name == "case-insensitive" && it.value }
    val multiline = anns.any { it.name == "multiline" && it.value } ||
        hasLineBoundaryInDefs(ptern.definitions) ||
        hasLineBoundaryInExpr(ptern.body)
    return buildSet {
        if (caseInsensitive) add(RegexOption.IGNORE_CASE)
        if (multiline) add(RegexOption.MULTILINE)
    }
}

private fun hasLineBoundaryInDefs(defs: List<Definition>): Boolean =
    defs.any { hasLineBoundaryInExpr(it.body) }

private fun hasLineBoundaryInExpr(expr: Expression): Boolean =
    expr.alternatives.any { hasLineBoundaryInSeq(it) }

private fun hasLineBoundaryInSeq(seq: Sequence): Boolean =
    seq.items.any { hasLineBoundaryInExcl(it.inner.inner) }

private fun hasLineBoundaryInExcl(excl: Exclusion): Boolean =
    hasLineBoundaryInItem(excl.base)

private fun hasLineBoundaryInItem(item: RangeItem): Boolean {
    if (item is RangeItem.SingleAtom) {
        val atom = item.atom
        if (atom is Atom.PositionAssertion && (atom.name == "line-start" || atom.name == "line-end")) return true
        if (atom is Atom.Group) return hasLineBoundaryInExpr(atom.inner)
    }
    return false
}

// ---------------------------------------------------------------------------
// ignoreMatching flag
// ---------------------------------------------------------------------------

internal fun determineIgnoreMatching(annotations: List<PternAnnotation>): Boolean =
    annotations.any { it.name == "replacements-ignore-matching" && it.value }

// ---------------------------------------------------------------------------
// Duplicate capture name detection (for named-group suppression)
// ---------------------------------------------------------------------------

internal fun findDuplicateCaptureNames(expr: Expression): List<String> {
    val names = collectAllCaptureNamesExpr(expr)
    val seen = mutableListOf<String>()
    val dups = mutableListOf<String>()
    for (name in names) {
        if (seen.contains(name)) { if (!dups.contains(name)) dups.add(name) }
        else seen.add(name)
    }
    return dups
}

private fun collectAllCaptureNamesExpr(expr: Expression): List<String> =
    expr.alternatives.flatMap { collectAllCaptureNamesSeq(it) }

private fun collectAllCaptureNamesSeq(seq: Sequence): List<String> =
    seq.items.flatMap { collectAllCaptureNamesCap(it) }

private fun collectAllCaptureNamesCap(cap: Capture): List<String> =
    (if (cap.name != null) listOf(cap.name) else emptyList()) + collectAllCaptureNamesExcl(cap.inner.inner)

private fun collectAllCaptureNamesExcl(excl: Exclusion): List<String> =
    collectAllCaptureNamesItem(excl.base)

private fun collectAllCaptureNamesItem(item: RangeItem): List<String> =
    if (item is RangeItem.SingleAtom) collectAllCaptureNamesAtom(item.atom) else emptyList()

private fun collectAllCaptureNamesAtom(atom: Atom): List<String> =
    if (atom is Atom.Group) collectAllCaptureNamesExpr(atom.inner) else emptyList()

// ---------------------------------------------------------------------------
// Definition compilation (recursive, memoised)
// ---------------------------------------------------------------------------

internal fun compileDefinitions(
    defs: List<Definition>,
    classDefs: Map<String, String>,
): Map<String, String> {
    val defBodies = defs.associate { it.name to it.body }
    return defs.fold(emptyMap()) { compiled, def ->
        compileDefMemo(def.name, defBodies, compiled, classDefs)
    }
}

private fun compileDefMemo(
    name: String,
    defBodies: Map<String, Expression>,
    compiled: Map<String, String>,
    classDefs: Map<String, String>,
): Map<String, String> {
    if (compiled.containsKey(name)) return compiled
    val body = defBodies[name] ?: return compiled
    val deps = interpolationsInExpression(body)
    val compiled2 = deps.fold(compiled) { c, dep ->
        if (!defBodies.containsKey(dep)) c else compileDefMemo(dep, defBodies, c, classDefs)
    }
    val frag = compileExpression(body, compiled2, classDefs, emptyList())
    return compiled2 + (name to frag)
}

// ---------------------------------------------------------------------------
// Class-operand compilation for definitions used in `excluding` contexts
// ---------------------------------------------------------------------------

internal fun compileClassDefinitions(defs: List<Definition>): Map<String, String> {
    val defBodies = defs.associate { it.name to it.body }
    return defs.fold(emptyMap()) { classCompiled, def ->
        compileClassDefMemo(def.name, defBodies, classCompiled)
    }
}

private fun compileClassDefMemo(
    name: String,
    defBodies: Map<String, Expression>,
    classCompiled: Map<String, String>,
): Map<String, String> {
    if (classCompiled.containsKey(name)) return classCompiled
    val body = defBodies[name] ?: return classCompiled
    val deps = interpolationsInExpression(body)
    val classCompiled2 = deps.fold(classCompiled) { c, dep ->
        if (!defBodies.containsKey(dep)) c else compileClassDefMemo(dep, defBodies, c)
    }
    val classBody = exprAsClassBody(body, classCompiled2)
    if (classBody.isEmpty()) return classCompiled2
    return classCompiled2 + (name to "[$classBody]")
}

private fun exprAsClassBody(expr: Expression, classDefs: Map<String, String>): String {
    val parts = expr.alternatives.map { seqAsClassBodyExt(it, classDefs) }
    if (parts.any { it.isEmpty() }) return ""
    return parts.joinToString("")
}

private fun seqAsClassBodyExt(seq: Sequence, classDefs: Map<String, String>): String {
    if (seq.items.size != 1) return ""
    val cap = seq.items[0]
    if (cap.name != null || cap.inner.count != null) return ""
    if (cap.inner.inner.excluded != null) return ""
    return rangeItemAsClassBodyExt(cap.inner.inner.base, classDefs)
}

private fun rangeItemAsClassBodyExt(item: RangeItem, classDefs: Map<String, String>): String {
    if (item is RangeItem.SingleAtom) {
        val atom = item.atom
        if (atom is Atom.Literal) return rawToClassChar(atom.content)
        if (atom is Atom.CharClass) return charClassStandalone(atom.name)
        if (atom is Atom.Group) {
            return atom.inner.alternatives.joinToString("") { seqAsClassBodyExt(it, classDefs) }
        }
        if (atom is Atom.Interpolation) return classDefs[atom.name] ?: ""
        return ""
    }
    // charRange
    if (item is RangeItem.CharRange && item.from is Atom.Literal && item.to is Atom.Literal) {
        return "[${rawToClassChar(item.from.content)}-${rawToClassChar(item.to.content)}]"
    }
    return ""
}

// ---------------------------------------------------------------------------
// Expression → regex string (simple, no rep-info tracking)
// ---------------------------------------------------------------------------

internal fun compileExpression(
    expr: Expression,
    defs: Map<String, String>,
    classDefs: Map<String, String>,
    suppressed: List<String>,
): String {
    val seqs = expr.alternatives
    val mergeable = seqs.size >= 2 && seqs.all { isClassItem(it) }
    if (mergeable) return "[${seqs.joinToString("") { sequenceAsClassBody(it) }}]"
    return seqs.joinToString("|") { compileSequence(it, defs, classDefs, suppressed) }
}

private fun compileSequence(
    seq: Sequence,
    defs: Map<String, String>,
    classDefs: Map<String, String>,
    suppressed: List<String>,
): String = seq.items.joinToString("") { compileCapture(it, defs, classDefs, suppressed) }

private fun compileCapture(
    cap: Capture,
    defs: Map<String, String>,
    classDefs: Map<String, String>,
    suppressed: List<String>,
): String {
    val body = compileRepetition(cap.inner, defs, classDefs, suppressed)
    if (cap.name == null) return body
    return if (suppressed.contains(cap.name)) "(?:$body)" else "(?<${cap.name}>$body)"
}

private fun compileRepetition(
    rep: Repetition,
    defs: Map<String, String>,
    classDefs: Map<String, String>,
    suppressed: List<String>,
): String {
    val body = compileExclusion(rep.inner, defs, classDefs, suppressed)
    if (rep.count == null) return body
    return wrapIfNeeded(body) + compileQuantifier(rep.count)
}

internal fun compileExclusion(
    excl: Exclusion,
    defs: Map<String, String>,
    classDefs: Map<String, String>,
    suppressed: List<String>,
): String {
    if (excl.excluded == null) return compileRangeItem(excl.base, defs, classDefs, suppressed)
    val baseClass = rangeItemAsClassOperand(excl.base, defs, classDefs)
    val exclClass = rangeItemAsClassOperand(excl.excluded, defs, classDefs)
    return buildSetDifference(baseClass, exclClass)
}

private fun compileRangeItem(
    item: RangeItem,
    defs: Map<String, String>,
    classDefs: Map<String, String>,
    suppressed: List<String>,
): String {
    if (item is RangeItem.SingleAtom) return compileAtom(item.atom, defs, classDefs, suppressed)
    if (item is RangeItem.CharRange && item.from is Atom.Literal && item.to is Atom.Literal) {
        return "[${rawToClassChar(item.from.content)}-${rawToClassChar(item.to.content)}]"
    }
    return "(?!)"
}

private fun compileAtom(
    atom: Atom,
    defs: Map<String, String>,
    classDefs: Map<String, String>,
    suppressed: List<String>,
): String = when (atom) {
    is Atom.Literal -> rawToRegex(atom.content)
    is Atom.CharClass -> charClassStandalone(atom.name)
    is Atom.Interpolation -> {
        val pattern = defs[atom.name]
        if (pattern != null) "(?:$pattern)" else "\\k<${atom.name}>"
    }
    is Atom.Group -> "(?:${compileExpression(atom.inner, defs, classDefs, suppressed)})"
    is Atom.PositionAssertion -> compilePositionAssertion(atom.name)
}

// ---------------------------------------------------------------------------
// Range items as class operands (for excluding)
// ---------------------------------------------------------------------------

private fun rangeItemAsClassOperand(
    item: RangeItem,
    defs: Map<String, String>,
    classDefs: Map<String, String>,
): String {
    if (item is RangeItem.SingleAtom) {
        val atom = item.atom
        if (atom is Atom.CharClass) return charClassStandalone(atom.name)
        if (atom is Atom.Literal) return "[${rawToClassChar(atom.content)}]"
        if (atom is Atom.Group) {
            return "[${atom.inner.alternatives.joinToString("") { sequenceAsClassBody(it) }}]"
        }
        if (atom is Atom.Interpolation) return classDefs[atom.name] ?: "[(?!)]"
        return "[${compileAtom(atom, defs, classDefs, emptyList())}]"
    }
    if (item is RangeItem.CharRange && item.from is Atom.Literal && item.to is Atom.Literal) {
        return "[${rawToClassChar(item.from.content)}-${rawToClassChar(item.to.content)}]"
    }
    return "[(?!)]"
}

// JVM set-difference: [A--B] → [A&&[^B]] by stripping outer [] from exclClass
private fun buildSetDifference(baseClass: String, exclClass: String): String {
    val exclContent = if (exclClass.startsWith("[") && exclClass.endsWith("]"))
        exclClass.substring(1, exclClass.length - 1) else exclClass
    return "[$baseClass&&[^$exclContent]]"
}

// ---------------------------------------------------------------------------
// Character-class merging for alternations
// ---------------------------------------------------------------------------

private fun isClassItem(seq: Sequence): Boolean {
    if (seq.items.size != 1) return false
    val cap = seq.items[0]
    if (cap.name != null) return false
    if (cap.inner.count != null) return false
    return isClassRangeItem(cap.inner.inner.base)
}

private fun isClassRangeItem(item: RangeItem): Boolean {
    if (item is RangeItem.SingleAtom) {
        val atom = item.atom
        if (atom is Atom.Literal) return decodedLength(atom.content) == 1
        if (atom is Atom.CharClass) return true
        return false
    }
    if (item is RangeItem.CharRange) return item.from is Atom.Literal && item.to is Atom.Literal
    return false
}

private fun sequenceAsClassBody(seq: Sequence): String {
    val cap = seq.items[0]
    val excl = cap.inner.inner
    if (excl.excluded == null) return rangeItemAsClassBody(excl.base)
    val baseOp = rangeItemAsClassOperand(excl.base, emptyMap(), emptyMap())
    val exclOp = rangeItemAsClassOperand(excl.excluded, emptyMap(), emptyMap())
    return buildSetDifference(baseOp, exclOp)
}

private fun rangeItemAsClassBody(item: RangeItem): String {
    if (item is RangeItem.SingleAtom) {
        val atom = item.atom
        if (atom is Atom.Literal) return rawToClassChar(atom.content)
        if (atom is Atom.CharClass) return charClassStandalone(atom.name)
        return ""
    }
    if (item is RangeItem.CharRange && item.from is Atom.Literal && item.to is Atom.Literal) {
        return "[${rawToClassChar(item.from.content)}-${rawToClassChar(item.to.content)}]"
    }
    return ""
}

// ---------------------------------------------------------------------------
// Position assertions
// ---------------------------------------------------------------------------

private fun compilePositionAssertion(name: String): String = when (name) {
    "word-start", "word-end" -> "\\b"
    "line-start" -> "^"
    "line-end" -> "$"
    else -> "(?!)"
}

// ---------------------------------------------------------------------------
// Quantifiers
// ---------------------------------------------------------------------------

private fun compileQuantifier(rc: RepCount): String {
    val lazy = if (rc.lazy) "?" else ""
    return compileQuantifierBase(rc) + lazy
}

private fun compileQuantifierBase(rc: RepCount): String {
    val min = rc.min
    val max = rc.max
    if (min == 0 && max is RepUpper.Exact && max.value == 1) return "?"
    if (min == 0 && max is RepUpper.Unbounded) return "*"
    if (min == 1 && max is RepUpper.Unbounded) return "+"
    if (max is RepUpper.Unbounded) return "{$min,}"
    if (max is RepUpper.None) return "{$min}"
    if (max is RepUpper.Exact) return "{$min,${max.value}}"
    return "{$min}"
}

// ---------------------------------------------------------------------------
// Character classes
// ---------------------------------------------------------------------------

internal fun charClassStandalone(name: String): String = when (name) {
    "Any" -> "[\\s\\S]"
    "Digit" -> "[0-9]"
    "Alpha" -> "[A-Za-z]"
    "Alnum" -> "[A-Za-z0-9]"
    "Lower" -> "[a-z]"
    "Upper" -> "[A-Z]"
    "Word" -> "[A-Za-z0-9_]"
    "Space" -> "[ \\t\\n\\r\\f]"
    "Blank" -> "[ \\t]"
    "Xdigit" -> "[0-9A-Fa-f]"
    "Ascii" -> "[\\x00-\\x7F]"
    "Cntrl" -> "[\\x00-\\x1F\\x7F]"
    "Graph" -> "[\\x21-\\x7E]"
    "Print" -> "[\\x20-\\x7E]"
    "Punct" -> "[\\x21-\\x2F\\x3A-\\x40\\x5B-\\x60\\x7B-\\x7E]"
    "L", "Letter" -> "\\p{L}"
    "Ll", "LowercaseLetter" -> "\\p{Ll}"
    "Lu", "UppercaseLetter" -> "\\p{Lu}"
    "Lm", "ModifierLetter" -> "\\p{Lm}"
    "Lo", "OtherLetter" -> "\\p{Lo}"
    "Lt", "TitlecaseLetter" -> "\\p{Lt}"
    "M", "Mark" -> "\\p{M}"
    "Mc", "SpacingMark" -> "\\p{Mc}"
    "Me", "EnclosingMark" -> "\\p{Me}"
    "Mn", "NonspacingMark" -> "\\p{Mn}"
    "N", "Number" -> "\\p{N}"
    "Nd", "DecimalNumber" -> "\\p{Nd}"
    "Nl", "LetterNumber" -> "\\p{Nl}"
    "No", "OtherNumber" -> "\\p{No}"
    "P", "Punctuation" -> "\\p{P}"
    "Pc", "ConnectorPunctuation" -> "\\p{Pc}"
    "Pd", "DashPunctuation" -> "\\p{Pd}"
    "Pe", "ClosePunctuation" -> "\\p{Pe}"
    "Pf", "FinalPunctuation" -> "\\p{Pf}"
    "Pi", "InitialPunctuation" -> "\\p{Pi}"
    "Po", "OtherPunctuation" -> "\\p{Po}"
    "Ps", "OpenPunctuation" -> "\\p{Ps}"
    "S", "Symbol" -> "\\p{S}"
    "Sc", "CurrencySymbol" -> "\\p{Sc}"
    "Sk", "ModifierSymbol" -> "\\p{Sk}"
    "Sm", "MathSymbol" -> "\\p{Sm}"
    "So", "OtherSymbol" -> "\\p{So}"
    "Z", "Separator" -> "\\p{Z}"
    "Zl", "LineSeparator" -> "\\p{Zl}"
    "Zp", "ParagraphSeparator" -> "\\p{Zp}"
    "Zs", "SpaceSeparator" -> "\\p{Zs}"
    "C", "Other" -> "\\p{C}"
    "Cc", "Control" -> "\\p{Cc}"
    "Cf", "Format" -> "\\p{Cf}"
    "Cn", "Unassigned" -> "\\p{Cn}"
    "Co", "PrivateUse" -> "\\p{Co}"
    "Cs", "Surrogate" -> "\\p{Cs}"
    else -> "(?!)"
}

// ---------------------------------------------------------------------------
// Raw literal content → regex string
// ---------------------------------------------------------------------------

private fun rawToRegex(content: String): String = processRaw(content, inCc = false)
private fun rawToClassChar(content: String): String = processRaw(content, inCc = true)

private fun processRaw(s: String, inCc: Boolean): String {
    val result = StringBuilder()
    var i = 0
    while (i < s.length) {
        if (s[i] == '\\') {
            i++
            if (i >= s.length) break
            val c = s[i]
            val fragment = when (c) {
                'n' -> { i++; "\\n" }
                't' -> { i++; "\\t" }
                'r' -> { i++; "\\r" }
                'a' -> { i++; "\\x07" }
                'f' -> { i++; "\\f" }
                'v' -> { i++; "\\x0B" }
                '\\' -> { i++; "\\\\" }
                '\'' -> { i++; "'" }
                '"' -> { i++; "\"" }
                'u' -> {
                    val hex = s.substring(i + 1, minOf(i + 5, s.length))
                    i += 5
                    "\\u$hex"
                }
                else -> { i++; c.toString() }
            }
            result.append(fragment)
        } else {
            val cp = s.codePointAt(i)
            val char = String(Character.toChars(cp))
            result.append(if (inCc) classEscape(char) else regexEscape(char))
            i += Character.charCount(cp)
        }
    }
    return result.toString()
}

private fun regexEscape(c: String): String =
    if ("\\.^$*+?()[]{|}".contains(c)) "\\$c" else c

private fun classEscape(c: String): String =
    if ("\\]^-()[{}|/&".contains(c)) "\\$c" else c

// ---------------------------------------------------------------------------
// Wrapping helpers
// ---------------------------------------------------------------------------

private fun wrapIfNeeded(s: String): String = if (isRegexAtom(s)) s else "(?:$s)"

private fun isRegexAtom(s: String): Boolean {
    val len = s.length
    if (len == 0 || len == 1) return true
    return s.startsWith("[") || s.startsWith("(?") || s.startsWith("\\")
}

// ---------------------------------------------------------------------------
// Interpolation name collector (for definition dependency ordering)
// ---------------------------------------------------------------------------

private fun interpolationsInExpression(expr: Expression): List<String> =
    expr.alternatives.flatMap { interpolationsInSequence(it) }

private fun interpolationsInSequence(seq: Sequence): List<String> =
    seq.items.flatMap { interpolationsInCapture(it) }

private fun interpolationsInCapture(cap: Capture): List<String> =
    interpolationsInExclusion(cap.inner.inner)

private fun interpolationsInExclusion(excl: Exclusion): List<String> =
    interpolationsInRangeItem(excl.base) +
        (excl.excluded?.let { interpolationsInRangeItem(it) } ?: emptyList())

private fun interpolationsInRangeItem(item: RangeItem): List<String> =
    if (item is RangeItem.SingleAtom) interpolationsInAtom(item.atom) else emptyList()

private fun interpolationsInAtom(atom: Atom): List<String> = when (atom) {
    is Atom.Interpolation -> listOf(atom.name)
    is Atom.Group -> interpolationsInExpression(atom.inner)
    else -> emptyList()
}

// ---------------------------------------------------------------------------
// Capture validator collection
// ---------------------------------------------------------------------------

internal fun collectCaptureValidators(
    expr: Expression,
    defs: Map<String, String>,
    classDefs: Map<String, String>,
): List<Pair<String, String>> =
    expr.alternatives.flatMap { collectValidatorsInSequence(it, defs, classDefs) }

private fun collectValidatorsInSequence(
    seq: Sequence,
    defs: Map<String, String>,
    classDefs: Map<String, String>,
): List<Pair<String, String>> =
    seq.items.flatMap { collectValidatorsInCapture(it, defs, classDefs) }

private fun collectValidatorsInCapture(
    cap: Capture,
    defs: Map<String, String>,
    classDefs: Map<String, String>,
): List<Pair<String, String>> {
    val body = compileRepetition(cap.inner, defs, classDefs, emptyList())
    val own: List<Pair<String, String>> = if (cap.name != null) listOf(cap.name to body) else emptyList()
    return own + collectValidatorsInExclusion(cap.inner.inner, defs, classDefs)
}

private fun collectValidatorsInExclusion(
    excl: Exclusion,
    defs: Map<String, String>,
    classDefs: Map<String, String>,
): List<Pair<String, String>> =
    collectValidatorsInRangeItem(excl.base, defs, classDefs)

private fun collectValidatorsInRangeItem(
    item: RangeItem,
    defs: Map<String, String>,
    classDefs: Map<String, String>,
): List<Pair<String, String>> =
    if (item is RangeItem.SingleAtom) collectValidatorsInAtom(item.atom, defs, classDefs) else emptyList()

private fun collectValidatorsInAtom(
    atom: Atom,
    defs: Map<String, String>,
    classDefs: Map<String, String>,
): List<Pair<String, String>> =
    if (atom is Atom.Group) collectCaptureValidators(atom.inner, defs, classDefs) else emptyList()

// ---------------------------------------------------------------------------
// RepetitionInfo and emit-with-rep-info variants
//
// Uses a private mutable context class to avoid threading counters through
// every function while keeping the logic identical to the TypeScript port.
// ---------------------------------------------------------------------------

internal data class EmitWithRepResult(
    val source: String,
    val repInfo: List<RepetitionInfo>,
)

internal fun compileExpressionWithRepInfo(
    expr: Expression,
    defs: Map<String, String>,
    classDefs: Map<String, String>,
): EmitWithRepResult {
    val ctx = RepEmitCtx(defs, classDefs)
    val source = ctx.emitExpression(expr, emptyList())
    return EmitWithRepResult(source, ctx.repInfos)
}

private class RepEmitCtx(
    val defs: Map<String, String>,
    val classDefs: Map<String, String>,
) {
    var counter = 0
    val repInfos = mutableListOf<RepetitionInfo>()

    fun emitExpression(expr: Expression, seen: List<String>): String {
        val seqs = expr.alternatives
        val mergeable = seqs.size >= 2 && seqs.all { isClassItem(it) }
        if (mergeable) return "[${seqs.joinToString("") { sequenceAsClassBody(it) }}]"
        val parts = mutableListOf<String>()
        var curSeen = seen
        for (seq in seqs) {
            val (s, newSeen) = emitSequence(seq, curSeen)
            parts.add(s)
            curSeen = newSeen
        }
        return parts.joinToString("|")
    }

    private fun emitSequence(seq: Sequence, seen: List<String>): Pair<String, List<String>> {
        val parts = mutableListOf<String>()
        var curSeen = seen
        for (cap in seq.items) {
            val (s, newSeen) = emitCapture(cap, curSeen)
            parts.add(s)
            curSeen = newSeen
        }
        return parts.joinToString("") to curSeen
    }

    private fun emitCapture(cap: Capture, seen: List<String>): Pair<String, List<String>> {
        val (body, newSeen) = emitRepetition(cap.inner, seen)
        if (cap.name == null) return body to newSeen
        return if (newSeen.contains(cap.name)) {
            "(?:$body)" to newSeen
        } else {
            "(?<${cap.name}>$body)" to listOf(cap.name) + newSeen
        }
    }

    private fun emitRepetition(rep: Repetition, seen: List<String>): Pair<String, List<String>> {
        if (rep.count == null) return emitExclusion(rep.inner, seen)
        val rc = rep.count
        val innerCaps = collectAllCaptureNamesExcl(rep.inner)
        if (innerCaps.isEmpty()) {
            val (body, newSeen) = emitExclusion(rep.inner, seen)
            return wrapIfNeeded(body) + compileQuantifier(rc) to newSeen
        }
        // Named captures in body — wrap in repN synthetic group (JVM: no underscores allowed)
        val repName = "rep$counter"
        counter++
        val (mainBody, newSeen) = emitExclusion(rep.inner, seen)
        val subSource = compileExclusion(rep.inner, defs, classDefs, emptyList())
        val main = "(?<$repName>${wrapIfNeeded(mainBody)}${compileQuantifier(rc)})"
        repInfos.add(RepetitionInfo(repName, subSource, innerCaps))
        return main to newSeen
    }

    private fun emitExclusion(excl: Exclusion, seen: List<String>): Pair<String, List<String>> {
        if (excl.excluded == null) return emitRangeItem(excl.base, seen)
        val baseClass = rangeItemAsClassOperand(excl.base, defs, classDefs)
        val exclClass = rangeItemAsClassOperand(excl.excluded, defs, classDefs)
        return buildSetDifference(baseClass, exclClass) to seen
    }

    private fun emitRangeItem(item: RangeItem, seen: List<String>): Pair<String, List<String>> {
        if (item is RangeItem.SingleAtom) return emitAtom(item.atom, seen)
        if (item is RangeItem.CharRange && item.from is Atom.Literal && item.to is Atom.Literal) {
            return "[${rawToClassChar(item.from.content)}-${rawToClassChar(item.to.content)}]" to seen
        }
        return "(?!)" to seen
    }

    private fun emitAtom(atom: Atom, seen: List<String>): Pair<String, List<String>> = when (atom) {
        is Atom.Literal -> rawToRegex(atom.content) to seen
        is Atom.CharClass -> charClassStandalone(atom.name) to seen
        is Atom.Interpolation -> {
            val pattern = defs[atom.name]
            val src = if (pattern != null) "(?:$pattern)" else "\\k<${atom.name}>"
            src to seen
        }
        is Atom.Group -> {
            val inner = emitExpression(atom.inner, seen)
            "(?:$inner)" to seen
        }
        is Atom.PositionAssertion -> compilePositionAssertion(atom.name) to seen
    }
}

// ---------------------------------------------------------------------------
// Decoded length (shared with Validator but duplicated to avoid cross-package dep)
// ---------------------------------------------------------------------------

private fun decodedLength(content: String): Int {
    var count = 0
    var i = 0
    while (i < content.length) {
        if (content[i] == '\\') {
            i++
            if (i >= content.length) { count++; break }
            val c = content[i]
            if (c == 'u') i += 5 else i++
            count++
        } else {
            val cp = content.codePointAt(i)
            i += Character.charCount(cp)
            count++
        }
    }
    return count
}
