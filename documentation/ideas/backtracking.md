# Ptern Backtracking Avoidance — Ideas and Trade-offs

This document captures a trail of thinking about detecting and preventing catastrophic
backtracking in Ptern patterns. Nothing here is a decision; it is a reference for future
planning.

---

## Background

Ptern compiles to JavaScript NFA-based regex, which means exponential backtracking is
possible for ambiguous patterns. The engine backtracks by trying alternative parse paths
when a match fails, and for certain pattern shapes the number of paths grows exponentially
with input length.

**Dangerous constructs:**

- Nested repetitions where the inner bound is variable.
- Alternation branches that overlap (one is a prefix of another).
- Two consecutive variable-length repetitions over overlapping character classes.

**Concrete growth rates:**

- Two-alternative overlapping pattern in a bounded repetition: Fibonacci growth (φ^n ≈
  1.618^n). Catastrophic threshold: bound ≈ 35–40 on typical hardware.
- Three-alternative overlapping pattern: tribonacci growth. Threshold drops to ≈ 25–30.
- Character classes (`%Digit`, `%Alpha`, etc.) are atomic and always safe — the NFA never
  needs to backtrack within a single character class match.

---

## The target: ambiguity, not just catastrophe

The useful framing is not "will this time out?" but "does this pattern have a unique parse
for every input?" A pattern is **ambiguous** if there exists any string that the engine
could match in more than one way. Ambiguity always indicates unclear intent and is often
the root cause of backtracking disasters. Ptern can enforce non-ambiguity as a structural
property — catching careless patterns long before they become catastrophic.

---

## Proposed checks

### 1. Alternation prefix-overlap detection

For `A | B`, verify that no string can be a prefix match of both A and B.

Two branches overlap if:

- One is a literal prefix of the other: `'abc' | 'abcd'` (the engine can match `'abc'`
  then fail on continuation, backtrack to try `'abcd'`).
- Both start with the same char class: `%Digit %Alpha | %Digit %Digit` — the `%Digit` at
  the front means both branches are always attempted.
- One branch is a sub-case of the other: `'0'..'9' | %Digit`.

**Rule:** Emit `SemanticError(AmbiguousAlternation)` when branch prefixes overlap. For
literal/literal and literal/range this is computable exactly. For char-class/char-class
it is a set-intersection check. For mixed sequences, checking the first token of each
branch (depth 1) is already sufficient to reject.

This is a strict rule — it rejects some patterns a human might write with full awareness
— but it is exactly right for a "legible patterns" library. Ambiguous alternation is the
primary source of both unclear intent and backtracking.

### 2. Repetition body ambiguity

A repetition `P * n..m` is safe if and only if P cannot match the same input in more than
one way **and** no two consecutive repetitions of P can "share" input.

Two sub-checks:

**2a. Self-ambiguous body.** If P is itself an alternation or contains one, check that
P's own branches are non-overlapping (the check from §1 applies recursively).
`(%Digit | %Digit) * 3` is trivially self-ambiguous.

**2b. Adjacency ambiguity.** Two consecutive copies of P can share input when P can match
strings of different lengths that are prefixes of each other. The canonical dangerous
case: `(%Alpha * 1..? | 'x') * 4` — on input `"xxxx"` the engine can split across
iterations in exponentially many ways.

**Rule:** If P's match length is not fixed, and P's body contains alternation or optional
elements, reject the repetition. This rules out `(%Alpha | '') * 5`,
`('a' | 'ab') * 10`, and `(%Digit * 1..? | 'x') * 4` — all ambiguous or
adjacent-ambiguous.

A fixed-length P is always safe regardless of iteration count: `(%Digit %Alpha) * 100`
— each iteration consumes exactly 2 chars, no overlap possible.

### 3. Nested repetition

`(P * a..b) * c..d` is almost always ambiguous unless the inner repetition is fixed
(`a == b`). Even `(%Digit * 2..3) * 2` is ambiguous on `"12345"` — is it `(12)(345)` or
`(123)(45)`?

**Rule:** Nested bounded repetition where the inner bound is not exact is a
`SemanticError(AmbiguousNestedRepetition)`.

The one safe exception: the outer repetition is fixed and the inner length is fixed.
`(%Digit * 2) * 3` always consumes exactly 6 chars. Both bounds must be exact.

### 4. Adjacent same-class unbounded sequences

`%Digit * 1..? %Digit * 1..?` — the engine cannot determine where the first repetition
ends and the second begins without backtracking over the entire string.

**Rule:** Two consecutive repetitions `A * a..? B * b..?` (or bounded with large upper)
where A and B accept any common string → `SemanticError(AmbiguousAdjacentRepetition)`.

For char classes this is a set-intersection check at the AST level. Most real
adjacent-repetition patterns involve different char classes (`%Alpha * 1..? %Digit * 1..?`)
which are disjoint and therefore safe.

### 5. Bound-sensitive graduated response

For patterns that are structurally ambiguous but where the degree of hazard depends on
the bound:

- **Any ambiguity + fixed small bound (≤ 5):** Warn (not error). The pattern may be
  intentionally approximate and fast in practice.
- **Any ambiguity + bound > ~20:** Hard error. Exponential growth is dangerous on
  realistic inputs.
- **Unbounded (`* 1..?`) + any ambiguity:** Always a hard error. No bound caps the
  growth.

Even bound-5 ambiguous patterns indicate unclear intent and should surface a warning,
giving the author the chance to rewrite. Only a user opting in (see §7) keeps such a
pattern without modification.

### 6. The safe structural subset

Patterns guaranteed to be backtracking-free:

- Sequences of fixed-length elements (literals, fixed-count repetitions, single char
  classes).
- Alternation whose first token is distinct across all branches (LL(1)-style).
- Repetitions of fixed-length bodies.
- Repetitions of variable-length bodies where the body's char classes are disjoint from
  each other at each alternation point.

`CompiledPtern` could carry a boolean `is_unambiguous: Bool` so downstream tooling can
rely on this guarantee.

### 7. Opt-out annotation

For users who understand what they are writing — complex lookahead patterns,
performance-tested cases — a single annotation bypasses the checks:

```
!allow-backtracking = true
```

This is intentionally verbose. It is not `!fast = false` or `!safe = false`; it
explicitly names the risk. The annotation is recorded in `CompiledPtern` so runtimes can
log or monitor it. Any pattern carrying this annotation is excluded from the
`is_unambiguous` guarantee.

---

## Implementation path

The checks belong in a new semantic pass, `semantic/backtracking.gleam`, running after
the existing validator and resolver. It operates on the resolved AST and emits
`SemanticError` variants added to `error.gleam`:

```gleam
AmbiguousAlternation(branch_a: String, branch_b: String)
AmbiguousRepetitionBody(reason: String)
AmbiguousNestedRepetition
AmbiguousAdjacentRepetition
```

The pass is skipped entirely when `!allow-backtracking = true` is set.

A small `CharClassSet` type (bit-set over ASCII + Unicode category flags) in
`src/semantic/char_class.gleam` would make intersection tests cheap and exact. The
existing validator already walks the AST in one accumulating fold; the backtracking pass
can share that infrastructure.

---

## Priority summary

| Check                              | Difficulty | Value                                     |
|------------------------------------|------------|-------------------------------------------|
| Alternation prefix overlap         | Medium     | High — catches most careless patterns     |
| Adjacent same-class unbounded      | Low        | High — trivially dangerous                |
| Nested non-fixed repetition        | Low        | High — almost always a mistake            |
| Repetition body alternation overlap| Medium     | High — the ReDoS root cause               |
| Graduated warnings by bound        | Low        | Medium — softens strictness               |
| `!allow-backtracking` opt-out      | Low        | Essential escape hatch                    |
