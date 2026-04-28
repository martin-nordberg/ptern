# Ptern Multi-Language Strategy — Ideas and Trade-offs

This document captures a trail of thinking about extending Ptern beyond its current
JavaScript/TypeScript target. Nothing here is a decision; it is a reference for future
planning.

---

## 1. Target language survey

### BEAM / Erlang

Gleam already compiles to Erlang/BEAM in addition to JavaScript, so a BEAM target could
reuse the existing Gleam source for the lexer, parser, semantic passes, codegen, and
substitution evaluator. The blockers are at the FFI layer:

- **`v` flag (Unicode sets mode)** — JavaScript-specific. Erlang uses PCRE, which has no
  equivalent. Set-difference (`[A--B]`) would need a different codegen backend emitting
  PCRE-compatible syntax (e.g. `[A&&[^B]]` or lookahead negation).
- **`d` flag (hasIndices)** — JavaScript-specific. Erlang's `re:run/3` with
  `{capture, all, index}` provides equivalent span data but through a different API.
- **Named captures** — work differently; the FFI replacement machinery would need a full
  rewrite in Erlang.

A second codegen backend (`codegen/regex_erlang.gleam`) plus an `ptern_ffi.erl` wrapping
`re` would be a self-contained chunk of work. The lexer, parser, AST, semantic passes, and
bounds computation are pure Gleam and require no changes.

**Verdict:** Achievable but non-trivial. Only worth doing with a concrete BEAM use case.

### Java / Kotlin

There is no Gleam-to-JVM target, so this would be a full reimplementation rather than a
new backend. The good news is that Java's `java.util.regex` is a better fit than PCRE:

- Named groups use the same `(?<name>...)` syntax.
- `Matcher.start("name")` / `Matcher.end("name")` provide per-capture spans natively,
  replacing the JavaScript `d` flag entirely.
- Unicode properties (`\p{L}` etc.) are supported.
- Set-difference: `[A--B]` becomes `[A&&[^B]]` in Java character classes — a codegen
  change only.

The implication: a Java codegen backend would emit slightly different regex syntax, but the
runtime replacement and substitution logic would be natural Java.

### Python

Python's `re` module uses a different named-group API (`match.group("name")`,
`match.span("name")`), which again provides span data natively. Unicode property support
requires the third-party `regex` library rather than the stdlib `re` module. Otherwise the
runtime porting story is similar to Java.

---

## 2. Architecture options for multi-language support

### Option A — Full rewrite per language

Rewrite the entire compiler pipeline (lexer, parser, semantic analysis, codegen) in each
target language. Each implementation is self-contained.

**Pros:** single language per codebase, standard packaging in each ecosystem, no
cross-language tooling required.

**Cons:** every bug fix and language feature must be applied N times; implementations drift
in edge-case behaviour; the hard correctness-sensitive parts (semantic validation, codegen)
are duplicated.

### Option B — Gleam core + thin language wrappers (current approach, extended)

Keep the Gleam implementation as the canonical compiler. Each target language implements
only the runtime layer (regex execution, replacement patching, substitution evaluation)
against a compiled output.

The Gleam `CompiledPtern` output already contains everything a runtime needs:
- `source` — regex pattern string
- `flags` — regex flags
- `capture_validators` — per-capture validator patterns
- `substitution_plan` — the substitution tree (a simple recursive ADT)
- `repetition_info` — repetition metadata for two-pass replacement

Serialising this to a **JSON IR** decouples compilation from execution:

```
ptern source string
        │
        ▼
   Gleam compiler
        │
        ▼
   JSON IR (regex, flags, plan, validators, rep_info)
        │
   ┌────┴────┐────────┐
   ▼         ▼        ▼
TypeScript  Java    Python
 runtime   runtime  runtime
```

Each language runtime is ~300–500 lines. The compiler — the hard, correctness-sensitive
part — is maintained once. New pattern language features propagate to all runtimes
automatically when the Gleam compiler is updated.

The Gleam CLI (or a WASM build of the Gleam compiler) can be used as a build-time tool that
pre-compiles patterns to JSON, or called at runtime via subprocess.

**Pros:** single source of behavioural truth; runtimes are thin and straightforward;
consistency is structural rather than a discipline.

**Cons:** introduces a cross-language build dependency; contributors touching the pattern
language need to know Gleam; Gleam's JS output includes runtime scaffolding that increases
package size.

---

## 3. AI assistance and codebase redundancy

The traditional objection to maintaining parallel codebases is primarily a *labour* argument:
bugs must be ported manually, features drift, context-switching between languages is
expensive. An AI code assistant substantially reduces all of these costs — "apply this fix to
the Java and Python versions" is a low-cost prompt.

What AI does *not* eliminate:

- **Correctness risk on porting.** The AI may miss a subtle invariant when translating, and
  a test suite that does not surface that edge case will not catch it.
- **Behavioural drift detection.** Three implementations can silently diverge even when all
  three pass their own tests. Verifying agreement requires explicit cross-language test
  coverage.
- **Authoritative ground truth.** Without a single canonical implementation, deciding which
  version is "correct" when they disagree is a human judgement call every time.

The shared-core (Option B) architecture therefore remains valuable even with AI assistance,
but the *reason* shifts: it is no longer primarily about saving maintenance labour. It is
about making correctness and consistency structural rather than something that must be
continuously re-verified.

---

## 4. Shared test fixtures across implementations

Every Ptern test case is pure data — a pattern string, an operation name, inputs, and an
expected output or error. A shared JSON fixture corpus means test content is written once
and executed identically by every language implementation.

### Fixture format

Files live in `test-fixtures/` at the repo root, organised by feature area.

```json
{
  "id": "iso_date_full_match",
  "pattern": "%Digit * 4 as year '-' %Digit * 2 as month '-' %Digit * 2 as day",
  "cases": [
    { "op": "matchesAllOf",  "input": "2026-04-28", "expect": true  },
    { "op": "matchesAllOf",  "input": "2026-4-28",  "expect": false },
    { "op": "matchFirstIn",  "input": "filed 2026-04-28",
      "expect": { "index": 6, "length": 10,
                  "captures": { "year": "2026", "month": "04", "day": "28" } } },
    { "op": "replaceFirstIn",
      "input":        "2026-04-28",
      "replacements": { "year": "2027" },
      "expect":       "2027-04-28" }
  ]
}
```

Errors use language-agnostic variant names:

```json
{ "op": "compile",
  "pattern": "!case-insensitive = true\n!case-insensitive = true\n'x'",
  "expect": { "error": "DuplicateAnnotation", "name": "case-insensitive" } }
```

Array replacements and substitution captures map directly to JSON arrays and objects.
Absent matches are represented as JSON `null`.

### Generating fixtures from the Gleam implementation

Rather than writing expected values by hand, a Gleam fixture driver reads each file, runs
every case, and writes the observed outputs back as the expected values. The Gleam
implementation becomes the authority for initial fixture generation. Other language CI then
runs the same files unchanged.

### What each language ships

- A small **test driver** (the only language-specific code) that loads fixture files, calls
  the language's own Ptern API for each case, and asserts the result matches.
- Its own small set of **language-specific unit tests** for internal concerns (memory layout,
  error type mapping, etc.) that cannot meaningfully be expressed as shared data.

The shared corpus covers the bulk of correctness testing; the language-specific tests cover
only implementation details that are invisible at the API boundary.

### What maps cleanly to JSON

Everything observable does: compile errors (variant name + fields), boolean results,
occurrence structs (`index`, `length`, `captures`), replacement outputs, substitution
outputs, all error variants for replacement and substitution. The only design choice is
representing `null`/`None` — JSON `null` is the natural uniform encoding.
