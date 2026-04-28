# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Ptern** is a Gleam library (JavaScript target) that compiles a readable pattern language (called "pterns") into regular expressions. The goal is to provide an alternative to regex that is far more readable while preserving the power of pattern matching, capturing, replacement, and substitution.

The public API of a compiled ptern (the `Ptern` interface in `index.ts`) includes:
- Boolean tests: `matchesAllOf()`, `matchesStartOf()`, `matchesEndOf()`, `matchesIn()`
- Occurrence queries: `matchAllOf()`, `matchStartOf()`, `matchEndOf()`, `matchFirstIn()`, `matchNextIn(startIndex)`, `matchAllIn()` — return `MatchOccurrence | null` (or `MatchOccurrence[]`), where `MatchOccurrence` carries `index`, `length`, and `captures`
- Replacements: `replaceAllOf(replacements)`, `replaceStartOf(replacements)`, `replaceEndOf(replacements)`, `replaceFirstIn(replacements)`, `replaceNextIn(startIndex, replacements)`, `replaceAllIn(replacements)` — take a `Record<string, string | string[]>` replacements dict, return the modified string (or the original if no match)
- Substitution: `substitute(captures)` — assembles a string from capture values without an original input string; requires `!substitutable = true`
- Metadata: `maxLength()`, `minLength()`

All internal regexes use the JavaScript `d` flag (`hasIndices`) to resolve per-capture positions precisely for replacement. The `v` flag (Unicode sets mode) is always set.

## Commands

```sh
# Run from the ptern-gleam/ subdirectory:
gleam build          # Build the Gleam library to ptern-gleam/build/dev/javascript/
gleam test           # Run all Gleam tests
gleam check          # Type-check without building
gleam add <package>  # Add a dependency

# Run from the repo root:
bun index.ts         # Run the TypeScript wrapper (requires gleam build first)
```

The Gleam project targets JavaScript only (`target = "javascript"` in `ptern-gleam/gleam.toml`) and runs on Bun.

## Project Structure

- `ptern-gleam/` — Gleam implementation (self-contained Gleam project)
  - `src/ptern.gleam` — library entry point; exposes `compile/1` and all public types
  - `src/ptern_ffi.mjs` — JavaScript FFI for regex execution and replacement patching
  - `src/regex.gleam` — Gleam wrappers around the FFI regex functions
  - `src/bounds.gleam` — min/max length computation
  - `src/lexer/` — tokeniser
  - `src/parser/` — parser producing an AST (`parser/ast.gleam`)
  - `src/semantic/` — `validator.gleam` (constraint checks), `resolver.gleam` (name resolution), `error.gleam` (error types)
  - `src/codegen/` — `codegen.gleam` (orchestration), `regex.gleam` (regex emission with `RepetitionInfo`), `substitution.gleam` (substitution plan builder)
  - `test/ptern_test.gleam` — gleeunit entry point (`main()` only)
  - `test/api/` — API-level tests: `match_test.gleam`, `replace_test.gleam`, `substitute_test.gleam`, `examples_test.gleam`
  - `test/semantic/` — `validator_test.gleam`, `resolver_test.gleam`
  - `test/codegen/` — `codegen_test.gleam`
  - `gleam.toml` — Gleam project manifest
  - `build/` — generated JavaScript output (gitignored)
- `index.ts` — TypeScript public API: `ptern` tagged template literal, `compile()`, and the `Ptern` interface
- `documentation/` — language documentation
  - `ptern-specification.md` — full formal language specification (grammar, semantics, all operations)
  - `user-guide.md` — quick-reference tables, operator summary, and worked examples

## Ptern Language

Full specification: `documentation/ptern-specification.md`. Key constructs:

- **Literals**: `'xyz'` or `"abc"` — literal text
- **Character class**: `%Digit`, `%Alpha`, `%Alnum`, `%L`, `%N`, `%Any`, etc.
- **Character range**: `'a'..'z'` — one character in the inclusive range
- **Set difference**: `%Alpha excluding 'q'`
- **Sequence**: `<ptern1> <ptern2>` — mandatory space enforces readability
- **Alternatives**: `<ptern1> | <ptern2>`
- **Fixed repetition**: `<ptern> * 3`
- **Bounded repetition**: `<ptern> * 3..10` or `<ptern> * 1..?` (unbounded)
- **Grouping**: `( <ptern> )`
- **Named capture**: `<ptern> as <identifier>` — the same name may appear at multiple positions; the same replacement/substitution value applies to every occurrence
- **Subpattern definition**: `identifier = <ptern> ;`
- **Subpattern interpolation / backreference**: `{ identifier }`
- **Position assertions**: `@word-start`, `@word-end`, `@line-start`, `@line-end`
- **Annotations**: `!case-insensitive`, `!multiline`, `!replacements-ignore-matching`, `!substitutable`, `!substitutions-ignore-matching`

Operator precedence (tightest to loosest): `()`, `{}`, `..`, `excluding`, `*`, `as`, sequence (space), `|`

## Key Implementation Details

**Replacement** works by patching per-capture index spans (from the `d` flag) directly into the match text. Captures inside repetitions use a two-pass approach: the main regex wraps the repetition in a synthetic `__rep_N` named group; a sub-regex is then run within that span to extract per-iteration spans. The `__rep_N` names are internal and are filtered out of all user-facing match results.

**Substitution** uses a compile-time substitution plan built from the AST, evaluated at runtime against a captures dict. Requires `!substitutable = true`.

**Duplicate capture names** are intentionally allowed. The compiler suppresses duplicate named groups in the main regex (only the first occurrence gets `(?<name>...)`) so JavaScript's `v`-mode regex accepts the pattern. Replacement and substitution apply the same value to every occurrence.

**Gleam public types** (in `src/ptern.gleam`):
- `CompileError` — `LexError | ParseError | SemanticErrors`
- `MatchOccurrence` — `{ index, length, captures: Dict(String, String) }`
- `ReplacementValue` — `ScalarReplacement(String) | ArrayReplacement(List(String))`
- `ReplacementError` — `InvalidReplacementValue | WrongReplacementType | ArrayLengthMismatch | DuplicateRepetitionCapture`
- `SubstitutionError` — `NotSubstitutable | MissingCapture | CaptureMismatch | WrongCaptureType | ArrayLengthError | NoMatchingBranch`
