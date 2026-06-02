package io.ptern.formatter

data class FormatOptions(
    val lineWidth: Int = 80,
    val compact: Boolean = false,
    val aligned: Boolean = true,
    val reordered: Boolean = false,
)
