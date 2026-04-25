Aside: what would you say is the feasibility for capturing multiple values within a repetition. E.g. for ptern `(%Digit as digit)*4`, ptern.match("1234") == {digit: ["1", "2",
"3", "4"]}

Short answer: conceptually sound, but non-trivial due to JS regex limitations.

The core problem is that JavaScript regex doesn't support this natively. Named captures inside repetitions always yield only the last match:

/(?<digit>\d){4}/.exec("1234")                                                                                                                                                  
// groups: { digit: "4" }

So ptern would have to work around this. Two realistic paths:

**Unrolling (fixed counts only)**                                                                                                                                                   
For * 4, emit (?<digit_1>\d)(?<digit_2>\d)(?<digit_3>\d)(?<digit_4>\d) and collect digit_1..4 into an array post-match. Clean, but only works for fixed * N. For bounded ranges
like * 2..5 the regex size is variable and the capture name indexing gets messy.

**Two-pass matching (general)**                                                                                                                                                     
Run the main regex to find the overall match bounds (already using the d flag for indices), then apply a sticky sub-regex for the repeated sub-pattern within that region to
collect all per-iteration captures. More complex but handles bounded repetitions.

**API implication**                                                                                                                                                                 
captures would need to be string | string[] rather than string, which is a meaningful type-level change that every caller has to handle.

**The symmetry argument**
There's a compelling case for it: if substitute({digit: ["1","2","3","4"]}) already proposes arrays as input for repeated captures, then match() returning {digit:              
["1","2","3","4"]} is the natural inverse. The substitution design already commits to this mental model.

My assessment: worth doing eventually, but a separate feature from substitution. The two-pass approach is the right general solution, and the API change should be deliberate. I
wouldn't let it block the substitution feature.

---------------

Tell me more about the two-pass matching approach

The core idea: the main regex finds where the overall match is, then a secondary regex extracts each iteration's captures from that region.

**What the compiler generates**

For (%Digit as digit) * 4, the codegen would emit two things:

1. Main regex — the repetition wrapped in an indexed group so hasIndices (d flag, already in use) gives you the span of the whole repeated region, not just the last capture:   
   ((?<digit>\d){4})   with d flag
1. The outer group tells you the repetition spans e.g. indices [3, 7]. The inner digit capture is discarded (it only has the last value anyway).
2. Sub-regex — compiled from just the repeated unit, run with g flag against the extracted substring:                                                                           
   (?<digit>\d)   with g flag
2. Applied to input.slice(3, 7) → four matches → ["1","2","3","4"].

**When it gets harder**

- Multiple captures per iteration: (%Digit as d %Alpha as c) * 3 — the sub-regex covers the whole repeated unit and each g-match yields both d and c. Each iteration produces   
  one entry per capture, so the result is parallel arrays: {d: ["1","2","3"], c: ["a","b","c"]}.
- Alternation inside repetition: ('a' as x | 'b' as y) * 3 — some iterations match x, others y. You'd need to decide whether absent captures in a given iteration are null      
  entries in the array, or whether the arrays have different lengths. This case needs a design decision before implementation.
- Nested repetitions: ((%Digit as a) * 2) * 3 — each pass level needs its own sub-regex and its own span group. The result for a would naturally be a nested array:
  [["1","2"],["3","4"],["5","6"]]. Whether that's worth supporting is a separate question.

**What this does NOT require**

The two-pass approach is purely a codegen/runtime concern — it doesn't need the AST at match time. So it's independent of !substitutable. The compiler just needs to recognize  
"this named capture is inside a repetition" and emit the extra span group + store the sub-regex alongside the main one.

**Main practical risk**

The span group approach assumes the repetition's matched region is contiguous and that the sub-regex re-matches the exact same substrings the main regex did. This holds for    
greedy matching (the default), but could produce surprising results if the sub-pattern is ambiguous. Worth noting as a known limitation.
                  