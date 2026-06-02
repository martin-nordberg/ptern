package io.ptern.semantic

import io.ptern.parser.ast.*

// ---------------------------------------------------------------------------
// Public entry point
// ---------------------------------------------------------------------------

internal fun checkBacktracking(ptern: ParsedPtern): List<SemanticError> {
    if (ptern.annotations.any { it.name == "allow-backtracking" && it.value }) return emptyList()
    val defs = buildDefs(ptern.definitions) + buildCaptureExprs(ptern.body)
    return checkExpression(ptern.body, defs)
}

// ---------------------------------------------------------------------------
// CharSet — conservative character-set for first/last analysis
// ---------------------------------------------------------------------------

private sealed class CharSet {
    object Empty : CharSet()
    object Any : CharSet()
    data class Literal(val char: String) : CharSet()
    data class Named(val name: String) : CharSet()
    data class Union(val sets: List<CharSet>) : CharSet()
    data class Excl(val base: CharSet, val excl: CharSet) : CharSet()
}

private val EMPTY_SET: CharSet = CharSet.Empty
private val ANY_CHAR: CharSet = CharSet.Any

private fun unionSet(a: CharSet, b: CharSet): CharSet {
    if (a is CharSet.Empty) return b
    if (b is CharSet.Empty) return a
    if (a is CharSet.Union && b is CharSet.Union) return CharSet.Union(a.sets + b.sets)
    if (a is CharSet.Union) return CharSet.Union(a.sets + b)
    if (b is CharSet.Union) return CharSet.Union(listOf(a) + b.sets)
    return CharSet.Union(listOf(a, b))
}

private fun intersects(a: CharSet, b: CharSet): Boolean {
    if (a is CharSet.Empty || b is CharSet.Empty) return false
    if (a is CharSet.Any || b is CharSet.Any) return true
    if (a is CharSet.Excl) return intersects(a.base, b) && !isSubset(b, a.excl)
    if (b is CharSet.Excl) return intersects(a, b.base) && !isSubset(a, b.excl)
    if (a is CharSet.Union) return a.sets.any { intersects(it, b) }
    if (b is CharSet.Union) return b.sets.any { intersects(a, it) }
    if (a is CharSet.Literal && b is CharSet.Literal) return a.char == b.char
    if (a is CharSet.Named && b is CharSet.Named) return namedClassesIntersect(a.name, b.name)
    if (a is CharSet.Named && b is CharSet.Literal) return charInNamedClass(b.char, a.name)
    if (a is CharSet.Literal && b is CharSet.Named) return charInNamedClass(a.char, b.name)
    return false
}

private fun isSubset(other: CharSet, excl: CharSet): Boolean {
    if (other is CharSet.Literal && excl is CharSet.Literal) return other.char == excl.char
    if (other is CharSet.Literal && excl is CharSet.Named) return charInNamedClass(other.char, excl.name)
    if (other is CharSet.Named && excl is CharSet.Named) return other.name == excl.name
    return false
}

private val DISJOINT_PAIRS = listOf(
    "Alpha" to "Digit", "L" to "Digit", "Alpha" to "N", "Upper" to "Digit",
    "Lower" to "Digit", "Upper" to "Lower", "L" to "N", "Upper" to "N",
    "Lower" to "N", "Upper" to "Space", "Lower" to "Space", "Alpha" to "Space",
    "L" to "Space", "N" to "Space", "Digit" to "Space", "Alnum" to "Space",
)

private fun namedClassesIntersect(a: String, b: String): Boolean {
    if (a == b) return true
    return !DISJOINT_PAIRS.any { (x, y) -> (x == a && y == b) || (x == b && y == a) }
}

private fun charInNamedClass(c: String, className: String): Boolean = when (className) {
    "Any" -> true
    "Digit" -> "0123456789".contains(c)
    "N" -> "0123456789".contains(c) ||
        !"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!\"#\$%&'()*+,-./:;<=>?@[\\]^_`{|}~ \t\n\r".contains(c)
    "Upper" -> "ABCDEFGHIJKLMNOPQRSTUVWXYZ".contains(c)
    "Lower" -> "abcdefghijklmnopqrstuvwxyz".contains(c)
    "Alpha", "L" -> "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz".contains(c) ||
        !"0123456789!\"#\$%&'()*+,-./:;<=>?@[\\]^_`{|}~ \t\n\r".contains(c)
    "Alnum" -> "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789".contains(c)
    "Xdigit" -> "0123456789ABCDEFabcdef".contains(c)
    "Space" -> c == " " || c == "\t" || c == "\n" || c == "\r"
    else -> true
}

// ---------------------------------------------------------------------------
// nullable / firstCharset / lastCharset
// ---------------------------------------------------------------------------

private fun nullableExpr(expr: Expression, defs: Map<String, Expression>): Boolean =
    expr.alternatives.any { nullableSeq(it, defs) }

private fun nullableSeq(seq: Sequence, defs: Map<String, Expression>): Boolean =
    seq.items.all { nullableCap(it, defs) }

private fun nullableCap(cap: Capture, defs: Map<String, Expression>): Boolean =
    nullableRep(cap.inner, defs)

private fun nullableRep(rep: Repetition, defs: Map<String, Expression>): Boolean {
    if (rep.count == null) return nullableExcl(rep.inner, defs)
    return rep.count.min == 0
}

private fun nullableExcl(excl: Exclusion, defs: Map<String, Expression>): Boolean {
    if (excl.base is RangeItem.SingleAtom) return nullableAtom(excl.base.atom, defs)
    return false
}

private fun nullableAtom(atom: Atom, defs: Map<String, Expression>): Boolean = when (atom) {
    is Atom.PositionAssertion -> true
    is Atom.Group -> nullableExpr(atom.inner, defs)
    is Atom.Interpolation -> defs[atom.name]?.let { nullableExpr(it, defs) } ?: false
    is Atom.Literal, is Atom.CharClass -> false
}

private fun firstCharsetExpr(expr: Expression, defs: Map<String, Expression>): CharSet =
    expr.alternatives.fold(EMPTY_SET) { acc, seq -> unionSet(acc, firstCharsetSeq(seq, defs)) }

private fun firstCharsetSeq(seq: Sequence, defs: Map<String, Expression>): CharSet =
    firstCharsetItems(seq.items, defs)

private fun firstCharsetItems(items: List<Capture>, defs: Map<String, Expression>): CharSet {
    if (items.isEmpty()) return EMPTY_SET
    val cap = items[0]
    val rest = items.drop(1)
    val capFirst = firstCharsetCap(cap, defs)
    if (!nullableCap(cap, defs)) return capFirst
    return unionSet(capFirst, firstCharsetItems(rest, defs))
}

private fun firstCharsetCap(cap: Capture, defs: Map<String, Expression>): CharSet =
    firstCharsetExcl(cap.inner.inner, defs)

private fun firstCharsetExcl(excl: Exclusion, defs: Map<String, Expression>): CharSet {
    val baseCs = if (excl.base is RangeItem.SingleAtom) firstCharsetAtom(excl.base.atom, defs) else ANY_CHAR
    if (excl.excluded == null) return baseCs
    val exclCs = if (excl.excluded is RangeItem.SingleAtom) firstCharsetAtom(excl.excluded.atom, defs) else ANY_CHAR
    return CharSet.Excl(baseCs, exclCs)
}

private fun firstCharsetAtom(atom: Atom, defs: Map<String, Expression>): CharSet = when (atom) {
    is Atom.Literal -> {
        val first = atom.content.firstOrNull()?.toString()
        if (first != null) CharSet.Literal(first) else EMPTY_SET
    }
    is Atom.CharClass -> CharSet.Named(atom.name)
    is Atom.PositionAssertion -> EMPTY_SET
    is Atom.Group -> firstCharsetExpr(atom.inner, defs)
    is Atom.Interpolation -> defs[atom.name]?.let { firstCharsetExpr(it, defs) } ?: ANY_CHAR
}

private fun lastCharsetExpr(expr: Expression, defs: Map<String, Expression>): CharSet =
    expr.alternatives.fold(EMPTY_SET) { acc, seq -> unionSet(acc, lastCharsetSeq(seq, defs)) }

private fun lastCharsetSeq(seq: Sequence, defs: Map<String, Expression>): CharSet =
    lastCharsetItems(seq.items.reversed(), defs)

private fun lastCharsetItems(revItems: List<Capture>, defs: Map<String, Expression>): CharSet {
    if (revItems.isEmpty()) return EMPTY_SET
    val cap = revItems[0]
    val rest = revItems.drop(1)
    val capLast = lastCharsetCap(cap, defs)
    if (!nullableCap(cap, defs)) return capLast
    return unionSet(capLast, lastCharsetItems(rest, defs))
}

private fun lastCharsetCap(cap: Capture, defs: Map<String, Expression>): CharSet =
    lastCharsetExcl(cap.inner.inner, defs)

private fun lastCharsetExcl(excl: Exclusion, defs: Map<String, Expression>): CharSet {
    val baseCs = if (excl.base is RangeItem.SingleAtom) lastCharsetAtom(excl.base.atom, defs) else ANY_CHAR
    if (excl.excluded == null) return baseCs
    val exclCs = if (excl.excluded is RangeItem.SingleAtom) firstCharsetAtom(excl.excluded.atom, defs) else ANY_CHAR
    return CharSet.Excl(baseCs, exclCs)
}

private fun lastCharsetAtom(atom: Atom, defs: Map<String, Expression>): CharSet = when (atom) {
    is Atom.Literal -> {
        val last = atom.content.lastOrNull()?.toString()
        if (last != null) CharSet.Literal(last) else EMPTY_SET
    }
    is Atom.CharClass -> CharSet.Named(atom.name)
    is Atom.PositionAssertion -> EMPTY_SET
    is Atom.Group -> lastCharsetExpr(atom.inner, defs)
    is Atom.Interpolation -> defs[atom.name]?.let { lastCharsetExpr(it, defs) } ?: ANY_CHAR
}

// ---------------------------------------------------------------------------
// Fixed-length detection
// ---------------------------------------------------------------------------

private fun fixedLenOfExcl(excl: Exclusion, defs: Map<String, Expression>): Int? {
    if (excl.base is RangeItem.CharRange) return 1
    if (excl.base is RangeItem.SingleAtom) return fixedLenOfAtom(excl.base.atom, defs)
    return null
}

private fun fixedLenOfAtom(atom: Atom, defs: Map<String, Expression>): Int? = when (atom) {
    is Atom.Literal -> atom.content.codePoints().count().toInt()
    is Atom.CharClass -> 1
    is Atom.PositionAssertion -> 0
    is Atom.Group -> fixedLenOfExpr(atom.inner, defs)
    is Atom.Interpolation -> defs[atom.name]?.let { fixedLenOfExpr(it, defs) }
}

private fun fixedLenOfExpr(expr: Expression, defs: Map<String, Expression>): Int? {
    val seqs = expr.alternatives
    if (seqs.isEmpty()) return 0
    val first = fixedLenOfSeq(seqs[0], defs)
    if (first == null) return null
    return if (seqs.drop(1).all { fixedLenOfSeq(it, defs) == first }) first else null
}

private fun fixedLenOfSeq(seq: Sequence, defs: Map<String, Expression>): Int? {
    var total = 0
    for (cap in seq.items) {
        val n = fixedLenOfCap(cap, defs) ?: return null
        total += n
    }
    return total
}

private fun fixedLenOfCap(cap: Capture, defs: Map<String, Expression>): Int? = fixedLenOfRep(cap.inner, defs)

private fun fixedLenOfRep(rep: Repetition, defs: Map<String, Expression>): Int? {
    if (rep.count == null) return fixedLenOfExcl(rep.inner, defs)
    val rc = rep.count
    if (rc.max is RepUpper.None) {
        val n = fixedLenOfExcl(rep.inner, defs) ?: return null
        return n * rc.min
    }
    if (rc.max is RepUpper.Exact && rc.min == rc.max.value) {
        val n = fixedLenOfExcl(rep.inner, defs) ?: return null
        return n * rc.min
    }
    return null
}

// ---------------------------------------------------------------------------
// Variable-length helpers
// ---------------------------------------------------------------------------

private fun isVariableCount(count: RepCount?): Boolean {
    if (count == null) return false
    if (count.max is RepUpper.None) return false
    if (count.max is RepUpper.Exact) return count.min != count.max.value
    return true // unbounded
}

private fun isUnboundedCount(count: RepCount?): Boolean =
    count != null && count.max is RepUpper.Unbounded

private fun isVariableLengthExcl(excl: Exclusion, defs: Map<String, Expression>): Boolean =
    fixedLenOfExcl(excl, defs) == null

// ---------------------------------------------------------------------------
// Recursive walk
// ---------------------------------------------------------------------------

private fun checkExpression(expr: Expression, defs: Map<String, Expression>): List<SemanticError> =
    expr.alternatives.flatMap { checkSequence(it, defs) }

private fun checkSequence(seq: Sequence, defs: Map<String, Expression>): List<SemanticError> {
    val adjErrors = checkAdjacentUnbounded(seq.items, defs)
    val innerErrors = seq.items.flatMap { checkCapture(it, defs) }
    return adjErrors + innerErrors
}

private fun checkCapture(cap: Capture, defs: Map<String, Expression>): List<SemanticError> =
    checkRepetition(cap.inner, defs)

private fun checkRepetition(rep: Repetition, defs: Map<String, Expression>): List<SemanticError> {
    val bodyErrs = if (rep.count != null) checkRepetitionBody(rep, defs) else emptyList()
    return bodyErrs + checkExclusion(rep.inner, defs)
}

private fun checkRepetitionBody(rep: Repetition, defs: Map<String, Expression>): List<SemanticError> {
    val base = rep.inner.base
    if (base is RangeItem.SingleAtom && base.atom is Atom.Group) {
        val branches = base.atom.inner.alternatives
        if (branches.size >= 2 && isVariableCount(rep.count)) {
            return checkPairwiseBranches(branches, defs)
        }
    }
    return checkBodySelfAmbiguity(rep, defs)
}

private fun checkPairwiseBranches(branches: List<Sequence>, defs: Map<String, Expression>): List<SemanticError> {
    val errs = mutableListOf<SemanticError>()
    for (i in branches.indices) {
        for (j in i + 1 until branches.size) {
            val bi = branches[i]
            val bj = branches[j]
            if (intersects(lastCharsetSeq(bi, defs), firstCharsetSeq(bj, defs)) ||
                intersects(lastCharsetSeq(bj, defs), firstCharsetSeq(bi, defs))) {
                errs.add(SemanticError.AmbiguousRepetitionAdjacency(seqLabel(bi), seqLabel(bj)))
            }
        }
    }
    return errs
}

private fun checkBodySelfAmbiguity(rep: Repetition, defs: Map<String, Expression>): List<SemanticError> {
    if (!isVariableLengthExcl(rep.inner, defs)) return emptyList()
    val fc = firstCharsetExcl(rep.inner, defs)
    val lc = lastCharsetExcl(rep.inner, defs)
    return if (intersects(lc, fc)) listOf(SemanticError.AmbiguousRepetitionBody) else emptyList()
}

private fun checkExclusion(excl: Exclusion, defs: Map<String, Expression>): List<SemanticError> {
    if (excl.base is RangeItem.SingleAtom) return checkAtom(excl.base.atom, defs)
    return emptyList()
}

private fun checkAtom(atom: Atom, defs: Map<String, Expression>): List<SemanticError> {
    if (atom is Atom.Group) return checkExpression(atom.inner, defs)
    return emptyList()
}

// ---------------------------------------------------------------------------
// Adjacent unbounded repetitions
// ---------------------------------------------------------------------------

private fun checkAdjacentUnbounded(items: List<Capture>, defs: Map<String, Expression>): List<SemanticError> {
    val errs = mutableListOf<SemanticError>()
    for (i in 0 until items.size - 1) {
        val capA = items[i]
        val capB = items[i + 1]
        if (isUnboundedCount(capA.inner.count) && isUnboundedCount(capB.inner.count)) {
            if (intersects(lastCharsetCap(capA, defs), firstCharsetCap(capB, defs))) {
                errs.add(SemanticError.AmbiguousAdjacentRepetition)
            }
        }
    }
    return errs
}

// ---------------------------------------------------------------------------
// Context builders
// ---------------------------------------------------------------------------

private fun buildDefs(definitions: List<Definition>): Map<String, Expression> =
    definitions.associate { it.name to it.body }

private fun buildCaptureExprs(expr: Expression): Map<String, Expression> =
    collectCapsFromExpr(expr, emptyMap())

private fun collectCapsFromExpr(expr: Expression, acc: Map<String, Expression>): Map<String, Expression> =
    expr.alternatives.fold(acc) { a, seq -> collectCapsFromSeq(seq, a) }

private fun collectCapsFromSeq(seq: Sequence, acc: Map<String, Expression>): Map<String, Expression> =
    seq.items.fold(acc) { a, cap -> collectCapsFromCap(cap, a) }

private fun collectCapsFromCap(cap: Capture, acc: Map<String, Expression>): Map<String, Expression> {
    var acc2 = acc
    if (cap.name != null && !acc.containsKey(cap.name)) {
        val capExpr = Expression(listOf(Sequence(listOf(Capture(cap.inner, null)))))
        acc2 = acc + (cap.name to capExpr)
    }
    return collectCapsFromExcl(cap.inner.inner, acc2)
}

private fun collectCapsFromExcl(excl: Exclusion, acc: Map<String, Expression>): Map<String, Expression> {
    if (excl.base is RangeItem.SingleAtom && excl.base.atom is Atom.Group) {
        return collectCapsFromExpr(excl.base.atom.inner, acc)
    }
    return acc
}

// ---------------------------------------------------------------------------
// Label helpers
// ---------------------------------------------------------------------------

private fun seqLabel(seq: Sequence): String = seq.items.joinToString(" ") { captureLabel(it) }
private fun captureLabel(cap: Capture): String = repLabel(cap.inner)
private fun repLabel(rep: Repetition): String = exclLabel(rep.inner)
private fun exclLabel(excl: Exclusion): String =
    if (excl.base is RangeItem.SingleAtom) atomLabel(excl.base.atom)
    else atomLabel((excl.base as RangeItem.CharRange).from) + ".." + atomLabel(excl.base.to)

private fun atomLabel(atom: Atom): String = when (atom) {
    is Atom.Literal -> "'${atom.content}'"
    is Atom.CharClass -> "%${atom.name}"
    is Atom.PositionAssertion -> "@${atom.name}"
    is Atom.Interpolation -> "{${atom.name}}"
    is Atom.Group -> "(...)"
}
