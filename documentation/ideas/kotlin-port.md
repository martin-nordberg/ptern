# Ptern Kotlin Port — Implementation Plan

**Status:** Draft  
**Date:** 2026-06-02

---

## 1. Goals and Constraints

- Full, standalone Kotlin implementation of the Ptern compiler and runtime.
  The Gleam edition remains canonical; Kotlin is a peer port, not a wrapper.
- Targets the JVM (Kotlin/JVM). Kotlin/Native and Kotlin/JS are out of scope.
- Zero runtime dependencies. Build and test tooling may use third-party libraries
  (Gradle plugins, JUnit 5, Jackson for fixture parsing) as test/build scope only.
- **Java-callable API**: all public types carry the annotations and structural
  conventions needed for clean use from Java, Scala, Groovy, or other JVM languages
  without Kotlin knowledge. See §5.
- Source structure mirrors the Gleam and TypeScript editions (same module names,
  same pass ordering, same AST shapes) so that fixes and language features can be
  ported mechanically across implementations.
- Test cases are driven by the shared JSON fixture corpus at `test-fixtures/`,
  identical to the TypeScript driver.

---

## 2. Strategy: What Differs from the TypeScript Plan

The Kotlin port follows the same Option A (full rewrite per language) strategy and
shared-fixture consistency model from `multi-language.md`. The key differences from
the TypeScript edition are:

### 2.1 Compiler pipeline — identical in logic

Lexer, parser, semantic validator, resolver, backtracking checker, bounds computation,
and substitution plan builder translate directly from TypeScript to Kotlin with only
syntactic changes. No design decisions are needed for these passes.

### 2.2 Codegen — different regex dialect

The JVM regex dialect differs from JavaScript in three specific ways, all isolated to
`codegen/RegexEmitter.kt`:

1. **Set-difference syntax** — `[A--B]` (JS `v` mode) becomes `[A&&[^B]]` in Java
   regex.
2. **No `v` flag** — The JVM regex engine has no Unicode-sets mode. Unicode property
   classes (`\p{L}`, `\p{Lu}`, etc.) work natively without any special flag.
3. **No `d` flag** — `Matcher.start(String)` / `Matcher.end(String)` provide
   per-named-capture spans directly, replacing the `hasIndices` approach.

Everything else in codegen (named group wrapping, backreference syntax, substitution
plan building, flag mapping) has a direct JVM equivalent.

### 2.3 Runtime replacement — simpler than JS/TS

For non-repetition captures, `Matcher.start("name")` / `Matcher.end("name")` replace
the `d`-flag mechanism entirely. Repetition captures still require the two-pass
approach (`__rep_N`-style synthetic groups), but note that **Java named group names
may not contain underscores** — see §3.8.

### 2.4 Kotlin language advantages

Kotlin's sealed classes, data classes, nullable types, and companion objects express
Ptern's ADT-heavy codebase more naturally than Java. The public API is also cleaner
to write and read while remaining fully Java-callable.

---

## 3. JVM Regex — Full Difference Table

All JVM regex differences are identical to what a Java port would need, since Kotlin
uses `java.util.regex` directly.

### 3.1 Flags

| JS flag | Meaning | JVM equivalent |
|---------|---------|----------------|
| `v` | Unicode sets mode | Not needed — `\p{...}` works natively |
| `d` | `hasIndices` — per-group spans | Not needed — `Matcher.start/end(String)` |
| `i` | Case-insensitive | `Pattern.CASE_INSENSITIVE or Pattern.UNICODE_CASE` |
| `m` | Multiline | `Pattern.MULTILINE` |

The Kotlin codegen emits a `Set<RegexOption>` (Kotlin stdlib) or a plain `Int` flag
mask. `Regex(pattern, options)` wraps the `Pattern` object.

### 3.2 Set Difference (`excluding`)

| Ptern | JS `v` mode | JVM |
|-------|------------|-----|
| `%Alpha excluding 'q'` | `[\p{Alpha}--[q]]` | `[\p{Alpha}&&[^q]]` |
| `'a'..'z' excluding ('a'\|'e'\|'i'\|'o'\|'u')` | `[a-z--[aeiou]]` | `[a-z&&[^aeiou]]` |

Rule: `[A--B]` → `[A&&[^B]]`. When the right-hand side is a flat union group
`(C1 | C2 | C3)`, the members are placed directly inside the negated class:
`[A&&[^C1C2C3]]`.

### 3.3 `%Any`

Both JS and JVM codegen emit `[\s\S]`. No change.

### 3.4 POSIX Character Classes

These are ASCII-only per the spec and compile identically across editions:

| Ptern | Emitted |
|-------|---------|
| `%Digit` | `[0-9]` |
| `%Alpha` | `[A-Za-z]` |
| `%Alnum` | `[A-Za-z0-9]` |
| `%Upper` | `[A-Z]` |
| `%Lower` | `[a-z]` |
| `%Word` | `[A-Za-z0-9_]` |
| `%Xdigit` | `[0-9A-Fa-f]` |
| `%Space` | `[ \t\n\r\f]` |
| `%Blank` | `[ \t]` |
| `%Ascii` | `[\x00-\x7F]` |
| `%Cntrl` | `[\x00-\x1F\x7F]` |
| `%Graph` | `[\x21-\x7E]` |
| `%Print` | `[\x20-\x7E]` |
| `%Punct` | `[!"#$%&'()*+,\-./:;<=>?@\[\\\]^_{|}~]` |

### 3.5 Unicode Category Classes

Both JS (`v` mode) and JVM use `\p{...}` for Unicode property classes. Identical
across editions. Example: `%L` → `\p{L}`, `%Lu` → `\p{Lu}`.

### 3.6 Named Groups and Backreferences

Both JVM (Java 7+) and JavaScript use `(?<name>...)` for named capturing groups and
`\k<name>` for named backreferences. No change needed.

### 3.7 Position Assertions

| Ptern | Emitted (both JS and JVM) |
|-------|--------------------------|
| `@word-start` | `(?<!\w)(?=\w)` |
| `@word-end` | `(?<=\w)(?!\w)` |
| `@line-start` | `^` (with `MULTILINE` flag) |
| `@line-end` | `$` (with `MULTILINE` flag) |

### 3.8 Anchoring (`matchesAllOf` etc.)

Use `\A` and `\z` (absolute start/end of input, unaffected by `MULTILINE`) when
anchoring for `matchesAllOf`, `matchesStartOf`, `matchesEndOf`. This prevents the
active multiline flag from interfering with string-level anchoring. When
`!multiline = true`, use `^`/`$` line anchors instead for these operations (as the
spec requires: §9.1).

### 3.9 Synthetic Repetition Group Names

**Important JVM constraint:** Java named group names must match `[A-Za-z][A-Za-z0-9]*`
— underscores are not allowed. The `__rep_0`, `__rep_1` names used in the JS/TS
edition are invalid in JVM regex.

Use `rep0`, `rep1`, … instead. These are filtered from user-facing match results by
membership in the known set of emitted synthetic group names (stored in
`CompiledPtern.syntheticGroupNames`), not by a name-prefix heuristic.

---

## 4. Repository Layout

```
ptern/
  ptern-gleam/          (existing, unchanged)
  ptern-typescript/     (existing, unchanged)
  ptern-kotlin/         (new)
  test-fixtures/        (existing shared corpus)
  documentation/
    ptern-specification.md
    ideas/
      typescript-port.md
      multi-language.md
      kotlin-port.md        (this file)
```

### 4.1 `ptern-kotlin/` internals

```
ptern-kotlin/
  src/
    main/kotlin/io/ptern/
      lexer/
        Token.kt                 (sealed class LexError; data class Token; enum TokenKind)
        Lexer.kt                 (fun lex(source: String): List<Token>)
      parser/
        ast/
          ParsedPtern.kt
          Expression.kt          (sealed class Expression + all variants)
          Atom.kt                (sealed class Atom + all variants)
          RepUpper.kt            (sealed class RepUpper)
          Annotation.kt
          Definition.kt
        TokenStream.kt
        ParseError.kt            (sealed class ParseError)
        Parser.kt                (fun parse(tokens: List<Token>): ParsedPtern)
      semantic/
        SemanticError.kt         (sealed class SemanticError + all variants)
        Validator.kt
        Resolver.kt
        BacktrackingChecker.kt
        Bounds.kt                (fun computeBounds(parsed: ParsedPtern): BoundsResult)
      codegen/
        RepetitionInfo.kt        (data class)
        SubstitutionPlan.kt      (sealed class)
        CompiledPtern.kt         (internal data class)
        RegexEmitter.kt          (JVM-dialect-specific — the key difference)
        SubstitutionPlanBuilder.kt
        Codegen.kt               (fun compile(parsed: ParsedPtern): CompiledPtern)
      runtime/
        MatchResult.kt           (internal data class)
        ReplaceOutcome.kt        (internal sealed class)
        Replacer.kt
      formatter/
        FormatOptions.kt         (data class)
        FormatError.kt           (sealed class)
        Formatter.kt
      Ptern.kt                   (public class — the main entry point)
      MatchOccurrence.kt         (public data class)
      ReplacementValue.kt        (public sealed class)
      CompileError.kt            (public sealed class)
      ReplacementError.kt        (public sealed class)
      SubstitutionError.kt       (public sealed class)
      Errors.kt                  (PternCompileError, PternReplacementError, PternSubstitutionError)
  src/
    test/kotlin/io/ptern/
      fixture/
        FixtureDriver.kt         (JUnit 5 parameterized fixture runner)
      api/
        MatchTest.kt
        ReplaceTest.kt
        SubstituteTest.kt
        FormatTest.kt
        ExamplesTest.kt
      internal/
        LexerTest.kt
        ParserTest.kt
        ValidatorTest.kt
        ResolverTest.kt
        CodegenTest.kt
  build.gradle.kts
  settings.gradle.kts
  .gitignore
```

---

## 5. Public API

### 5.1 `Ptern` class

```kotlin
class Ptern private constructor(private val compiled: CompiledPtern, ...) {

    companion object {
        @JvmStatic fun compile(source: String): Ptern { ... }
    }

    // Boolean tests
    fun matchesAllOf(input: String): Boolean
    fun matchesStartOf(input: String): Boolean
    fun matchesEndOf(input: String): Boolean
    fun matchesIn(input: String): Boolean

    // Occurrence queries — nullable return (T? maps to @Nullable T in Java)
    fun matchAllOf(input: String): MatchOccurrence?
    fun matchStartOf(input: String): MatchOccurrence?
    fun matchEndOf(input: String): MatchOccurrence?
    fun matchFirstIn(input: String): MatchOccurrence?
    fun matchNextIn(input: String, startIndex: Int): MatchOccurrence?
    fun matchAllIn(input: String): List<MatchOccurrence>

    // Replacement — throws PternReplacementError on validation failure
    fun replaceAllOf(input: String, replacements: Map<String, ReplacementValue>): String
    fun replaceStartOf(input: String, replacements: Map<String, ReplacementValue>): String
    fun replaceEndOf(input: String, replacements: Map<String, ReplacementValue>): String
    fun replaceFirstIn(input: String, replacements: Map<String, ReplacementValue>): String
    fun replaceNextIn(input: String, startIndex: Int, replacements: Map<String, ReplacementValue>): String
    fun replaceAllIn(input: String, replacements: Map<String, ReplacementValue>): String

    // Substitution — throws PternSubstitutionError
    fun substitute(captures: Map<String, ReplacementValue>): String

    // Metadata
    val minLength: Int
    val maxLength: Int?   // null means unbounded; maps to @Nullable Integer in Java
}
```

`@JvmStatic` on `compile` means Java callers write `Ptern.compile(source)` rather
than `Ptern.Companion.compile(source)`.

Nullable return types (`MatchOccurrence?`, `Int?`) surface as `@Nullable` in Java.
Java callers use null-checks or `Objects.requireNonNull`; no `Optional` wrapping is
needed at the API layer.

### 5.2 `MatchOccurrence`

```kotlin
data class MatchOccurrence(
    val index: Int,
    val length: Int,
    val captures: Map<String, String>   // unmodifiable
)
```

`data class` gives Java callers `equals`, `hashCode`, `toString`, and component
accessor methods for free.

### 5.3 `ReplacementValue`

```kotlin
sealed class ReplacementValue {
    data class Scalar(val value: String) : ReplacementValue()
    data class Array(val values: List<String>) : ReplacementValue()

    companion object {
        @JvmStatic fun of(value: String): ReplacementValue = Scalar(value)
        @JvmStatic fun ofArray(vararg values: String): ReplacementValue = Array(values.toList())
        @JvmStatic fun ofArray(values: List<String>): ReplacementValue = Array(values.toList())
    }
}
```

`ofArray` uses a distinct name instead of overloading `of`, avoiding vararg ambiguity
from Java (where `of(String)` and `of(String...)` would be ambiguous at the call site).

### 5.4 Error types

All errors use unchecked exceptions (consistent with the TypeScript edition). The
exception classes carry a typed payload for programmatic inspection.

```kotlin
// Compile errors
class PternCompileError(val compileError: CompileError)
    : RuntimeException(compileError.toString())

sealed class CompileError {
    data class LexError(val error: io.ptern.lexer.LexError) : CompileError()
    data class ParseError(val error: io.ptern.parser.ParseError) : CompileError()
    data class SemanticErrors(val errors: List<SemanticError>) : CompileError()
}

// Replacement errors
class PternReplacementError(val replacementError: ReplacementError)
    : RuntimeException(replacementError.toString())

sealed class ReplacementError {
    data class InvalidReplacementValue(val name: String, val value: String) : ReplacementError()
    data class WrongReplacementType(val name: String) : ReplacementError()
    data class ArrayLengthMismatch(val name: String, val provided: Int, val actual: Int) : ReplacementError()
    data class DuplicateRepetitionCapture(val name: String) : ReplacementError()
}

// Substitution errors
class PternSubstitutionError(val substitutionError: SubstitutionError)
    : RuntimeException(substitutionError.toString())

sealed class SubstitutionError {
    object NotSubstitutable : SubstitutionError()
    data class MissingCapture(val name: String) : SubstitutionError()
    data class CaptureMismatch(val name: String, val value: String) : SubstitutionError()
    data class ArrayLengthError(val name: String, val length: Int, val min: Int, val max: Int) : SubstitutionError()
    object NoMatchingBranch : SubstitutionError()
}
```

`sealed class` hierarchies in Kotlin are fully accessible from Java via `instanceof`
and cast; Kotlin's `when` exhaustiveness does not help Java callers but they can use
`if`/`instanceof` chains.

### 5.5 Formatter

```kotlin
object Formatter {
    @JvmStatic @JvmOverloads
    fun format(source: String, options: FormatOptions = FormatOptions()): String
}

data class FormatOptions(
    val lineWidth: Int = 80,
    val compact: Boolean = false,
    val aligned: Boolean = true,
    val reordered: Boolean = false
)
```

`@JvmOverloads` generates Java-callable overloads for each trailing-default
combination, so Java callers can write `Formatter.format(source)` without supplying
all four options.

`Formatter` as a Kotlin `object` exposes static-style methods. `@JvmStatic` makes
`Formatter.format(...)` work from Java without `.INSTANCE`.

### 5.6 Naming

Gleam `snake_case` / TypeScript `camelCase` → Kotlin `camelCase` (identical mapping):
`matches_all_of` → `matchesAllOf`, `match_first_in` → `matchFirstIn`, etc.

---

## 6. AST Types

Kotlin sealed classes replace Gleam custom types and TypeScript discriminated unions.
The mapping is direct and natural:

```kotlin
// Gleam: pub type RepUpper { Exact(Int) | Unbounded | None }
sealed class RepUpper {
    data class Exact(val value: Int) : RepUpper()
    object Unbounded : RepUpper()
    object None : RepUpper()
}

// Gleam: pub type Atom { Literal(String) | CharClass(String) | ... }
sealed class Atom {
    data class Literal(val content: String) : Atom()
    data class CharClass(val name: String) : Atom()
    data class Interpolation(val name: String) : Atom()
    data class Group(val inner: Expression) : Atom()
    data class PositionAssertion(val name: String) : Atom()
}
```

Leaf variants with no fields use `object`; variants with fields use `data class`.
All sealed class hierarchies map 1:1 to the TypeScript AST shapes.

---

## 7. Compile Pipeline

Mirrors the Gleam and TypeScript pipelines exactly:

```
Ptern.compile(source: String): Ptern
  1. Lexer.lex(source)                      → List<Token>
  2. Parser.parse(tokens)                   → ParsedPtern
  3. Validator.validate(parsed)             → List<SemanticError>
  4. Resolver.resolve(parsed)               → List<SemanticError>
  5. BacktrackingChecker.check(parsed)      → List<SemanticError>
     filter DuplicateCapture from combined errors
     if errors remain → throw PternCompileError
  6. Codegen.compile(parsed)                → CompiledPtern
  7. Bounds.computeBounds(parsed)           → BoundsResult
  8. Construct Ptern from CompiledPtern + BoundsResult
```

### 7.1 `CompiledPtern` (internal)

```kotlin
internal data class CompiledPtern(
    val source: String,
    val flags: Set<RegexOption>,          // Kotlin stdlib; wraps Pattern flags
    val ignoreMatching: Boolean,
    val captureValidators: List<Pair<String, String>>,
    val isSubstitutable: Boolean,
    val ignoreSubstitutionMatching: Boolean,
    val substitutionPlan: SubstitutionPlan?,
    val repetitionInfo: List<RepetitionInfo>,
    val syntheticGroupNames: Set<String>  // e.g. {"rep0", "rep1"} — filtered from results
)
```

`syntheticGroupNames` is the explicit set of internally emitted group names that must
be excluded from user-facing match results, replacing the prefix-heuristic used in
JS/TS.

---

## 8. Runtime Replacement

### 8.1 Span extraction (non-repetition captures)

```kotlin
val start = matcher.start("name")
val end   = matcher.end("name")
```

This replaces the `d`-flag / `match.indices.groups` mechanism from JS/TS entirely.

### 8.2 Repetition captures (two-pass)

The main regex wraps each repetition in a synthetic `(?<repN>...)` group. A secondary
`Regex` compiled from the repetition body runs on the extracted span to recover
per-iteration capture positions. The logic is a direct translation from TypeScript.

### 8.3 `matchAllIn` and zero-width match guard

`matchAllIn` loops `matcher.find()`. When a match has length 0 (e.g. from a
position-assertion-only pattern), the next call uses `matcher.find(matcher.start()+1)`
to advance past the zero-width position — identical guard to the TypeScript edition.

---

## 9. Java Interop Summary

This section collects all Kotlin annotations and conventions required for clean Java
usage.

| Concern | Kotlin declaration | Java-visible effect |
|---------|--------------------|---------------------|
| Factory method on companion | `@JvmStatic fun compile(...)` | `Ptern.compile(...)` (not `Ptern.Companion.compile(...)`) |
| Default parameter overloads | `@JvmOverloads` on `format(source, options = ...)` | Overloads for each trailing default |
| Singleton `object` methods | `@JvmStatic` | Static call syntax |
| Nullable return types | `T?` + `@Nullable` annotation | Java sees `@Nullable T`; null-check as usual |
| `Int?` for `maxLength` | `@Nullable Integer` in Java | Null-safe null-check or boxed |
| `data class` | — | `equals`, `hashCode`, `toString`, accessor methods |
| `sealed class` | — | `instanceof` / cast patterns in Java |
| `List`, `Map` | Kotlin stdlib collections | Java `List`, `Map` (same interfaces) |
| `ReplacementValue.of` naming | `of(String)`, `ofArray(String...)` | No vararg/overload ambiguity from Java |

Kotlin properties (`val minLength: Int`, `val maxLength: Int?`) compile to Java
getter methods (`getMinLength()`, `getMaxLength()`). This is standard Kotlin/Java
interop; no extra annotations are needed.

---

## 10. Build Tooling

### 10.1 `build.gradle.kts`

```kotlin
plugins {
    kotlin("jvm") version "2.1.0"
    `java-library`
}

group = "io.ptern"
version = "0.1.0"

kotlin {
    jvmToolchain(21)
}

dependencies {
    // No runtime dependencies

    testImplementation(platform("org.junit:junit-bom:5.11.0"))
    testImplementation("org.junit.jupiter:junit-jupiter")
    testRuntimeOnly("org.junit.platform:junit-platform-launcher")
    testImplementation("com.fasterxml.jackson.core:jackson-databind:2.17.0")
}

tasks.test {
    useJUnitPlatform()
}
```

### 10.2 Running tests

```sh
# From ptern-kotlin/:
./gradlew test                                    # run all tests
./gradlew test --tests "io.ptern.api.*"           # run a package
./gradlew test --continuous                       # re-run on file changes
```

---

## 11. Shared Test Fixtures

The Kotlin edition consumes the same `test-fixtures/` corpus as TypeScript without
modification. The JUnit 5 fixture driver uses `@ParameterizedTest` with
`@MethodSource` and Jackson to parse fixture JSON:

```kotlin
class FixtureDriver {

    @ParameterizedTest(name = "{0}")
    @MethodSource("allFixtureCases")
    fun fixtureCase(id: String, case: FixtureCase) {
        // dispatch on case.op and assert case.expect
    }

    companion object {
        @JvmStatic fun allFixtureCases(): Stream<Arguments> {
            // walk test-fixtures/**/*.json, deserialise each case
        }
    }
}
```

Jackson is a test-scope dependency only; the published library has no runtime
dependencies.

---

## 12. Work Breakdown

### Phase 1 — Foundation

1. Create `ptern-kotlin/` skeleton (`build.gradle.kts`, `settings.gradle.kts`,
   package structure).
2. Port `lexer/Token.kt`, `lexer/Lexer.kt`. Add `LexerTest.kt`.
3. Port `parser/ast/` sealed hierarchy, `parser/Parser.kt`. Add `ParserTest.kt`.
4. Port `semantic/SemanticError.kt`, `semantic/Validator.kt`,
   `semantic/Resolver.kt`. Add `ValidatorTest.kt`, `ResolverTest.kt`.

### Phase 2 — Codegen

5. Port `codegen/RegexEmitter.kt` — the **JVM-dialect-specific** pass. Implement
   `[A&&[^B]]` set-difference, JVM flag mapping, `\A`/`\z` anchoring, and `repN`
   synthetic group naming. Verify against `test-fixtures/codegen/codegen.json`.
6. Port `codegen/SubstitutionPlanBuilder.kt`.
7. Port `codegen/Codegen.kt` (orchestration).
8. Port `semantic/BacktrackingChecker.kt` and `semantic/Bounds.kt`.

### Phase 3 — Runtime

9. Port `runtime/Replacer.kt` from `ptern_ffi.mjs` / `runtime/replace.ts`. Use
   `Matcher.start/end("name")` for non-repetition span extraction.
10. Assemble `Ptern.kt` (public class, all methods). Apply Java interop annotations.

### Phase 4 — Tests and Fixtures

11. Write `fixture/FixtureDriver.kt` (parameterised JUnit 5 runner).
12. Write API tests in `test/kotlin/io/ptern/api/`.
13. Write internal unit tests for lexer, parser, validator, resolver, codegen.

### Phase 5 — Formatter and Documentation

14. Port `formatter/Formatter.kt`.
15. Write `documentation/kotlin-user-guide.md`.
16. Write `ptern-kotlin/README.md`.
17. Update `ptern-specification.md` §1.3 to reference the Kotlin user guide.

---

## 13. Open Questions and TODOs

| ID | Area | Question | Default / Options |
|----|------|----------|-------------------|
| ~~TODO-1~~ | Kotlin version | ~~**Which Kotlin version?**~~ — resolved: Kotlin 2.1, no experimental features. | |
| ~~TODO-2~~ | JVM target | ~~**JVM bytecode target version?**~~ — resolved: JVM 21 minimum; `jvmToolchain(21)`. | |
| ~~TODO-3~~ | Package namespace | ~~**`io.ptern` vs `com.ptern`?**~~ — resolved: `io.ptern`. | |
| ~~TODO-4~~ | Test framework | ~~**JUnit 5 only, or also Kotest?**~~ — resolved: JUnit 5 only. | |
| ~~TODO-5~~ | `@Nullable` source | ~~**Which `@Nullable` annotation?**~~ — resolved: `org.jetbrains.annotations.Nullable` (compile scope). | |
| ~~TODO-6~~ | `@Nullable` on properties | ~~**Annotate Kotlin nullable properties for Java?**~~ — resolved: rely on automatic generation from `org.jetbrains:annotations` on the compile classpath; add explicit `@Nullable` only for `maxLength` in the public API. | |
| ~~TODO-7~~ | `!case-insensitive` Unicode | ~~**`CASE_INSENSITIVE` alone or combined with `UNICODE_CASE`?**~~ — resolved: `RegexOption.IGNORE_CASE` (wraps both flags in Kotlin stdlib). | |
| ~~TODO-8~~ | `%Any` codegen | ~~**`[\s\S]` or `(?s:.)`?**~~ — resolved: `[\s\S]`. | |
| ~~TODO-9~~ | `UNICODE_CHARACTER_CLASS` flag | ~~**Apply `Pattern.UNICODE_CHARACTER_CLASS` globally?**~~ — resolved: omit; Ptern's codegen never emits `\d`/`\w`/`\s`. | |
| ~~TODO-10~~ | `matchAllIn` empty-match guard | ~~**Confirm zero-width match behaviour matches TypeScript?**~~ — resolved: carry the bump-by-1 guard; verify against shared fixtures. | |
| ~~TODO-11~~ | Synthetic group name filter | ~~**Use `syntheticGroupNames: Set<String>` on `CompiledPtern`, or a naming convention?**~~ — resolved: explicit `syntheticGroupNames: Set<String>` in `CompiledPtern`; no naming convention. | |
| ~~TODO-12~~ | Formatter parity | ~~**Include formatter in initial release?**~~ — resolved: yes, include in Phase 5. | |
| ~~TODO-13~~ | Coroutines | ~~**Should any API be suspendable?**~~ — resolved: synchronous only, no `suspend` functions. | |
| ~~TODO-14~~ | Kotlin multiplatform | ~~**Kotlin/Native or Kotlin/JS future?**~~ — resolved: out of scope; note in README. | |
| ~~TODO-15~~ | Maven coordinates | ~~**Artifact ID for Maven Central?**~~ — resolved: `io.ptern:ptern-kotlin`. | |
| ~~TODO-16~~ | Backreference syntax | ~~**Confirm `\k<name>` works in `java.util.regex`?**~~ — resolved: use `\k<name>`; add a fixture test covering backreferences (e.g. HTML tag matching example) in Phase 2. | |

---

## 14. Differences from TypeScript Port (Summary)

| Concern | TypeScript | Kotlin |
|---------|-----------|--------|
| Set-difference regex syntax | `[A--B]` (JS `v` mode) | `[A&&[^B]]` (JVM) |
| Span extraction | `d` flag + `match.indices.groups` | `Matcher.start/end("name")` |
| Compiled pattern type | `RegExp` | `java.util.regex.Pattern` (via `kotlin.text.Regex`) |
| Flag representation | flag string (`"vim"`) | `Set<RegexOption>` |
| Absent match return type | `null` | `null` (Kotlin `T?`, `@Nullable T` to Java) |
| Union types | TypeScript discriminated unions | Kotlin sealed classes + data classes |
| Error handling | `throw` (unchecked by convention) | `throw RuntimeException` subclasses |
| Synthetic group naming | `__rep_0`, `__rep_1` | `rep0`, `rep1` (underscores invalid in JVM named groups) |
| Zero-match guard in `matchAllIn` | bump offset by 1 | `matcher.find(start + 1)` |
| Build tool | Bun | Gradle (Kotlin DSL) |
| Test framework | `bun:test` | JUnit 5 |
| JSON for fixtures | native `JSON.parse` | Jackson (test scope) |
| Package distribution | npm (`@ptern/tern`) | Maven Central (`io.ptern:ptern-kotlin`) |
| Java callability | N/A | `@JvmStatic`, `@JvmOverloads` on all entry points |
