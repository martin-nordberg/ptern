package io.ptern.runtime

import io.ptern.PternSubstitutionException
import io.ptern.ReplacementValue
import io.ptern.SubstitutionError
import io.ptern.codegen.SubstitutionPlan
import java.util.regex.Pattern

internal class Substituter(
    private val captureValidators: List<Pair<String, String>>,
    private val ignoreMatching: Boolean,
) {
    private val validatorMap: Map<String, String> = captureValidators
        .groupBy({ it.first }, { it.second })
        .mapValues { (_, v) -> v.first() }

    fun evaluate(plan: SubstitutionPlan, captures: Map<String, ReplacementValue>): String =
        evalPlan(plan, captures)

    private fun evalPlan(plan: SubstitutionPlan, captures: Map<String, ReplacementValue>): String =
        when (plan) {
            is SubstitutionPlan.Literal -> plan.text
            is SubstitutionPlan.PositionAssertion -> ""
            is SubstitutionPlan.NotEvaluable -> throw PternSubstitutionException(
                SubstitutionError.CaptureMismatch(""),
                "Pattern element is not evaluable in substitution context",
            )
            is SubstitutionPlan.Capture -> evalCapture(plan, captures)
            is SubstitutionPlan.Sequence -> plan.items.joinToString("") { evalPlan(it, captures) }
            is SubstitutionPlan.Alternation -> evalAlternation(plan, captures)
            is SubstitutionPlan.FixedRep -> evalFixedRep(plan, captures)
            is SubstitutionPlan.BoundedRep -> evalBoundedRep(plan, captures)
        }

    private fun evalCapture(plan: SubstitutionPlan.Capture, captures: Map<String, ReplacementValue>): String {
        val value = captures[plan.name] ?: throw PternSubstitutionException(
            SubstitutionError.MissingCapture(plan.name),
            "Missing capture '${plan.name}'",
        )
        return when (value) {
            is ReplacementValue.Scalar -> {
                validateValue(plan.name, value.value)
                value.value
            }
            is ReplacementValue.Array -> {
                // Array substitution: evaluate inner plan once per element using per-element context
                if (value.values.isEmpty()) throw PternSubstitutionException(
                    SubstitutionError.ArrayLengthError(plan.name),
                    "Array replacement for '${plan.name}' is empty",
                )
                value.values.joinToString("") { v ->
                    validateValue(plan.name, v)
                    v
                }
            }
        }
    }

    private fun evalAlternation(plan: SubstitutionPlan.Alternation, captures: Map<String, ReplacementValue>): String {
        for (branch in plan.branches) {
            try {
                return evalPlan(branch, captures)
            } catch (_: PternSubstitutionException) {
                // try next branch
            }
        }
        throw PternSubstitutionException(SubstitutionError.NoMatchingBranch, "No matching branch in alternation")
    }

    private fun evalFixedRep(plan: SubstitutionPlan.FixedRep, captures: Map<String, ReplacementValue>): String =
        (0 until plan.count).joinToString("") { evalPlan(plan.inner, captures) }

    private fun evalBoundedRep(plan: SubstitutionPlan.BoundedRep, captures: Map<String, ReplacementValue>): String =
        evalPlan(plan.inner, captures)

    private fun validateValue(name: String, value: String) {
        if (ignoreMatching) return
        val pattern = validatorMap[name] ?: return
        val fullPattern = Pattern.compile(pattern)
        if (!fullPattern.matcher(value).matches()) {
            throw PternSubstitutionException(
                SubstitutionError.CaptureMismatch(name),
                "Substitution value '$value' does not match capture '$name'",
            )
        }
    }
}
