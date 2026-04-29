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
- Alternation *inside a variable-length repetition* where branches overlap such that the
  engine cannot determine where one iteration ends and the next begins.
- Two consecutive variable-length repetitions over overlapping character classes.

**Constructs that are fine:**

- Alternation with shared prefixes outside any repetition: `'yes' | 'yep' | 'yeah'` tries
  each branch a bounded number of times. Backtracking is linear in the number of branches
  and the length of the overlap — not catastrophic.
- Alternation inside a *fixed* repetition: the number of paths is bounded by a constant
  known at compile time (see §2 for the qualification).

**Concrete growth rates for the dangerous cases:**

- Two-alternative overlapping adjacency inside an unbounded repetition: Fibonacci growth
  (φ^n ≈ 1.618^n). Catastrophic threshold: depth ≈ 35–40 on typical hardware.
- Three-alternative overlapping adjacency: tribonacci growth. Threshold drops to ≈ 25–30.
- Character classes (`%Digit`, `%Alpha`, etc.) are atomic — the NFA never backtracks
  within a single character class match.

**The design stance:** Ptern reports compilation errors for patterns that can produce
catastrophic (super-linear) backtracking. It does not flag minor or bounded backtracking,
because eliminating every shared prefix would make the language less readable for no
practical benefit. The goal is to block ReDoS, not to enforce theoretical LL(1) purity.

---

## The target: catastrophic ambiguity, not all ambiguity

A pattern is **catastrophically ambiguous** if there exists a string for which the number
of parse paths the engine must explore grows super-linearly (exponentially or worse) with
input length. This is the condition that causes ReDoS.

**Benign ambiguity** — where the engine tries a few branches and moves on — is acceptable.
`'yes' | 'yep' | 'yeah'` is ambiguous in the formal sense (the engine explores `'ye'`
twice) but never catastrophic. Even `'y' | 'yes' | 'yep' | 'yea' | 'aye'` — which has
suffix-prefix overlaps between branches — is benign inside a repetition because no input
string has two valid factorizations. Ptern allows this class of pattern.

The checks below target only catastrophic ambiguity. The outcome of compilation is always
either success (the compiled pattern) or a hard error. There are no warnings.

---

## Proposed checks

### 1. Adjacency ambiguity inside variable repetitions

This is the primary ReDoS source. The pattern `(A | B) * 1..?` is catastrophic when the
engine can partition some input string into branches in more than one way — exponentially
many partitions exist for long inputs, and when the overall match fails the engine must
exhaust all of them.

The root condition is: **a suffix of one branch is also expressible as a sequence of
branch matches** starting from the same position. If such a suffix exists, the engine can
"re-split" a previously consumed prefix and find a different factorization, leading to
exponential blowup.

**The canonical catastrophic case:** `('a' | 'aa') * 1..?`. The suffix `'a'` of `'aa'`
is itself a branch. On input `"aaaa"` the engine can split as `"a"+"a"+"a"+"a"`,
`"aa"+"a"+"a"`, `"a"+"aa"+"a"`, `"a"+"a"+"aa"`, `"aa"+"aa"` — Fibonacci-many
factorizations. Catastrophic.

**A clean safe case:** `('yes' | 'yep' | 'yeah') * 1..?`. Proper suffixes of every
branch (`'es'`, `'s'`; `'ep'`, `'p'`; `'eah'`, `'ah'`, `'h'`) share no character with
any branch prefix (`'y'`, `'ye'`, `'yea'`). No suffix can begin a branch, so no
re-splitting is possible.

**A trickier case:** `('y' | 'yes' | 'yep' | 'yea' | 'aye') * 1..?`. The suffix `'ye'`
of `'aye'` is a proper prefix of `'yes'`, `'yep'`, `'yea'` — so a naive suffix-prefix
intersection check flags this. Yet no input string has two valid factorizations: `'ye'`
alone is not a branch and `'ay'` is not a branch, so `'aye'` cannot be split into a
prefix that is itself a sequence of branches. The pattern is benign.

The suffix-prefix intersection check is therefore **sound but not tight**: it catches
true catastrophic cases but also rejects benign patterns where the overlapping suffix is
not itself reachable as a branch sequence. A tighter criterion is **unique decodability**
in the Sardinas-Patterson sense: the alternation language is catastrophically ambiguous
inside a repetition if and only if the language's self-concatenation contains an
ambiguous factorization — equivalently, if the Sardinas-Patterson dangling-suffix
iteration reaches the empty string.

**Rule (conservative):** Inside a variable-length repetition, if any proper suffix of a
branch is a proper prefix of any branch (including itself), reject with
`CompileError(AmbiguousRepetitionAdjacency)`. This correctly blocks all catastrophic
cases and also blocks some benign ones (see TODO below).

For literal branches the check is exact string comparison. For branches ending or starting
with char classes, use set intersection on the character sets: if the terminal character
set of one branch intersects the leading character set of another, treat the overlap as
present and reject.

*Implementation note:* The check requires computing a *leading token set* and *terminal
token set* for each AST node. This composes straightforwardly for sequences and char
classes but needs care for nullable elements: the effective terminal set of `P * 0..1`
is `terminal(P) ∪ leading(following_element)` because P may match nothing. A small
`nullable/1`, `first/1`, `last/1` recursion over the AST — analogous to the classic
nullable/first/follow sets from parser theory — is the natural approach.

**Decision:** Ptern uses the conservative check. The Sardinas-Patterson algorithm would
be more precise but adds substantial complexity — especially once char-class branches are
involved — and the benefit (accepting a narrow class of benign-but-overlapping patterns)
does not justify that cost at this stage.

The trade-off is that some genuinely safe patterns, such as
`('y' | 'yes' | 'yep' | 'yea' | 'aye') * 1..?`, will be rejected. Users who need such
patterns must add `!allow-backtracking = true`. This limitation must be called out
explicitly in user-facing documentation: the error message for
`AmbiguousRepetitionAdjacency` should explain that the check is conservative and direct
users to the opt-out annotation, and the user guide should include an example of a
rejected-but-safe pattern alongside the workaround.

### 2. Repetition body self-ambiguity

A repetition body can be catastrophic even without top-level alternation, if the body
itself has variable length and contains overlapping sub-patterns that create adjacency
ambiguity across iterations.

**Safe case — fixed-length body.** A body whose match length is fixed is always safe
regardless of iteration count: `(%Digit %Alpha) * 100` consumes exactly 2 chars per
iteration; `(%Digit | %Alpha) * 100` consumes exactly 1 char per iteration (single-char
alternation is also fixed-length). No overlap is possible.

**Unsafe case — variable-length body with internal overlap.**
`(%Alpha * 1..? | 'x') * 4` contains a variable-length sub-pattern whose iterations can
consume different amounts of input, making iteration boundaries ambiguous.

**Rule:** Reject `P * a..b` when P is variable-length and P's body fails the
suffix-prefix overlap check from §1 at iteration boundaries. A fixed outer bound does
not exempt a variable-length body from the check — only a fixed-length body is
unconditionally safe regardless of iteration count.

### 3. Nested repetition with variable inner bound

`(P * a..b) * c..d` is almost always catastrophically ambiguous unless the inner
repetition is fixed (`a == b`). Even `(%Digit * 2..3) * 2` is ambiguous on `"12345"` —
is it `(12)(345)` or `(123)(45)`?

**Rule:** Nested bounded repetition where the inner bound is not exact is a hard
`CompileError(AmbiguousNestedRepetition)`.

The one safe exception: both bounds are exact. `(%Digit * 2) * 3` always consumes exactly
6 chars.

### 4. Adjacent same-class unbounded sequences

`%Digit * 1..? %Digit * 1..?` — the engine cannot determine where the first repetition
ends and the second begins, producing O(n²) or worse backtracking.

**Rule:** Two consecutive repetitions `A * a..? B * b..?` where A and B accept any common
string → `CompileError(AmbiguousAdjacentRepetition)`.

For char classes this is a set-intersection check. Most real adjacent-repetition patterns
involve different char classes (`%Alpha * 1..? %Digit * 1..?`), which are disjoint and
safe.

### 5. Backreferences and subpattern interpolation

Interpolating a subpattern by name — `{ identifier }` — inside a repetition body
substitutes the resolved AST of the subpattern at that point. The backtracking checks must
operate on the *resolved* body, not the reference site, to catch hazards introduced by the
referenced definition.

**Decision:** The backtracking pass runs after name resolution and sub-pattern
substitution. By that point every `{ identifier }` reference has been replaced by its
inlined AST, so the pass sees a fully concrete tree with no references remaining. Each
reference site is checked independently in its local context — a subpattern that is safe
at the top level may be dangerous inside a variable-length repetition, and the pass will
catch this because it sees the inlined body at the repetition site rather than checking
the definition in isolation.

### 6. Safe structural subset

Patterns guaranteed to be safe (no catastrophic backtracking):

- Sequences of fixed-length elements (literals, fixed-count repetitions, single char
  classes).
- Alternation anywhere, *provided* it is not inside a variable-length repetition body
  with suffix-prefix overlap between branches.
- Repetitions of fixed-length bodies, regardless of branch count.
- Repetitions of variable-length bodies where no suffix of any alternative is a prefix of
  another alternative at iteration boundaries.
- Adjacent repetitions over disjoint char classes.

`CompiledPtern` could carry a boolean `is_backtracking_safe: Bool` so downstream tooling
can rely on this guarantee. (Named `is_backtracking_safe` rather than `is_unambiguous`
because Ptern intentionally allows benign ambiguity; the flag records the absence of
*catastrophic* ambiguity only.)

### 7. Opt-out annotation

For users who understand what they are writing — complex lookahead patterns,
performance-tested cases — a single annotation bypasses all checks:

```
!allow-backtracking = true
```

This is intentionally verbose. It is not `!fast = false` or `!safe = false`; it
explicitly names the risk. The annotation is recorded in `CompiledPtern` so runtimes can
log or monitor it. Any pattern carrying this annotation is excluded from the
`is_backtracking_safe` guarantee.

**Decision:** `!allow-backtracking = true` is top-level only and exempts the entire
pattern. Subexpression scope is not supported.

---

## Implementation path

The checks belong in a new semantic pass, `semantic/backtracking.gleam`, running after
the existing validator and resolver. It operates on the resolved AST and emits
`CompileError` variants added to `error.gleam`:

```gleam
AmbiguousRepetitionAdjacency(branch_a: String, branch_b: String)
AmbiguousRepetitionBody(reason: String)
AmbiguousNestedRepetition
AmbiguousAdjacentRepetition
```

The pass is skipped entirely when `!allow-backtracking = true` is set.

A small `CharClassSet` type (bit-set over ASCII + Unicode category flags) in
`src/semantic/char_class.gleam` would make intersection tests cheap and exact. The
existing validator already walks the AST in one accumulating fold; the backtracking pass
can share that infrastructure.

*Implementation note:* The bit-set covers named char classes and ASCII directly, but
custom ranges (`'a'..'z'`) need explicit handling. Reasonable options are a sorted
interval list, full-Unicode bit-set expansion, or treating non-ASCII ranges as
conservatively overlapping everything.

---

## Priority summary

| Check                                        | Difficulty | Value                                        |
|----------------------------------------------|------------|----------------------------------------------|
| Adjacency overlap inside variable repetition | Medium     | High — the primary ReDoS root cause          |
| Adjacent same-class unbounded sequences      | Low        | High — trivially dangerous                   |
| Nested non-fixed repetition                  | Low        | High — almost always a mistake               |
| Repetition body self-ambiguity               | Medium     | High — catches subtler variable-body cases   |
| `!allow-backtracking` opt-out                | Low        | Essential escape hatch                       |

**Open TODOs before implementation can begin:**

None.
