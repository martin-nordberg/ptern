package io.ptern.codegen

import io.ptern.parser.ast.ParsedPtern

internal fun compile(ptern: ParsedPtern): CompiledPtern {
    val flags = determineFlags(ptern)
    val ignoreMatching = determineIgnoreMatching(ptern.annotations)
    val isSubstitutable = ptern.annotations.any { it.name == "substitutable" && it.value }
    val ignoreSubstitutionMatching = ptern.annotations.any { it.name == "substitutions-ignore-matching" && it.value }
    val classDefs = compileClassDefinitions(ptern.definitions)
    val defs = compileDefinitions(ptern.definitions, classDefs)
    val emitResult = compileExpressionWithRepInfo(ptern.body, defs, classDefs)
    val captureValidators = collectCaptureValidators(ptern.body, defs, classDefs)
    val defBodies = ptern.definitions.associate { it.name to it.body }
    val substitutionPlan = if (isSubstitutable) buildSubstitutionPlan(ptern.body, defBodies) else null
    val syntheticGroupNames = emitResult.repInfo.map { it.groupName }.toSet()

    return CompiledPtern(
        source = emitResult.source,
        flags = flags,
        ignoreMatching = ignoreMatching,
        captureValidators = captureValidators,
        isSubstitutable = isSubstitutable,
        ignoreSubstitutionMatching = ignoreSubstitutionMatching,
        substitutionPlan = substitutionPlan,
        repetitionInfo = emitResult.repInfo,
        syntheticGroupNames = syntheticGroupNames,
    )
}
