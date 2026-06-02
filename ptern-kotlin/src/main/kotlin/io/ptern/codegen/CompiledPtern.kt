package io.ptern.codegen

internal data class CompiledPtern(
    val source: String,
    val flags: Set<RegexOption>,
    val ignoreMatching: Boolean,
    val captureValidators: List<Pair<String, String>>,
    val isSubstitutable: Boolean,
    val ignoreSubstitutionMatching: Boolean,
    val substitutionPlan: SubstitutionPlan?,
    val repetitionInfo: List<RepetitionInfo>,
    val syntheticGroupNames: Set<String>,
)
