package io.ptern.codegen

sealed class SubstitutionPlan {
    data class Literal(val text: String) : SubstitutionPlan()
    object PositionAssertion : SubstitutionPlan() { override fun toString() = "PositionAssertion" }
    object NotEvaluable : SubstitutionPlan() { override fun toString() = "NotEvaluable" }
    data class Capture(val name: String, val inner: SubstitutionPlan) : SubstitutionPlan()
    data class Sequence(val items: List<SubstitutionPlan>) : SubstitutionPlan()
    data class Alternation(val branches: List<SubstitutionPlan>) : SubstitutionPlan()
    data class FixedRep(val inner: SubstitutionPlan, val count: Int) : SubstitutionPlan()
    data class BoundedRep(val inner: SubstitutionPlan, val min: Int, val max: Int?) : SubstitutionPlan()
}
