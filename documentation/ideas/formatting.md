# Ptern Automated Formatting

Provide a na API within Ptern to reformat the source code of a ptern.

* Public API:
  
    `pub fn format(source: String, options: Dict) -> Result(String, FormatError);`

* Options:

  - lineWidth - integer >= 40 - the target maximum line width for the output; default = 80
  - compact - boolean - if true format with less whitespace; default = false
  - aligned - boolean - if true, vertically align '=' in annotations and definitions; default = true

Below is a procedural definition of how code is to be formatted:

## Errors

Check whether the ptern compiles. If there are syntax errors (i.e. no valid AST), then stop
and return the same error as compile(..).

## Overall Layout

Organize the code as follows:

  - (No leading blank lines)
  - Annotations in alphabteical order, one per line
  - One blank line if there are annotations
  - Definitions in their original order, one per line
  - One blank line if there are definitions
  - The final pattern all on one line
  - (No trailing blank lines)

## Whitespace

1. Use no tab characters; replace tabs with spaces.

2. Shrink all whitespace to at most one space character except for the alignment whitespace
   noted below.

3. Include space characters as follows:
|Case|compact = false|compact = true|
|----|---------------|--------------|
|Before and after '..'|0|0|
|Before and after '*'|1|0|
|Before and after '\|'|1|0|
|After '('|1|0|
|Before ')'|1|0|
|Before and after any keyword|1|1|

The compact option does not affect whitespace around '='; only the aligned option has an effect.

|Case     |aligned=false|aligned=true|
|---------|-------------|------------|
|Before '='|1|Enough space characters to vertically align all annotations or all definitions (not both) such that the longest annotation name or definition name is followed by one space character.|
|After '='|1|1|

   
## Line Breaks

### Annotations

1. Always leave each annotation all on one line. It should not be possible for an annotation to exceed the minimum allowed target line width of 40.

2. If compact = false, put one blank line after the annotations, if there are any. If compact = true
add no such separator line.

### Definitions

1. If the whole line is longer than lineWidth and the trimmed text to the right of '=' is less than
   lineWidth - 4, then put a line break after '=' and indent the remainder by 4 spaces.

2. If a definition line remains longer than lineWidth, replace the rightmost mandatory whitespace
   that occurs within the first lineWidth+1 characters with a line break. Indent the remainder after
   the break such that it starts vertically aligned with the text after ' = ' just above.

3. If a definition line starts with an alternation and cannot be broken by mandatory whitespace
   as above, then put a line break before the rightmost '|' of the same alternation that falls
   in the first lineWidth+1 characters. Indent the
   remainder so that the '|' aligns with '(' or '|' of the preceding line.

4. If none of the above rules applies, leave the line longer than the target width.

5. If compact = false, put one blank line after the definitions, if there are any. If compact = true
add no such separator line.

### Final Pattern

1. If a pattern line remains longer than lineWidth, replace the rightmost mandatory whitespace
   that occurs within the first lineWidth+1 characters with a line break. Do not indent the
   remainder on the next the line.

2. If a pattern line starts with an alternation and cannot be broken by mandatory whitespace
   as above, then put a line break before the rightmost '|' of the same alternation that falls
   in the first lineWidth+1 characters. Do not indent the remainder on the next line.
