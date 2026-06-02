package io.ptern.semantic

import io.ptern.parser.ast.*

private val KNOWN_ANNOTATIONS = setOf(
    "case-insensitive",
    "multiline",
    "replacements-ignore-matching",
    "substitutable",
    "substitutions-ignore-matching",
    "allow-backtracking",
)

private val KNOWN_POSITION_ASSERTIONS = setOf(
    "word-start", "word-end", "line-start", "line-end",
)

object Validator {
    fun validate(ptern: ParsedPtern): List<SemanticError> {
        val isSubstitutable = ptern.annotations.any { it.name == "substitutable" && it.value }
        val defBodies = ptern.definitions.associate { it.name to it.body }
        val substAnnotErrs = validateSubstitutionAnnotations(ptern.annotations)
        val bodySubstErrs = if (isSubstitutable && !isSubstitutableExpr(ptern.body, defBodies))
            listOf(SemanticError.NotSubstitutableBody)
        else emptyList()

        return validateAnnotations(ptern.annotations) +
            substAnnotErrs +
            bodySubstErrs +
            validateDefinitions(ptern.definitions) +
            validateExpression(ptern.body, insideRep = false, isSubst = isSubstitutable, defBodies)
    }
}

// ---------------------------------------------------------------------------
// Annotations
// ---------------------------------------------------------------------------

private fun validateAnnotations(anns: List<PternAnnotation>): List<SemanticError> {
    val nameErrs = anns.flatMap { ann ->
        if (ann.name in KNOWN_ANNOTATIONS) emptyList()
        else listOf(SemanticError.UnknownAnnotation(ann.name))
    }
    return nameErrs + findDuplicateNames(anns.map { it.name }) { SemanticError.DuplicateAnnotation(it) }
}

private fun validateSubstitutionAnnotations(anns: List<PternAnnotation>): List<SemanticError> {
    val isSubstitutable = anns.any { it.name == "substitutable" && it.value }
    val ignoreMatchingSet = anns.any { it.name == "substitutions-ignore-matching" && it.value }
    return if (ignoreMatchingSet && !isSubstitutable)
        listOf(SemanticError.SubstitutionsIgnoreMatchingWithoutSubstitutable)
    else emptyList()
}

// ---------------------------------------------------------------------------
// Definitions
// ---------------------------------------------------------------------------

private fun validateDefinitions(defs: List<Definition>): List<SemanticError> =
    defs.flatMap { validateExpression(it.body, insideRep = false, isSubst = false, emptyMap()) }

// ---------------------------------------------------------------------------
// Expression tree walk
// ---------------------------------------------------------------------------

private fun validateExpression(
    expr: Expression,
    insideRep: Boolean,
    isSubst: Boolean,
    defBodies: Map<String, Expression>,
): List<SemanticError> = expr.alternatives.flatMap { validateSequence(it, insideRep, isSubst, defBodies) }

private fun validateSequence(
    seq: Sequence,
    insideRep: Boolean,
    isSubst: Boolean,
    defBodies: Map<String, Expression>,
): List<SemanticError> = seq.items.flatMap { validateCapture(it, insideRep, isSubst, defBodies) }

private fun validateCapture(
    cap: Capture,
    insideRep: Boolean,
    isSubst: Boolean,
    defBodies: Map<String, Expression>,
): List<SemanticError> {
    val covered = isSubst && cap.name != null
    return validateRepetition(cap.inner, insideRep, isSubst, covered, defBodies)
}

private fun validateRepetition(
    rep: Repetition,
    insideRep: Boolean,
    isSubst: Boolean,
    coveredByCapture: Boolean,
    defBodies: Map<String, Expression>,
): List<SemanticError> {
    val countErrs = mutableListOf<SemanticError>()
    if (rep.count != null) {
        countErrs += validateRepCount(rep.count)
        val excl = rep.inner
        if (excl.excluded == null && excl.base is RangeItem.SingleAtom && excl.base.atom is Atom.PositionAssertion) {
            countErrs += SemanticError.PositionAssertionInRepetition(excl.base.atom.name)
        }
        if (isSubst && !coveredByCapture) {
            val max = rep.count.max
            if ((max is RepUpper.Exact || max is RepUpper.Unbounded) && !hasNamedCaptureInExclusion(rep.inner)) {
                countErrs += SemanticError.BoundedRepetitionNeedsCapture
            }
        }
    }
    val subInside = rep.count != null || insideRep
    return countErrs + validateExclusion(rep.inner, subInside, isSubst, defBodies)
}

private fun validateRepCount(rc: RepCount): List<SemanticError> {
    val errs = mutableListOf<SemanticError>()
    if (rc.max is RepUpper.None && rc.lazy) errs += SemanticError.FewestOnExactRepetition
    if (rc.max is RepUpper.Exact && rc.min > rc.max.value) {
        errs += SemanticError.InvertedRepetitionBounds(rc.min, rc.max.value)
    }
    return errs
}

private fun validateExclusion(
    excl: Exclusion,
    insideRep: Boolean,
    isSubst: Boolean,
    defBodies: Map<String, Expression>,
): List<SemanticError> {
    val baseErrs = validateRangeItem(excl.base, insideRep, isSubst, defBodies)
    if (excl.excluded == null) return baseErrs
    val exclErrs = validateRangeItem(excl.excluded, insideRep, isSubst, defBodies)
    val setErrs = if (isCharSet(excl.base, defBodies) && isCharSet(excl.excluded, defBodies)) {
        if (rangeItemsEqual(excl.base, excl.excluded)) listOf(SemanticError.EmptyCharacterSet) else emptyList()
    } else {
        listOf(SemanticError.InvalidExclusionOperand)
    }
    return baseErrs + exclErrs + setErrs
}

private fun validateRangeItem(
    item: RangeItem,
    insideRep: Boolean,
    isSubst: Boolean,
    defBodies: Map<String, Expression>,
): List<SemanticError> = when (item) {
    is RangeItem.SingleAtom -> validateAtom(item.atom, insideRep, isSubst, defBodies)
    is RangeItem.CharRange -> validateCharRange(item.from, item.to)
}

private fun validateCharRange(from: Atom, to: Atom): List<SemanticError> {
    fun checkEndpoint(atom: Atom): List<SemanticError> = if (atom is Atom.Literal) {
        val lenErrs = if (decodedLength(atom.content) != 1)
            listOf(SemanticError.InvalidRangeEndpoint(atom.content)) else emptyList()
        lenErrs + validateLiteralEscapes(atom.content)
    } else {
        listOf(SemanticError.InvalidRangeEndpoint("<non-literal>"))
    }
    val fromErrs = checkEndpoint(from)
    val toErrs = checkEndpoint(to)
    val invErrs = if (from is Atom.Literal && to is Atom.Literal &&
        from.content.length == 1 && to.content.length == 1 &&
        from.content[0].code > to.content[0].code
    ) {
        listOf(SemanticError.InvertedRange(from.content, to.content))
    } else emptyList()
    return fromErrs + toErrs + invErrs
}

private fun validateAtom(
    atom: Atom,
    insideRep: Boolean,
    isSubst: Boolean,
    defBodies: Map<String, Expression>,
): List<SemanticError> = when (atom) {
    is Atom.Literal -> {
        if (atom.content.isEmpty()) listOf(SemanticError.EmptyLiteral)
        else validateLiteralEscapes(atom.content)
    }
    is Atom.CharClass, is Atom.Interpolation -> emptyList()
    is Atom.Group -> validateExpression(atom.inner, insideRep, isSubst, defBodies)
    is Atom.PositionAssertion ->
        if (atom.name in KNOWN_POSITION_ASSERTIONS) emptyList()
        else listOf(SemanticError.UnknownPositionAssertion(atom.name))
}

// ---------------------------------------------------------------------------
// Substitutability checks
// ---------------------------------------------------------------------------

private fun isSubstitutableExpr(expr: Expression, defBodies: Map<String, Expression>): Boolean =
    expr.alternatives.all { isSubstitutableSeq(it, defBodies) }

private fun isSubstitutableSeq(seq: Sequence, defBodies: Map<String, Expression>): Boolean =
    seq.items.all { isSubstitutableCap(it, defBodies) }

private fun isSubstitutableCap(cap: Capture, defBodies: Map<String, Expression>): Boolean =
    cap.name != null || isSubstitutableRep(cap.inner, defBodies)

private fun isSubstitutableRep(rep: Repetition, defBodies: Map<String, Expression>): Boolean {
    if (rep.count == null) return isSubstitutableExcl(rep.inner, defBodies)
    if (rep.count.max is RepUpper.None) return isSubstitutableExcl(rep.inner, defBodies)
    return hasNamedCaptureInExclusion(rep.inner)
}

private fun isSubstitutableExcl(excl: Exclusion, defBodies: Map<String, Expression>): Boolean {
    if (excl.excluded != null) return false
    return isSubstitutableItem(excl.base, defBodies)
}

private fun isSubstitutableItem(item: RangeItem, defBodies: Map<String, Expression>): Boolean =
    item is RangeItem.SingleAtom && isSubstitutableAtom(item.atom, defBodies)

private fun isSubstitutableAtom(atom: Atom, defBodies: Map<String, Expression>): Boolean = when (atom) {
    is Atom.Literal, is Atom.PositionAssertion -> true
    is Atom.CharClass -> false
    is Atom.Interpolation -> defBodies[atom.name]?.let { isSubstitutableExpr(it, defBodies) } ?: false
    is Atom.Group -> isSubstitutableExpr(atom.inner, defBodies)
}

// ---------------------------------------------------------------------------
// Named capture helpers
// ---------------------------------------------------------------------------

fun hasNamedCaptureInExclusion(excl: Exclusion): Boolean = hasNamedCaptureInItem(excl.base)

private fun hasNamedCaptureInItem(item: RangeItem): Boolean =
    item is RangeItem.SingleAtom && hasNamedCaptureInAtom(item.atom)

private fun hasNamedCaptureInAtom(atom: Atom): Boolean =
    atom is Atom.Group && hasNamedCaptureInExpr(atom.inner)

private fun hasNamedCaptureInExpr(expr: Expression): Boolean =
    expr.alternatives.any { hasNamedCaptureInSeq(it) }

private fun hasNamedCaptureInSeq(seq: Sequence): Boolean =
    seq.items.any { hasNamedCaptureInCap(it) }

private fun hasNamedCaptureInCap(cap: Capture): Boolean =
    cap.name != null || hasNamedCaptureInRep(cap.inner)

private fun hasNamedCaptureInRep(rep: Repetition): Boolean = hasNamedCaptureInExclusion(rep.inner)

// ---------------------------------------------------------------------------
// Character set helpers
// ---------------------------------------------------------------------------

private fun isSimpleCharSet(item: RangeItem): Boolean = when (item) {
    is RangeItem.CharRange -> item.from is Atom.Literal && item.to is Atom.Literal
    is RangeItem.SingleAtom -> when (val atom = item.atom) {
        is Atom.Literal -> decodedLength(atom.content) == 1
        is Atom.CharClass -> true
        else -> false
    }
}

fun isCharSet(item: RangeItem, defBodies: Map<String, Expression>): Boolean {
    if (item is RangeItem.SingleAtom) {
        val atom = item.atom
        if (atom is Atom.Group) {
            val alts = atom.inner.alternatives
            return alts.isNotEmpty() && alts.all { isCharSetGroupAlt(it) }
        }
        if (atom is Atom.Interpolation) {
            val body = defBodies[atom.name]
            return body != null && isCharSetInterpBody(body, defBodies)
        }
    }
    return isSimpleCharSet(item)
}

private fun isCharSetGroupAlt(seq: Sequence): Boolean {
    if (seq.items.size != 1) return false
    val cap = seq.items[0]
    return cap.name == null && cap.inner.count == null &&
        cap.inner.inner.excluded == null && isSimpleCharSet(cap.inner.inner.base)
}

private fun isCharSetInterpBody(expr: Expression, defBodies: Map<String, Expression>): Boolean =
    expr.alternatives.isNotEmpty() && expr.alternatives.all { isCharSetInterpAlt(it, defBodies) }

private fun isCharSetInterpAlt(seq: Sequence, defBodies: Map<String, Expression>): Boolean {
    if (seq.items.size != 1) return false
    val cap = seq.items[0]
    return cap.name == null && cap.inner.count == null &&
        cap.inner.inner.excluded == null && isCharSet(cap.inner.inner.base, defBodies)
}

private fun rangeItemsEqual(a: RangeItem, b: RangeItem): Boolean = when {
    a is RangeItem.CharRange && b is RangeItem.CharRange ->
        atomsEqual(a.from, b.from) && atomsEqual(a.to, b.to)
    a is RangeItem.SingleAtom && b is RangeItem.SingleAtom ->
        atomsEqual(a.atom, b.atom)
    else -> false
}

private fun atomsEqual(a: Atom, b: Atom): Boolean = when {
    a is Atom.Literal && b is Atom.Literal -> a.content == b.content
    a is Atom.CharClass && b is Atom.CharClass -> a.name == b.name
    else -> false
}

// ---------------------------------------------------------------------------
// Escape sequence validation
// ---------------------------------------------------------------------------

private fun validateLiteralEscapes(content: String): List<SemanticError> {
    val errs = mutableListOf<SemanticError>()
    var i = 0
    while (i < content.length) {
        if (content[i] == '\\') {
            i++
            if (i >= content.length) { errs += SemanticError.InvalidEscapeSequence("\\"); break }
            val c = content[i]
            if ("ntrAfv'\"\\".contains(c)) {
                i++
            } else if (c == 'u') {
                i += 5
            } else {
                errs += SemanticError.InvalidEscapeSequence("\\" + c)
                i++
            }
        } else {
            val cp = content.codePointAt(i)
            i += Character.charCount(cp)
        }
    }
    return errs
}

// ---------------------------------------------------------------------------
// Decoded length
// ---------------------------------------------------------------------------

fun decodedLength(content: String): Int {
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

// ---------------------------------------------------------------------------
// Duplicate detection helper
// ---------------------------------------------------------------------------

private fun findDuplicateNames(names: List<String>, make: (String) -> SemanticError): List<SemanticError> {
    val seen = mutableSetOf<String>()
    val dups = mutableSetOf<String>()
    for (name in names) {
        if (!seen.add(name)) dups.add(name)
    }
    return dups.map(make)
}
