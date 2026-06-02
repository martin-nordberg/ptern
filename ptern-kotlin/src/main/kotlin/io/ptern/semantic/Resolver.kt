package io.ptern.semantic

import io.ptern.parser.ast.*

object Resolver {
    fun resolve(ptern: ParsedPtern): List<SemanticError> {
        val (defNames, dupDefErrs) = collectDefNames(ptern.definitions)
        val circErrs = findCircularDefinitions(ptern.definitions, defNames)
        val defRefErrs = ptern.definitions.flatMap { checkUndefinedRefs(it.body, defNames, emptyList()) }
        val bodyCapNames = capturesInExpression(ptern.body)
        val dupCapErrs = findDuplicateNames(bodyCapNames) { SemanticError.DuplicateCapture(it) }
        val defCapNames = ptern.definitions.flatMap { capturesInExpression(it.body) }
        val allCapNames = bodyCapNames + defCapNames
        val conflictErrs = findCaptureDefConflicts(allCapNames, defNames)
        val bodyRefErrs = checkUndefinedRefs(ptern.body, defNames, bodyCapNames)
        val unusedErrs = findUnusedDefinitions(ptern.definitions, defNames, ptern.body)

        return dupDefErrs + circErrs + defRefErrs + dupCapErrs + conflictErrs + bodyRefErrs + unusedErrs
    }
}

// ---------------------------------------------------------------------------
// Definition name collection
// ---------------------------------------------------------------------------

private fun collectDefNames(defs: List<Definition>): Pair<List<String>, List<SemanticError>> {
    val names = defs.map { it.name }
    val errors = findDuplicateNames(names) { SemanticError.DuplicateDefinition(it) }
    return Pair(dedup(names), errors)
}

// ---------------------------------------------------------------------------
// Circular definition detection
// ---------------------------------------------------------------------------

private fun findCircularDefinitions(defs: List<Definition>, defNames: List<String>): List<SemanticError> {
    val graph = defs.associate { def ->
        def.name to interpolationsInExpression(def.body).filter { it in defNames }
    }
    val allCycles = defNames.flatMap { dfsCycles(graph, it, emptyList()) }
    val sortedCycles = allCycles.map { it.sorted() }
    return dedupLists(sortedCycles).map { SemanticError.CircularDefinition(it) }
}

private fun dfsCycles(graph: Map<String, List<String>>, node: String, path: List<String>): List<List<String>> {
    if (node in path) return listOf(takeUntilInclusive(path, node))
    val newPath = listOf(node) + path
    return (graph[node] ?: emptyList()).flatMap { dfsCycles(graph, it, newPath) }
}

private fun takeUntilInclusive(lst: List<String>, target: String): List<String> {
    val result = mutableListOf<String>()
    for (x in lst) {
        result.add(x)
        if (x == target) break
    }
    return result
}

// ---------------------------------------------------------------------------
// Unused definition detection
// ---------------------------------------------------------------------------

private fun findUnusedDefinitions(
    defs: List<Definition>,
    defNames: List<String>,
    body: Expression,
): List<SemanticError> {
    val graph = defs.associate { def ->
        def.name to interpolationsInExpression(def.body).filter { it in defNames }
    }
    val seeds = interpolationsInExpression(body).filter { it in defNames }
    val reachable = expandReachable(graph, seeds, emptyList())
    return defNames.filter { it !in reachable }.map { SemanticError.UnusedDefinition(it) }
}

private fun expandReachable(
    graph: Map<String, List<String>>,
    frontier: List<String>,
    visited: List<String>,
): List<String> {
    if (frontier.isEmpty()) return visited
    val name = frontier[0]
    val rest = frontier.drop(1)
    if (name in visited) return expandReachable(graph, rest, visited)
    val deps = graph[name] ?: emptyList()
    return expandReachable(graph, deps + rest, listOf(name) + visited)
}

// ---------------------------------------------------------------------------
// Undefined reference checking
// ---------------------------------------------------------------------------

private fun checkUndefinedRefs(
    expr: Expression,
    defNames: List<String>,
    capNames: List<String>,
): List<SemanticError> =
    interpolationsInExpression(expr)
        .filter { it !in defNames && it !in capNames }
        .map { SemanticError.UndefinedReference(it) }

// ---------------------------------------------------------------------------
// Capture / definition conflict checking
// ---------------------------------------------------------------------------

private fun findCaptureDefConflicts(capNames: List<String>, defNames: List<String>): List<SemanticError> =
    dedup(capNames).filter { it in defNames }.map { SemanticError.CaptureDefinitionConflict(it) }

// ---------------------------------------------------------------------------
// Collecting interpolation names from AST
// ---------------------------------------------------------------------------

private fun interpolationsInExpression(expr: Expression): List<String> =
    expr.alternatives.flatMap { interpolationsInSequence(it) }

private fun interpolationsInSequence(seq: Sequence): List<String> =
    seq.items.flatMap { interpolationsInCapture(it) }

private fun interpolationsInCapture(cap: Capture): List<String> =
    interpolationsInRepetition(cap.inner)

private fun interpolationsInRepetition(rep: Repetition): List<String> =
    interpolationsInExclusion(rep.inner)

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
// Collecting capture names from AST
// ---------------------------------------------------------------------------

private fun capturesInExpression(expr: Expression): List<String> =
    expr.alternatives.flatMap { capturesInSequence(it) }

private fun capturesInSequence(seq: Sequence): List<String> =
    seq.items.flatMap { capturesInCapture(it) }

private fun capturesInCapture(cap: Capture): List<String> =
    (if (cap.name != null) listOf(cap.name) else emptyList()) + capturesInRepetition(cap.inner)

private fun capturesInRepetition(rep: Repetition): List<String> =
    capturesInExclusion(rep.inner)

private fun capturesInExclusion(excl: Exclusion): List<String> =
    capturesInRangeItem(excl.base)

private fun capturesInRangeItem(item: RangeItem): List<String> =
    if (item is RangeItem.SingleAtom) capturesInAtom(item.atom) else emptyList()

private fun capturesInAtom(atom: Atom): List<String> =
    if (atom is Atom.Group) capturesInExpression(atom.inner) else emptyList()

// ---------------------------------------------------------------------------
// List utilities
// ---------------------------------------------------------------------------

private fun findDuplicateNames(names: List<String>, make: (String) -> SemanticError): List<SemanticError> {
    val seen = mutableSetOf<String>()
    val dups = mutableSetOf<String>()
    for (name in names) {
        if (!seen.add(name)) dups.add(name)
    }
    return dups.map(make)
}

private fun dedup(lst: List<String>): List<String> {
    val seen = mutableSetOf<String>()
    return lst.filter { seen.add(it) }
}

private fun dedupLists(lsts: List<List<String>>): List<List<String>> {
    val result = mutableListOf<List<String>>()
    for (lst in lsts) {
        if (result.none { it.size == lst.size && it.zip(lst).all { (a, b) -> a == b } }) {
            result.add(lst)
        }
    }
    return result
}
