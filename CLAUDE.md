# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Ptern** is a Gleam library (JavaScript target) that compiles a readable pattern language (called "pterns") into regular expressions via tagged template literals. The goal is to provide an alternative to regex that is far more readable while preserving the power of pattern matching, capturing, and metadata queries.

The public API of a compiled ptern (the `Ptern` interface in `index.ts`) includes:
- Boolean tests: `matchesAllOf()`, `matchesStartOf()`, `matchesEndOf()`, `matchesIn()`
- Occurrence queries: `matchAllOf()`, `matchStartOf()`, `matchEndOf()`, `matchFirstIn()`, `matchNextIn(startIndex)`, `matchAllIn()` — return `MatchOccurrence | null` (or `MatchOccurrence[]`), where `MatchOccurrence` carries `index`, `length`, and `captures`
- Replacements: `replaceAllOf(replacements)`, `replaceStartOf(replacements)`, `replaceEndOf(replacements)`, `replaceFirstIn(replacements)`, `replaceNextIn(startIndex, replacements)`, `replaceAllIn(replacements)` — take a `MatchResult`-shaped replacements dict, return the modified string (or the original if no match)
- Metadata: `maxLength()`, `minLength()`

Replace operations use the JavaScript `d` flag (`hasIndices`) on all internal regexes to resolve per-capture positions precisely.

## Commands

```sh
# Run from the ptern-gleam/ subdirectory:
gleam build          # Build the Gleam library to ptern-gleam/build/dev/javascript/
gleam test           # Run all Gleam tests
gleam run            # Run src/ptern.gleam main
gleam check          # Type-check without building
gleam add <package>  # Add a dependency

# Run from the repo root:
bun index.ts         # Run the TypeScript wrapper (requires gleam build first)
```

The Gleam project targets JavaScript only (`target = "javascript"` in `ptern-gleam/gleam.toml`) and runs on Bun.

## Project Structure

- `ptern-gleam/` — Gleam implementation (self-contained Gleam project)
  - `src/ptern.gleam` — library entry point; exposes `compile/1`
  - `src/lexer/`, `src/parser/`, `src/semantic/`, `src/codegen/` — pipeline stages
  - `test/` — gleeunit test suite
  - `gleam.toml` — Gleam project manifest
  - `build/` — generated JavaScript output (gitignored)
- `index.ts` — TypeScript public API: `ptern` tagged template literal, `compile()`, and the `Ptern` interface; loads compiled output from `ptern-gleam/build/`

## Ptern Language

The language has a defined grammar (see README.md for full syntax reference):

- **Literals**: `'xyz'` or `"abc"` — literal text
- **Character class range**: `'a'..'z'` — one character in the inclusive range
- **Unicode/POSIX classes**: `%Digit`, `%Alpha`, `%Alnum`, `%L`, `%N`, `%Any`, etc.
- **Sequence**: `<ptern1> <ptern2>` — space between is required (enforces readability)
- **Alternatives**: `<ptern1> | <ptern2>`
- **Fixed repetition**: `<ptern> * 3`
- **Bounded repetition**: `<ptern> * 3..10`
- **Grouping**: `( <ptern> )`
- **Named capture**: `<ptern> as <identifier>`
- **Set difference**: `%IDENTIFIER excluding <ptern>`
- **Named subpattern definition**: `identifier = <ptern> ;`
- **Subpattern interpolation**: `{ identifier }`

Operator precedence (highest to lowest): `()`, `{}`, `..`, `excluding`, `*`, `as`, sequence (space), `|`, `=`
