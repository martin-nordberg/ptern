package io.ptern.formatter

import io.ptern.lexer.LexException
import io.ptern.lexer.Lexer
import io.ptern.parser.Parser
import io.ptern.parser.ast.*

// ---------------------------------------------------------------------------
// Public entry point
// ---------------------------------------------------------------------------

internal fun formatPtern(source: String, options: FormatOptions): String {
    if (options.lineWidth < 40) {
        throw PternFormatException(FormatError.InvalidLineWidth, "lineWidth must be >= 40")
    }
    val tokens = try {
        Lexer.lex(source)
    } catch (e: LexException) {
        throw PternFormatException(FormatError.FormatLexError(e.message ?: ""), "Lex error: ${e.message}")
    }
    val parsed = try {
        Parser.parse(tokens)
    } catch (e: ParseException) {
        throw PternFormatException(FormatError.FormatParseError(e.message ?: ""), "Parse error: ${e.message}")
    }
    return emitPtern(parsed, options)
}

// ---------------------------------------------------------------------------
// Piece type for line-breaking
// ---------------------------------------------------------------------------

private sealed class Piece {
    data class Text(val content: String) : Piece()
    object SeqSpace : Piece() { override fun toString() = "SeqSpace" }
    object Alt : Piece() { override fun toString() = "Alt" }
}

private fun pieceLen(p: Piece, compact: Boolean): Int = when (p) {
    is Piece.Text -> p.content.length
    Piece.SeqSpace -> 1
    Piece.Alt -> if (compact) 1 else 3
}

private fun piecesToStr(pieces: List<Piece>, compact: Boolean): String =
    pieces.joinToString("") { p ->
        when (p) {
            is Piece.Text -> p.content
            Piece.SeqSpace -> " "
            Piece.Alt -> if (compact) "|" else " | "
        }
    }

// ---------------------------------------------------------------------------
// Top-level emitter
// ---------------------------------------------------------------------------

private fun emitPtern(parsed: ParsedPtern, opts: FormatOptions): String {
    val compact = opts.compact
    val aligned = opts.aligned
    val lineWidth = opts.lineWidth

    val sortedAnns = parsed.annotations.sortedBy { it.name }
    val annCol = if (aligned && sortedAnns.isNotEmpty()) computeAlignCol(sortedAnns.map { it.name }) else 0
    val annLines = emitAnnotationBlock(sortedAnns, annCol, aligned, compact)

    val orderedDefs = if (opts.reordered) reorderDefinitions(parsed.definitions) else parsed.definitions
    val defCol = if (aligned && orderedDefs.isNotEmpty()) computeAlignCol(orderedDefs.map { it.name }) else 0
    val defLines = emitDefinitionBlock(orderedDefs, defCol, aligned, compact, lineWidth)

    val bodyCommentLines = parsed.bodyComments.map { "#$it" }
    val bodyPieces = emitExprPieces(parsed.body, compact)
    val bodyLines = breakBodyExpr(bodyPieces, "", lineWidth, compact)

    val hasAnns = sortedAnns.isNotEmpty()
    val hasDefs = orderedDefs.isNotEmpty()
    val annSep = if (hasAnns && !compact) listOf("") else emptyList()
    val defSep = if (hasDefs && !compact) listOf("") else emptyList()

    val pternBlock = if (parsed.pternComments.isEmpty()) emptyList()
    else parsed.pternComments.map { "#$it" } + listOf("")

    val allLines = pternBlock + annLines + annSep + defLines + defSep + bodyCommentLines + bodyLines
    return allLines.joinToString("\n")
}

// ---------------------------------------------------------------------------
// Annotation block
// ---------------------------------------------------------------------------

private fun emitAnnotationBlock(
    annotations: List<PternAnnotation>,
    alignCol: Int,
    aligned: Boolean,
    compact: Boolean,
): List<String> {
    val lines = mutableListOf<String>()
    annotations.forEachIndexed { i, ann ->
        if (ann.comments.isNotEmpty() && i > 0 && !compact) lines.add("")
        for (c in ann.comments) lines.add("#$c")
        lines.add(emitAnnotationLine(ann, alignCol, aligned))
    }
    return lines
}

private fun emitAnnotationLine(ann: PternAnnotation, alignCol: Int, aligned: Boolean): String {
    val namePart = "!${ann.name}"
    val spacing = if (aligned) " ".repeat(alignCol - namePart.length) else " "
    val valStr = if (ann.value) "true" else "false"
    return "$namePart${spacing}= $valStr"
}

// ---------------------------------------------------------------------------
// Definition ordering (reordered = true)
// ---------------------------------------------------------------------------

private fun reorderDefinitions(defs: List<Definition>): List<Definition> {
    val defNameSet = defs.map { it.name }.toSet()
    val adj = defs.map { it.name to collectDefRefs(it.body, defNameSet) }
    return topoLayerSort(defs, adj)
}

private fun collectDefRefs(expr: Expression, defNames: Set<String>): List<String> =
    expr.alternatives.flatMap { seq -> seq.items.flatMap { cap -> refsFromRep(cap.inner, defNames) } }

private fun refsFromRep(rep: Repetition, defNames: Set<String>): List<String> =
    refsFromExcl(rep.inner, defNames)

private fun refsFromExcl(excl: Exclusion, defNames: Set<String>): List<String> {
    val base = refsFromRangeItem(excl.base, defNames)
    val excluRefs = excl.excluded?.let { refsFromRangeItem(it, defNames) } ?: emptyList()
    return base + excluRefs
}

private fun refsFromRangeItem(ri: RangeItem, defNames: Set<String>): List<String> = when (ri) {
    is RangeItem.CharRange -> refsFromAtomNode(ri.from, defNames) + refsFromAtomNode(ri.to, defNames)
    is RangeItem.SingleAtom -> refsFromAtomNode(ri.atom, defNames)
}

private fun refsFromAtomNode(atom: Atom, defNames: Set<String>): List<String> = when (atom) {
    is Atom.Interpolation -> if (atom.name in defNames) listOf(atom.name) else emptyList()
    is Atom.Group -> collectDefRefs(atom.inner, defNames)
    else -> emptyList()
}

private fun topoLayerSort(defs: List<Definition>, adj: List<Pair<String, List<String>>>): List<Definition> {
    val layers = adj.map { (name, _) -> name to -1 }.toMutableList()
    var changed = true
    repeat(adj.size + 1) {
        if (!changed) return@repeat
        changed = false
        for (i in layers.indices) {
            val (name, curLayer) = layers[i]
            val deps = adj.find { it.first == name }?.second ?: emptyList()
            val newLayer = computeLayer(deps, layers)
            if (newLayer != curLayer) {
                layers[i] = name to newLayer
                changed = true
            }
        }
    }

    val cycleNames = layers.filter { it.second < 0 }.map { it.first }.toSet()
    val layeredNames = layers
        .filter { it.second >= 0 }
        .sortedWith(compareBy({ it.second }, { it.first }))
        .map { it.first }

    val findDef = { name: String -> defs.find { it.name == name }!! }
    return layeredNames.map(findDef) + defs.filter { it.name in cycleNames }
}

private fun computeLayer(deps: List<String>, layers: List<Pair<String, Int>>): Int {
    if (deps.isEmpty()) return 0
    val resolved = mutableListOf<Int>()
    for (dep in deps) {
        val entry = layers.find { it.first == dep } ?: return -1
        if (entry.second < 0) return -1
        resolved.add(entry.second)
    }
    return (resolved.maxOrNull() ?: -1) + 1
}

// ---------------------------------------------------------------------------
// Definition block
// ---------------------------------------------------------------------------

private fun emitDefinitionBlock(
    defs: List<Definition>,
    alignCol: Int,
    aligned: Boolean,
    compact: Boolean,
    lineWidth: Int,
): List<String> {
    val lines = mutableListOf<String>()
    defs.forEachIndexed { i, def ->
        if (def.comments.isNotEmpty() && i > 0 && !compact) lines.add("")
        for (c in def.comments) lines.add("#$c")
        lines.addAll(emitDefinition(def, alignCol, aligned, compact, lineWidth))
    }
    return lines
}

private fun emitDefinition(
    def: Definition,
    alignCol: Int,
    aligned: Boolean,
    compact: Boolean,
    lineWidth: Int,
): List<String> {
    val spacing = if (aligned) " ".repeat(alignCol - def.name.length) else " "
    val nameEq = "${def.name}${spacing}"
    val fullPrefix = "${nameEq}= "
    val bodyPieces = emitExprPieces(def.body, compact)
    return breakDefinition(fullPrefix, nameEq, bodyPieces, lineWidth, compact)
}

private fun breakDefinition(
    fullPrefix: String,
    nameEq: String,
    bodyPieces: List<Piece>,
    lineWidth: Int,
    compact: Boolean,
): List<String> {
    val bodyStr = piecesToStr(bodyPieces, compact)
    val bodyWithSemi = "$bodyStr ;"
    val fullLine = fullPrefix + bodyWithSemi

    if (fullLine.length <= lineWidth) return listOf(fullLine)

    // D1: body (including " ;") fits in lineWidth - 4
    if (bodyWithSemi.length <= lineWidth - 4) {
        val line1 = "$nameEq="
        val bodyLines = breakBodyExpr(bodyPieces, "    ", lineWidth, compact)
        if (bodyLines.isEmpty()) return listOf(line1)
        val rest = bodyLines.dropLast(1)
        val last = bodyLines.last()
        return listOf(line1) + rest + listOf("$last ;")
    }

    // D2/D3: wrap mid-line
    val col = fullPrefix.length
    val cont = " ".repeat(col)
    return breakLine(fullPrefix, cont, col, bodyPieces, " ;", lineWidth, compact)
}

// ---------------------------------------------------------------------------
// Body expression line breaking
// ---------------------------------------------------------------------------

private fun breakBodyExpr(
    pieces: List<Piece>,
    indent: String,
    lineWidth: Int,
    compact: Boolean,
): List<String> {
    val col = indent.length
    return breakLine(indent, indent, col, pieces, "", lineWidth, compact)
}

private fun breakLine(
    prefix: String,
    contPrefix: String,
    col: Int,
    pieces: List<Piece>,
    suffix: String,
    lineWidth: Int,
    compact: Boolean,
): List<String> {
    val flat = piecesToStr(pieces, compact)
    val fullLine = prefix + flat + suffix
    if (fullLine.length <= lineWidth) return listOf(fullLine)

    val limit = lineWidth - col

    // B1: break at rightmost seqSpace
    val seqIdx = findRightmostSeqBreak(pieces, limit, compact)
    if (seqIdx != null) {
        val before = pieces.subList(0, seqIdx)
        val after = pieces.subList(seqIdx + 1, pieces.size)
        val line1 = prefix + piecesToStr(before, compact)
        val contCol = contPrefix.length
        return listOf(line1) + breakLine(contPrefix, contPrefix, contCol, after, suffix, lineWidth, compact)
    }

    // B2: break at rightmost alt
    val altIdx = findRightmostAltBreak(pieces, limit, compact)
    if (altIdx != null) {
        val before = pieces.subList(0, altIdx)
        val after = pieces.subList(altIdx + 1, pieces.size)
        val line1 = prefix + piecesToStr(before, compact)
        val altBar = if (compact) "|" else "| "
        val altPrefix = " ".repeat(col) + altBar
        val altCol = altPrefix.length
        return listOf(line1) + breakLine(altPrefix, altPrefix, altCol, after, suffix, lineWidth, compact)
    }

    // B3: no break available, emit as-is
    return listOf(fullLine)
}

private fun findRightmostSeqBreak(pieces: List<Piece>, limit: Int, compact: Boolean): Int? {
    var pos = 0
    var best: Int? = null
    for (i in pieces.indices) {
        val p = pieces[i]
        if (p is Piece.SeqSpace && pos <= limit) best = i
        pos += pieceLen(p, compact)
    }
    return best
}

private fun findRightmostAltBreak(pieces: List<Piece>, limit: Int, compact: Boolean): Int? {
    var pos = 0
    var best: Int? = null
    for (i in pieces.indices) {
        val p = pieces[i]
        if (p is Piece.Alt) {
            val pipePos = if (compact) pos else pos + 1
            if (pipePos <= limit) best = i
        }
        pos += pieceLen(p, compact)
    }
    return best
}

// ---------------------------------------------------------------------------
// Expression piece emitters
// ---------------------------------------------------------------------------

private fun emitExprPieces(expr: Expression, compact: Boolean): List<Piece> {
    val branches = expr.alternatives
    if (branches.isEmpty()) return emptyList()
    if (branches.size == 1) return emitSeqPieces(branches[0], compact)
    return branches.flatMapIndexed { i, seq ->
        if (i == 0) emitSeqPieces(seq, compact)
        else listOf(Piece.Alt) + emitSeqPieces(seq, compact)
    }
}

private fun emitSeqPieces(seq: Sequence, compact: Boolean): List<Piece> {
    val items = seq.items
    if (items.isEmpty()) return emptyList()
    if (items.size == 1) return emitCapturePieces(items[0], compact)
    return items.flatMapIndexed { i, item ->
        if (i == 0) emitCapturePieces(item, compact)
        else listOf(Piece.SeqSpace) + emitCapturePieces(item, compact)
    }
}

private fun emitCapturePieces(cap: Capture, compact: Boolean): List<Piece> {
    val base = emitRepPieces(cap.inner, compact)
    if (cap.name == null) return base
    return base + listOf(Piece.Text(" as ${cap.name}"))
}

private fun emitRepPieces(rep: Repetition, compact: Boolean): List<Piece> {
    val exclStr = emitExclStr(rep.inner, compact)
    if (rep.count == null) return listOf(Piece.Text(exclStr))
    val sep = if (compact) "*" else " * "
    return listOf(Piece.Text(exclStr + sep + emitRepCountStr(rep.count)))
}

// ---------------------------------------------------------------------------
// String emitters for atoms and nested expressions
// ---------------------------------------------------------------------------

private fun emitExclStr(excl: Exclusion, compact: Boolean): String {
    val base = emitRangeItemStr(excl.base, compact)
    if (excl.excluded == null) return base
    return "$base excluding ${emitRangeItemStr(excl.excluded, compact)}"
}

private fun emitRangeItemStr(ri: RangeItem, compact: Boolean): String = when (ri) {
    is RangeItem.CharRange -> "${emitAtomStr(ri.from, compact)}..${emitAtomStr(ri.to, compact)}"
    is RangeItem.SingleAtom -> emitAtomStr(ri.atom, compact)
}

private fun emitAtomStr(atom: Atom, compact: Boolean): String = when (atom) {
    is Atom.Literal -> if ("'" in atom.content) "\"${atom.content}\"" else "'${atom.content}'"
    is Atom.CharClass -> "%${atom.name}"
    is Atom.Interpolation -> "{${atom.name}}"
    is Atom.PositionAssertion -> "@${atom.name}"
    is Atom.Group -> {
        val inner = emitExprStr(atom.inner, compact)
        if (compact) "($inner)" else "( $inner )"
    }
}

private fun emitExprStr(expr: Expression, compact: Boolean): String {
    val sep = if (compact) "|" else " | "
    return expr.alternatives.joinToString(sep) { emitSeqStr(it, compact) }
}

private fun emitSeqStr(seq: Sequence, compact: Boolean): String =
    seq.items.joinToString(" ") { emitCaptureStr(it, compact) }

private fun emitCaptureStr(cap: Capture, compact: Boolean): String {
    val base = emitRepStr(cap.inner, compact)
    return if (cap.name != null) "$base as ${cap.name}" else base
}

private fun emitRepStr(rep: Repetition, compact: Boolean): String {
    val exclStr = emitExclStr(rep.inner, compact)
    if (rep.count == null) return exclStr
    val sep = if (compact) "*" else " * "
    return "$exclStr$sep${emitRepCountStr(rep.count)}"
}

private fun emitRepCountStr(rc: RepCount): String {
    val base = when (val upper = rc.max) {
        is RepUpper.None -> "${rc.min}"
        is RepUpper.Exact -> "${rc.min}..${upper.value}"
        is RepUpper.Unbounded -> "${rc.min}..?"
    }
    return if (rc.lazy) "$base fewest" else base
}

// ---------------------------------------------------------------------------
// Alignment helper
// ---------------------------------------------------------------------------

private fun computeAlignCol(names: List<String>): Int = (names.maxOf { it.length }) + 2
