package io.ptern

sealed class ReplacementValue {
    data class Scalar(val value: String) : ReplacementValue()
    data class Array(val values: List<String>) : ReplacementValue()
}
