# Ptern TypeScript Port — Implementation Plan

**Status:** Draft  
**Date:** 2026-05-27

---

## 1. Goals and Constraints

- Full, standalone TypeScript implementation of the Ptern compiler and runtime.  
  The Gleam edition remains primary and canonical; TypeScript is a peer port, not
  a wrapper around Gleam's compiled JavaScript output.
- Works in Node.js (18+) and modern browsers without bundler modification.
- Zero runtime dependencies. Only `typescript` is a dev dependency.
- High-level source structure mirrors the Gleam edition (same module names, same pass
  ordering, same AST shapes) so that fixes and language features can be ported
  mechanically.
- Test cases are shared across language editions via a JSON fixture corpus so that
  correctness is verified consistently everywhere.

---

## 2. Decisions Made Up-Front

| Topic | Decision | Rationale |
|---|---|---|
| Full rewrite vs. thin wrapper | Full rewrite | Gleam's compiled JS output carries runtime scaffolding unsuitable for packaging as a TypeScript library. A clean TS source also lets users read and contribute to the compiler. |
| Shared test fixtures | Yes — JSON corpus at `test-fixtures/` | Fixtures guarantee identical behaviour across editions; the Gleam edition is the truth source for fixture generation. |
| Error handling style | All error conditions throw (`PternCompileError`, `PternReplacementError`, `PternSubstitutionError`) | Single, consistent model. No safe/Result-returning variant. |
| Module format | ESM only | CJS users are unlikely to adopt Ptern's paradigm shift. New work uses ESM; no CJS shim needed. |
| Build toolchain | Bun for development, testing, and building; `tsc` for type-checking and `.d.ts` generation | Bun runs TypeScript directly (no compile step to test), has a fast built-in bundler, and is already used by the Gleam edition. The distributed ESM output targets Node.js. |
| Formatter | Included (mirrors `formatter/formatter.gleam`) | Parity with Gleam edition. |

---

## 3. Repository Layout

```
ptern/
  ptern-gleam/          (existing, unchanged)
  ptern-typescript/     (new)
  test-fixtures/        (new — shared JSON corpus)
  documentation/
    ptern-specification.md
    ideas/
      typescript-port.md   (this file)
      multi-language.md
    typescript-user-guide.md   (new)
```

### 3.1 `ptern-typescript/` internals

```
ptern-typescript/
  src/
    lexer/
      token.ts          (Token union type, LexError type)
      lexer.ts          (lex() → Token[])
    parser/
      ast.ts            (ParsedPtern, Expression, ... AST types)
      stream.ts         (TokenStream helper)
      parser.ts         (parse() → ParsedPtern)
    semantic/
      error.ts          (SemanticError union type)
      validator.ts      (validate() → SemanticError[])
      resolver.ts       (resolve() → SemanticError[])
      backtracking.ts   (check() → SemanticError[])
      bounds.ts         (computeBounds() → { min, max })
    codegen/
      regex.ts          (emitRegex(), RepetitionInfo, flag determination)
      substitution.ts   (SubstitutionPlan type, buildPlan())
      codegen.ts        (compile() → CompiledPtern)
    runtime/
      replace.ts        (replacement patching; absorbs ptern_ffi.mjs logic)
    formatter/
      formatter.ts      (format() → string)
    index.ts            (public API; Ptern class + named exports)
  test/
    driver.test.ts      (JSON fixture runner — loads test-fixtures/**)
    api/
      match.test.ts
      replace.test.ts
      substitute.test.ts
      format.test.ts
    internal/
      lexer.test.ts
      parser.test.ts
      validator.test.ts
      resolver.test.ts
      codegen.test.ts
  dist/                 (generated; gitignored)
  package.json
  tsconfig.json
  tsconfig.build.json   (excludes test/ for distribution build)
```

---

## 4. Source Architecture

### 4.1 Compile pipeline

Exactly mirrors the Gleam pipeline:

```
compile(source: string): Ptern
  1. lex(source)            → Token[]          (lexer/lexer.ts)
  2. parse(tokens)          → ParsedPtern       (parser/parser.ts)
  3. validate(parsed)       → SemanticError[]   (semantic/validator.ts)
  4. resolve(parsed)        → SemanticError[]   (semantic/resolver.ts)
  5. check(parsed)          → SemanticError[]   (semantic/backtracking.ts)
     filter DuplicateCapture from combined list
     if errors remain → throw PternCompileError
  6. codegen.compile(parsed)→ CompiledPtern     (codegen/codegen.ts)
  7. computeBounds(parsed)  → { min, max }      (semantic/bounds.ts)
  8. Construct Ptern instance from compiled output
```

### 4.2 AST types (`src/parser/ast.ts`)

Direct TypeScript translation of `parser/ast.gleam`. Gleam custom types become
TypeScript discriminated unions:

```typescript
// Gleam: pub type RepUpper { Exact(Int) | Unbounded | None }
type RepUpper =
  | { kind: "exact"; value: number }
  | { kind: "unbounded" }
  | { kind: "none" };

// Gleam: pub type Atom { Literal(content) | CharClass(name) | ... }
type Atom =
  | { kind: "literal"; content: string }
  | { kind: "charClass"; name: string }
  | { kind: "interpolation"; name: string }
  | { kind: "group"; inner: Expression }
  | { kind: "positionAssertion"; name: string };
```

All other AST types follow this pattern. Names are camelCase (TypeScript convention)
but map 1:1 to the Gleam variants.

### 4.3 Token types (`src/lexer/token.ts`)

```typescript
type TokenKind =
  | "singleQuotedLiteral" | "doubleQuotedLiteral"
  | "characterClass" | "identifier" | "integer"
  | "positionAssertion"
  | "bang" | "asterisk" | "equals" | "semicolon"
  | "leftParen" | "rightParen" | "leftBrace" | "rightBrace"
  | "rangeOperator" | "questionMark" | "alternativeOperator"
  | "as" | "excluding" | "fewest" | "true" | "false"
  | "whitespace" | "comment";

type Token = { kind: TokenKind; value: string };

// Lex errors
type LexError =
  | { kind: "unexpectedCharacter"; char: string }
  | { kind: "unterminatedString" }
  | { kind: "inlineComment" };
```

### 4.4 SemanticError union (`src/semantic/error.ts`)

Every variant in `semantic/error.gleam` maps to a discriminated union member.
Names are camelCase. Example:

```typescript
type SemanticError =
  | { kind: "undefinedReference"; name: string }
  | { kind: "duplicateDefinition"; name: string }
  | { kind: "circularDefinition"; names: string[] }
  | { kind: "duplicateCapture"; name: string }
  | { kind: "invalidEscapeSequence"; seq: string }
  // ... all other variants
  ;
```

### 4.5 CompiledPtern (internal, `src/codegen/codegen.ts`)

```typescript
type RepetitionInfo = { groupName: string; subSource: string; captures: string[] };

type CompiledPtern = {
  source: string;
  flags: string;
  ignoreMatching: boolean;
  captureValidators: [string, string][];   // [captureName, fragment][]
  isSubstitutable: boolean;
  ignoreSubstitutionMatching: boolean;
  substitutionPlan: SubstitutionPlan | null;
  repetitionInfo: RepetitionInfo[];
};
```

### 4.6 Substitution plan (`src/codegen/substitution.ts`)

```typescript
type SubstitutionPlan =
  | { kind: "literal"; text: string }
  | { kind: "positionAssertion" }
  | { kind: "notEvaluable" }
  | { kind: "capture"; name: string; inner: SubstitutionPlan }
  | { kind: "sequence"; items: SubstitutionPlan[] }
  | { kind: "alternation"; branches: SubstitutionPlan[] }
  | { kind: "fixedRep"; inner: SubstitutionPlan; count: number }
  | { kind: "boundedRep"; inner: SubstitutionPlan; min: number; max: number | null };
```

### 4.7 Runtime replacement (`src/runtime/replace.ts`)

The JavaScript replacement logic currently living in `ptern_ffi.mjs` is ported
directly to TypeScript here. No FFI boundary is needed since TypeScript is the
runtime. The API surface is internal; the public `Ptern` class calls it.

Functions:
- `execRich(re: RegExp, input: string): MatchResult | null`
- `execFromRich(re: RegExp, input: string, startIndex: number): MatchResult | null`
- `execAllRich(re: RegExp, input: string): MatchResult[]`
- `replaceRichWithArrays(re, input, scalars, arrays, repInfo, flags): ReplaceOutcome`
- `replaceFromRichWithArrays(re, input, startIndex, scalars, arrays, repInfo, flags): ReplaceOutcome`
- `replaceAllRichWithArrays(re, input, scalars, arrays, repInfo, flags): ReplaceOutcome`

```typescript
type MatchResult = { index: number; length: number; captures: [string, string][] };
type ReplaceOutcome =
  | { ok: true; value: string }
  | { ok: false; mismatches: [name: string, provided: number, actual: number][] };
```

---

## 5. Public API (`src/index.ts`)

### 5.1 Types

```typescript
// Opaque compiled pattern — instances are created by compile()
export class Ptern { /* ... private constructor ... */ }

export type MatchOccurrence = {
  index: number;
  length: number;
  captures: Record<string, string>;
};

// Scalar string or per-iteration array
export type ReplacementValue = string | string[];
export type ReplacementMap = Record<string, ReplacementValue>;

export type FormatOptions = {
  lineWidth: number;  // default 80
  compact: boolean;   // default false
  aligned: boolean;   // default true
  reordered: boolean; // default false
};
```

### 5.2 Errors

```typescript
export class PternCompileError extends Error {
  readonly compileError: CompileError;
}
// CompileError is { kind: "lexError" | "parseError" | "semanticErrors", ... }

export class PternReplacementError extends Error {
  readonly replacementError: ReplacementError;
}
// ReplacementError mirrors Gleam's ReplacementError variants

export class PternSubstitutionError extends Error {
  readonly substitutionError: SubstitutionError;
}
// SubstitutionError mirrors Gleam's SubstitutionError variants
```

### 5.3 Top-level functions

```typescript
// Compile a ptern source string. Throws PternCompileError on failure.
export function compile(source: string): Ptern;

// Format a ptern source string. Throws PternCompileError (FormatError subtype) on failure.
export function format(source: string, options?: Partial<FormatOptions>): string;
```

### 5.4 Ptern class methods

```typescript
class Ptern {
  // Boolean tests
  matchesAllOf(input: string): boolean;
  matchesStartOf(input: string): boolean;
  matchesEndOf(input: string): boolean;
  matchesIn(input: string): boolean;

  // Occurrence queries
  matchAllOf(input: string): MatchOccurrence | null;
  matchStartOf(input: string): MatchOccurrence | null;
  matchEndOf(input: string): MatchOccurrence | null;
  matchFirstIn(input: string): MatchOccurrence | null;
  matchNextIn(input: string, startIndex: number): MatchOccurrence | null;
  matchAllIn(input: string): MatchOccurrence[];

  // Replacement — throw PternReplacementError on validation failure
  replaceAllOf(input: string, replacements: ReplacementMap): string;
  replaceStartOf(input: string, replacements: ReplacementMap): string;
  replaceEndOf(input: string, replacements: ReplacementMap): string;
  replaceFirstIn(input: string, replacements: ReplacementMap): string;
  replaceNextIn(input: string, startIndex: number, replacements: ReplacementMap): string;
  replaceAllIn(input: string, replacements: ReplacementMap): string;

  // Substitution — throws PternSubstitutionError
  substitute(captures: ReplacementMap): string;

  // Metadata
  get minLength(): number;
  get maxLength(): number | null;
}
```

**Naming notes:**
- Gleam uses `snake_case`; TypeScript API uses `camelCase` consistently.
- Method names translate directly: `matches_all_of` → `matchesAllOf`, etc.
- `ReplacementValue` is simplified from Gleam's union: a plain `string` is
  `ScalarReplacement`; a `string[]` is `ArrayReplacement`. The distinction is
  inferred from the runtime type rather than requiring an explicit tag.

### 5.5 Open questions / TBDs

All error conditions throw — no safe/Result-returning variant will be shipped.

All operations are synchronous. No async or Worker-based API will be provided.

---

## 6. Shared Test Fixtures

### 6.1 Location and structure

```
test-fixtures/
  api/
    match.json
    replace.json
    substitute.json
    examples.json
  semantic/
    validator.json
    resolver.json
    backtracking.json
  codegen/
    codegen.json
  lexer/
    lexer.json
  parser/
    parser.json
```

### 6.2 Fixture format (recap from `multi-language.md`)

Each file contains an array of fixture groups:

```json
[
  {
    "id": "iso_date_full_match",
    "pattern": "%Digit * 4 as year '-' %Digit * 2 as month '-' %Digit * 2 as day",
    "cases": [
      { "op": "matchesAllOf",  "input": "2026-04-28", "expect": true },
      { "op": "matchesAllOf",  "input": "2026-4-28",  "expect": false },
      { "op": "matchFirstIn",
        "input": "filed 2026-04-28",
        "expect": { "index": 6, "length": 10,
                    "captures": { "year": "2026", "month": "04", "day": "28" } }
      },
      { "op": "replaceFirstIn",
        "input":        "2026-04-28",
        "replacements": { "year": "2027" },
        "expect":       "2027-04-28"
      }
    ]
  }
]
```

Compile-error fixtures use the variant name as a string identifier:

```json
{ "op": "compile",
  "pattern": "!case-insensitive = true\n!case-insensitive = true\n'x'",
  "expect": { "error": "duplicateAnnotation", "name": "case-insensitive" } }
```

Absent matches are `null`. Substitution captures use the same `ReplacementMap`
shape (value is a string or an array of strings).

### 6.3 Codegen fixtures

Codegen-level tests verify the emitted regex string (and flags) for a given
ptern source, independent of runtime behaviour. This is the TypeScript analogue
of `codegen_test.gleam`:

```json
{ "id": "plain_literal",
  "pattern": "'hello'",
  "expect": { "source": "hello", "flags": "v" }
}
```

These fixtures are especially valuable because they verify the codegen is
identical between Gleam and TypeScript, not just that end-to-end behaviour
happens to agree.

### 6.4 Generating fixtures from the Gleam edition

A Gleam fixture-export tool (`ptern-gleam/src/fixtures/export.gleam`) runs
every current test case and writes the observed outputs to `test-fixtures/`.
This is a one-time bootstrap step; thereafter fixtures are maintained by hand
when new tests are added to either implementation.

Workflow:
1. Add a test to the Gleam test suite (the normal way).
2. Run `gleam run -m fixtures/export` to regenerate `test-fixtures/`.
3. The TypeScript fixture runner picks up the new case on next `bun test`.

**Fixture shapes for lexer and parser:**

Lexer fixtures include both success and error cases. A success case is a flat
array of `{ kind, value }` token objects; an error case names the variant plus
offending content:

```json
[
  { "id": "keyword_boundary",
    "input": "asset",
    "expect": [{ "kind": "identifier", "value": "asset" }]
  },
  { "id": "unterminated_string",
    "input": "'hello",
    "expect": { "error": "unterminatedString" }
  }
]
```

Parser fixtures cover error cases only. The AST is too deeply nested to serialise
robustly, and parse correctness on success is implicitly covered by the codegen
fixtures (a passing codegen fixture proves the parse was correct):

```json
[
  { "id": "unexpected_eof",
    "input": "'hello' |",
    "expect": { "error": "unexpectedEndOfInput" }
  },
  { "id": "orphaned_comment",
    "input": "# a comment\n\n'hello'",
    "expect": { "error": "orphanedComment" }
  }
]
```

The Gleam fixture exporter still needs to be built (Phase 3 work).

### 6.5 TypeScript fixture driver (`test/driver.test.ts`)

```typescript
import { describe, it, expect } from "bun:test";
import { compile } from "../src/index.js";

// Load all JSON fixture files and generate a test per case
```

The driver covers all operations in the fixture schema. Language-specific tests
(`test/api/`, `test/internal/`) cover things that cannot be expressed as JSON
fixture cases: TypeScript-specific error class properties, the exact shape of
thrown exceptions, etc.

---

## 7. Tooling and Build

### 7.1 `package.json`

```json
{
  "name": "@ptern/tern",
  "version": "0.1.0",
  "type": "module",
  "exports": {
    ".": "./dist/index.js"
  },
  "types": "./dist/index.d.ts",
  "files": ["dist/"],
  "scripts": {
    "build": "bun build src/index.ts --outdir dist --target node && tsc -p tsconfig.build.json --emitDeclarationOnly",
    "test": "bun test",
    "typecheck": "tsc --noEmit"
  },
  "devDependencies": {
    "typescript": "^5.8"
  }
}
```

Bun is used for bundling (`bun build`) to produce the distributable `dist/index.js`
targeting Node. `tsc --emitDeclarationOnly` produces `.d.ts` files alongside it.
No extra dev dependencies are required.

### 7.2 `tsconfig.json`

Used for type-checking (`bun typecheck`) and `.d.ts` emission (`tsconfig.build.json`).
Bun resolves TypeScript directly at runtime without invoking `tsc`.

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "Bundler",
    "moduleResolution": "Bundler",
    "strict": true,
    "exactOptionalPropertyTypes": true,
    "noUncheckedIndexedAccess": true,
    "declaration": true,
    "declarationMap": true,
    "noEmit": true
  },
  "include": ["src/**/*", "test/**/*"]
}
```

`tsconfig.build.json` overrides `noEmit: false`, sets `outDir: "dist"`, and
excludes `test/**/*`.

### 7.3 Running tests

```sh
# From ptern-typescript/:
bun test                  # runs all *.test.ts files directly — no compile step
bun test test/api/        # run a subtree
bun test --watch          # re-run on file changes
```

Bun executes TypeScript test files natively. Tests use `bun:test` imports
(`describe`, `it`, `expect`). No compilation step is needed to run the suite.

---

## 8. Documentation Changes

### 8.1 New: `documentation/typescript-user-guide.md`

Mirrors the structure of `ptern-gleam/doc/user-guide.md`, with TypeScript
code examples throughout. Sections:

1. A First Taste
2. Compiling Patterns
3. Boolean Tests
4. Occurrence Queries — `MatchOccurrence`, index/length/captures
5. Replacement — scalar vs. array, `!replacements-ignore-matching`
6. Substitution — `!substitutable`, `substitute()`
7. Subpattern Definitions and Interpolation
8. Character Classes — full table
9. Annotations Reference
10. Compile Errors — the `PternCompileError` exception, `compileError` payload
11. Replacement and Substitution Errors
12. Bounds — `minLength`, `maxLength`
13. Formatting — `format()`

All code examples use `import { compile } from "ptern"` and TypeScript types.
The user guide does **not** duplicate the language reference in
`ptern-specification.md`; it links to it instead.

### 8.2 New: `ptern-typescript/README.md`

Quick-start (10–20 lines), install instructions, one API example, link to
`documentation/typescript-user-guide.md`.

### 8.3 Updates to `documentation/ptern-specification.md`

- Add a note in §1.3 ("Scope") that the spec covers the Ptern source language
  and is language-agnostic; binding APIs are documented separately per edition.
- Add a reference to the TypeScript user guide alongside the Gleam user guide.

### 8.4 Updates to `documentation/ideas/multi-language.md`

Record that Option A (full rewrite per language) was chosen for TypeScript, that
shared JSON fixtures are the consistency mechanism, and that Option B (JSON IR)
remains on the table for future language ports where Gleam expertise is unavailable.

### 8.5 `ptern-gleam/doc/user-guide.md`

Retitle to `ptern-gleam/doc/user-guide.md` (already scoped to Gleam) and add a
header note pointing to the TypeScript user guide.

---

## 9. Work Breakdown

Rough phasing, not a strict sequence:

### Phase 1 — Foundation

1. Create `ptern-typescript/` skeleton (package.json, tsconfig, src/, test/).
2. Port `lexer/token.ts` and `lexer/lexer.ts`. Add internal lexer tests.
3. Port `parser/ast.ts`, `parser/stream.ts`, `parser/parser.ts`. Add parser tests.
4. Port `semantic/error.ts`, `semantic/validator.ts`, `semantic/resolver.ts`.
5. Port `codegen/regex.ts` and `codegen/codegen.ts` (regex emission, flag
   determination). Verify codegen output matches Gleam via `codegen.json` fixtures.

### Phase 2 — Runtime

6. Port `runtime/replace.ts` from `ptern_ffi.mjs`. This is a direct translation
   from JavaScript to TypeScript — the logic is unchanged.
7. Port `semantic/bounds.ts`.
8. Port `codegen/substitution.ts` and `semantic/backtracking.ts`.
9. Assemble `src/index.ts` (Ptern class, compile(), all methods).

### Phase 3 — Tests and Fixtures

10. Build `test-fixtures/` corpus: first write fixtures by hand for the core
    API tests (match, replace, substitute, examples), then add the Gleam
    fixture-export tooling for automated generation.
11. Write `test/driver.test.ts` (JSON fixture runner).
12. Add TypeScript-specific tests in `test/api/` for exception shapes,
    edge cases not captured in fixtures, browser-build smoke test.

### Phase 4 — Formatter and Documentation

13. Port `formatter/formatter.ts`.
14. Write `documentation/typescript-user-guide.md`.
15. Update `ptern-specification.md` and `multi-language.md` references.
16. Write `ptern-typescript/README.md`.

---

## 10. Open Questions and TBDs

| ID | Area | Question |
|---|---|---|
| ~~TBD-1~~ | Public API | ~~Safe API variant~~ — resolved: throwing-only, no safe variant. |
| ~~TBD-2~~ | Async | ~~Async/Worker API~~ — resolved: synchronous only. |
| ~~TBD-3~~ | Fixtures | ~~Lexer/parser fixture shape~~ — resolved: lexer uses `{ kind, value }[]` token arrays (success) + error variants; parser uses error cases only (success covered by codegen fixtures). |
| ~~TBD-4~~ | CJS build | ~~CJS output strategy~~ — resolved: ESM only, no CJS. |
| ~~TBD-5~~ | Test execution | ~~Test execution strategy~~ — resolved: `bun test` runs `.ts` files directly, no compile step. |
| ~~TBD-6~~ | Browser bundle | ~~Browser bundle~~ — resolved: ESM-only for now, no UMD/IIFE bundle. |
| ~~TBD-7~~ | Naming | ~~Package name~~ — resolved: `@ptern/tern`. |
| ~~TBD-8~~ | Versioning | ~~Version lock-step~~ — resolved: each edition tracks its own independent semver; the shared anchor is the spec version (`ptern-specification.md` §1). Each release documents which spec version it implements. A spec version bump is the trigger to update both editions before either is published claiming the new spec version. No mechanical enforcement — process only. |
| ~~TBD-9~~ | Fixture authority | ~~Fixture authority~~ — resolved: Gleam edition is authoritative; TypeScript must match. |
| ~~TBD-10~~ | Formatter parity | ~~Formatter parity~~ — resolved: full formatter parity required in the initial release. |
