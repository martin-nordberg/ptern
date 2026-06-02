package io.ptern

data class MatchOccurrence(
    val index: Int,
    val length: Int,
    val captures: Map<String, String>,
)
