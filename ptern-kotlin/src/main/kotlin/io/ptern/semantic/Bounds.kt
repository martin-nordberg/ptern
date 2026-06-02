package io.ptern.semantic

import io.ptern.parser.ast.*

data class Bounds(val min: Int, val max: Int?)

internal fun computePternBounds(parsed: ParsedPtern): Bounds {
    val defBounds = computeDefBoundsAll(parsed.definitions)
    return computeExpressionBounds(parsed.body, defBounds)
}

// ---------------------------------------------------------------------------
// Definition bounds (memoised)
// ---------------------------------------------------------------------------

private fun computeDefBoundsAll(defs: List<Definition>): Map<String, Bounds> {
    val defExprs = defs.associate { it.name to it.body }
    val acc = mutableMapOf<String, Bounds>()
    for (def in defs) computeDefBoundsMemo(def.name, defExprs, acc)
    return acc
}

private fun computeDefBoundsMemo(
    name: String,
    defExprs: Map<String, Expression>,
    acc: MutableMap<String, Bounds>,
) {
    if (acc.containsKey(name)) return
    val body = defExprs[name] ?: return
    acc[name] = computeExpressionBounds(body, acc)
}

// ---------------------------------------------------------------------------
// Expression bounds
// ---------------------------------------------------------------------------

private fun computeExpressionBounds(expr: Expression, defs: Map<String, Bounds>): Bounds {
    val seqs = expr.alternatives
    if (seqs.isEmpty()) return Bounds(0, 0)
    val first = computeSequenceBounds(seqs[0], defs)
    return seqs.drop(1).fold(first) { acc, seq ->
        val b = computeSequenceBounds(seq, defs)
        Bounds(minOf(acc.min, b.min), maxOpt(acc.max, b.max))
    }
}

private fun computeSequenceBounds(seq: Sequence, defs: Map<String, Bounds>): Bounds =
    seq.items.fold(Bounds(0, 0)) { acc, cap ->
        val b = computeRepetitionBounds(cap.inner, defs)
        Bounds(acc.min + b.min, addOpt(acc.max, b.max))
    }

private fun computeRepetitionBounds(rep: Repetition, defs: Map<String, Bounds>): Bounds {
    val inner = computeExclusionBounds(rep.inner, defs)
    if (rep.count == null) return inner
    val min = rep.count.min
    val repMax = rep.count.max
    if (repMax is RepUpper.Exact) return Bounds(inner.min * min, mulOpt(inner.max, repMax.value))
    if (repMax is RepUpper.None) return Bounds(inner.min * min, mulOpt(inner.max, min))
    return Bounds(inner.min * min, null) // unbounded
}

private fun computeExclusionBounds(excl: Exclusion, defs: Map<String, Bounds>): Bounds =
    computeRangeItemBounds(excl.base, defs)

private fun computeRangeItemBounds(item: RangeItem, defs: Map<String, Bounds>): Bounds {
    if (item is RangeItem.CharRange) return Bounds(1, 1)
    if (item is RangeItem.SingleAtom) return computeAtomBounds(item.atom, defs)
    return Bounds(0, 0)
}

private fun computeAtomBounds(atom: Atom, defs: Map<String, Bounds>): Bounds = when (atom) {
    is Atom.Literal -> {
        val len = decodedLength(atom.content)
        Bounds(len, len)
    }
    is Atom.CharClass -> Bounds(1, 1)
    is Atom.Interpolation -> defs[atom.name] ?: Bounds(0, 0)
    is Atom.Group -> computeExpressionBounds(atom.inner, defs)
    is Atom.PositionAssertion -> Bounds(0, 0)
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

private fun addOpt(a: Int?, b: Int?): Int? = if (a == null || b == null) null else a + b
private fun maxOpt(a: Int?, b: Int?): Int? = if (a == null || b == null) null else maxOf(a, b)
private fun mulOpt(a: Int?, n: Int): Int? = if (a == null) null else a * n
