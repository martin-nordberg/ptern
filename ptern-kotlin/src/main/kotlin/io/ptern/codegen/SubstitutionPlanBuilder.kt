package io.ptern.codegen

import io.ptern.parser.ast.*

// ---------------------------------------------------------------------------
// Public entry point
// ---------------------------------------------------------------------------

internal fun buildSubstitutionPlan(body: Expression, defBodies: Map<String, Expression>): SubstitutionPlan {
    val capReps = collectCaptureRepsInExpr(body)
    return buildPlanExpr(body, defBodies, capReps)
}

// ---------------------------------------------------------------------------
// Body-capture repetition collector
// ---------------------------------------------------------------------------

private fun collectCaptureRepsInExpr(expr: Expression): Map<String, Repetition> =
    expr.alternatives.fold(emptyMap()) { acc, seq -> acc + collectCaptureRepsInSeq(seq) }

private fun collectCaptureRepsInSeq(seq: Sequence): Map<String, Repetition> =
    seq.items.fold(emptyMap()) { acc, cap -> acc + collectCaptureRepsInCap(cap) }

private fun collectCaptureRepsInCap(cap: Capture): Map<String, Repetition> {
    val own = if (cap.name != null) mapOf(cap.name to cap.inner) else emptyMap()
    return own + collectCaptureRepsInExcl(cap.inner.inner)
}

private fun collectCaptureRepsInExcl(excl: Exclusion): Map<String, Repetition> =
    collectCaptureRepsInItem(excl.base)

private fun collectCaptureRepsInItem(item: RangeItem): Map<String, Repetition> {
    if (item is RangeItem.CharRange) return emptyMap()
    if (item is RangeItem.SingleAtom) return collectCaptureRepsInAtom(item.atom)
    return emptyMap()
}

private fun collectCaptureRepsInAtom(atom: Atom): Map<String, Repetition> =
    if (atom is Atom.Group) collectCaptureRepsInExpr(atom.inner) else emptyMap()

// ---------------------------------------------------------------------------
// Plan builder
// ---------------------------------------------------------------------------

private fun buildPlanExpr(
    expr: Expression,
    defBodies: Map<String, Expression>,
    capReps: Map<String, Repetition>,
): SubstitutionPlan {
    val seqs = expr.alternatives
    if (seqs.size == 1) return buildPlanSeq(seqs[0], defBodies, capReps)
    return SubstitutionPlan.Alternation(seqs.map { buildPlanSeq(it, defBodies, capReps) })
}

private fun buildPlanSeq(
    seq: Sequence,
    defBodies: Map<String, Expression>,
    capReps: Map<String, Repetition>,
): SubstitutionPlan {
    val items = seq.items
    if (items.size == 1) return buildPlanCap(items[0], defBodies, capReps)
    return SubstitutionPlan.Sequence(items.map { buildPlanCap(it, defBodies, capReps) })
}

private fun buildPlanCap(
    cap: Capture,
    defBodies: Map<String, Expression>,
    capReps: Map<String, Repetition>,
): SubstitutionPlan {
    val inner = buildPlanRep(cap.inner, defBodies, capReps)
    if (cap.name == null) return inner
    return SubstitutionPlan.Capture(cap.name, inner)
}

private fun buildPlanRep(
    rep: Repetition,
    defBodies: Map<String, Expression>,
    capReps: Map<String, Repetition>,
): SubstitutionPlan {
    val base = buildPlanItem(rep.inner.base, defBodies, capReps)
    val inner: SubstitutionPlan = if (rep.inner.excluded != null) SubstitutionPlan.NotEvaluable else base
    if (rep.count == null) return inner
    val rc = rep.count
    if (rc.max is RepUpper.None) return SubstitutionPlan.FixedRep(inner, rc.min)
    if (rc.max is RepUpper.Exact) return SubstitutionPlan.BoundedRep(inner, rc.min, rc.max.value)
    return SubstitutionPlan.BoundedRep(inner, rc.min, null) // unbounded
}

private fun buildPlanItem(
    item: RangeItem,
    defBodies: Map<String, Expression>,
    capReps: Map<String, Repetition>,
): SubstitutionPlan {
    if (item is RangeItem.CharRange) return SubstitutionPlan.NotEvaluable
    if (item is RangeItem.SingleAtom) return buildPlanAtom(item.atom, defBodies, capReps)
    return SubstitutionPlan.NotEvaluable
}

private fun buildPlanAtom(
    atom: Atom,
    defBodies: Map<String, Expression>,
    capReps: Map<String, Repetition>,
): SubstitutionPlan = when (atom) {
    is Atom.Literal -> SubstitutionPlan.Literal(rawToString(atom.content))
    is Atom.CharClass -> SubstitutionPlan.NotEvaluable
    is Atom.PositionAssertion -> SubstitutionPlan.PositionAssertion
    is Atom.Interpolation -> {
        val body = defBodies[atom.name]
        if (body != null) {
            buildPlanExpr(body, defBodies, capReps)
        } else if (capReps.containsKey(atom.name)) {
            SubstitutionPlan.Capture(atom.name, SubstitutionPlan.NotEvaluable)
        } else {
            SubstitutionPlan.Literal("")
        }
    }
    is Atom.Group -> buildPlanExpr(atom.inner, defBodies, capReps)
}

// ---------------------------------------------------------------------------
// Literal decoding (raw content → plain string for plan Literal nodes)
// ---------------------------------------------------------------------------

private fun rawToString(raw: String): String {
    val result = StringBuilder()
    var i = 0
    while (i < raw.length) {
        if (raw[i] == '\\') {
            i++
            if (i >= raw.length) break
            val c = raw[i]
            when (c) {
                'n' -> { result.append('\n'); i++ }
                't' -> { result.append('\t'); i++ }
                'r' -> { result.append('\r'); i++ }
                'a' -> { result.append(''); i++ }
                'f' -> { result.append(''); i++ }
                'v' -> { result.append(''); i++ }
                '\\' -> { result.append('\\'); i++ }
                '\'' -> { result.append('\''); i++ }
                '"' -> { result.append('"'); i++ }
                'u' -> {
                    val hex = raw.substring(i + 1, minOf(i + 5, raw.length))
                    val cp = hex.toIntOrNull(16)
                    if (cp != null) result.appendCodePoint(cp)
                    i += 5
                }
                else -> { result.append(c); i++ }
            }
        } else {
            val cp = raw.codePointAt(i)
            result.appendCodePoint(cp)
            i += Character.charCount(cp)
        }
    }
    return result.toString()
}
