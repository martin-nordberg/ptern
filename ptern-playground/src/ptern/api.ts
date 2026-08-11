// Typed wrapper around @ptern/tern (the ptern-typescript engine), consumed as
// a local Bun workspace dependency. This file is the seam between the engine
// and the rest of the playground — every other file imports only from here,
// and never touches @ptern/tern directly.

import {
  compile as pternCompile,
  format as pternFormat,
  PternCompileError,
  PternReplacementError,
  PternSubstitutionError,
  PternFormatError,
  type Ptern as EnginePtern,
  type ReplacementMap,
  type MatchOccurrence as EngineMatchOccurrence,
  type FormatOptions as EngineFormatOptions,
  type CompileError as EngineCompileError,
  type LexError as EngineLexError,
  type ParseError as EngineParseError,
  type SemanticError as EngineSemanticError,
  type ReplacementError as EngineReplacementError,
  type SubstitutionError as EngineSubstitutionError,
} from '@ptern/tern'

// ---------------------------------------------------------------------------
// Public types
// ---------------------------------------------------------------------------

export type Ptern = EnginePtern

export type CompileError =
  | { kind: 'lex'; message: string }
  | { kind: 'parse'; message: string }
  | { kind: 'semantic'; messages: string[] }

export type FormatOptions = EngineFormatOptions

export type MatchOccurrence = EngineMatchOccurrence

// Identical shape to @ptern/tern's own ReplacementMap — an alias, not a
// separate type, so captures pass straight through with no conversion.
export type CaptureInput = ReplacementMap

export type ReplacementError =
  | { kind: 'invalid'; captureName: string; value: string }
  | { kind: 'wrongType'; captureName: string }
  | { kind: 'lengthMismatch'; captureName: string; provided: number; actual: number }
  | { kind: 'duplicateRepetition'; captureName: string }

export type SubstitutionError =
  | { kind: 'notSubstitutable' }
  | { kind: 'missing'; name: string }
  | { kind: 'mismatch'; name: string }
  | { kind: 'lengthError'; name: string; length: number; min: number; max: number | null }
  | { kind: 'noMatchingBranch' }

// ---------------------------------------------------------------------------
// Error message formatting
// ---------------------------------------------------------------------------

function formatLexError(e: EngineLexError): string {
  switch (e.kind) {
    case 'unexpectedCharacter': return `Unexpected character '${e.char}'`
    case 'unterminatedString': return 'Unterminated string literal'
    case 'inlineComment': return 'Inline comments are not allowed'
  }
}

function formatParseError(e: EngineParseError): string {
  switch (e.kind) {
    case 'unexpectedToken': return `Unexpected token: expected ${e.expected}, got ${e.got}`
    case 'unexpectedEndOfInput': return 'Unexpected end of input'
    case 'orphanedComment': return 'Comment must be immediately followed by an annotation, definition, or body expression'
    case 'trailingComment': return 'Comments cannot appear after the body expression'
  }
}

function formatSemanticError(e: EngineSemanticError): string {
  switch (e.kind) {
    case 'undefinedReference': return `Undefined reference: ${e.name}`
    case 'duplicateDefinition': return `Duplicate definition: ${e.name}`
    case 'circularDefinition': return `Circular definition: ${e.names.join(', ')}`
    case 'captureDefinitionConflict': return `Name used as both a capture and a definition: ${e.name}`
    case 'invalidRangeEndpoint': return `Invalid character range endpoint: '${e.content}'`
    case 'invertedRange': return `Inverted character range: '${e.from}'..'${e.to}'`
    case 'invertedRepetitionBounds': return `Inverted repetition bounds: ${e.min}..${e.max}`
    case 'invalidExclusionOperand': return 'Invalid operand for excluding'
    case 'unknownAnnotation': return `Unknown annotation: !${e.name}`
    case 'duplicateAnnotation': return `Duplicate annotation: !${e.name}`
    case 'invalidEscapeSequence': return `Invalid escape sequence: ${e.seq}`
    case 'unknownPositionAssertion': return `Unknown position assertion: @${e.name}`
    case 'positionAssertionInRepetition': return `Position assertion @${e.name} cannot appear inside a repetition`
    case 'substitutionsIgnoreMatchingWithoutSubstitutable': return '!substitutions-ignore-matching requires !substitutable'
    case 'notSubstitutableBody': return 'Pattern body is not substitutable'
    case 'boundedRepetitionNeedsCapture': return 'Bounded repetition inside substitutable pattern must have a capture'
    case 'emptyLiteral': return 'Empty string literal'
    case 'emptyCharacterSet': return 'Empty character set (excluding removes all characters)'
    case 'ambiguousRepetitionAdjacency': return 'Ambiguous: repetition adjacent to another repetition in an alternation'
    case 'ambiguousRepetitionBody': return 'Ambiguous: repetition body could match empty string'
    case 'ambiguousAdjacentRepetition': return 'Ambiguous: two repetitions are adjacent'
    case 'fewestOnExactRepetition': return '!fewest cannot be used on an exact repetition'
    case 'unusedDefinition': return `Unused definition: ${e.name}`
    default:
      // duplicateCapture — compile() already filters this out of the
      // semanticErrors list before it reaches user code, so in practice
      // this case never fires.
      return `Duplicate capture: ${e.name}`
  }
}

function convertReplacementError(e: EngineReplacementError): ReplacementError {
  switch (e.kind) {
    case 'invalidReplacementValue': return { kind: 'invalid', captureName: e.captureName, value: e.value }
    case 'wrongReplacementType': return { kind: 'wrongType', captureName: e.captureName }
    case 'arrayLengthMismatch': return { kind: 'lengthMismatch', captureName: e.captureName, provided: e.provided, actual: e.actual }
    case 'duplicateRepetitionCapture': return { kind: 'duplicateRepetition', captureName: e.captureName }
  }
}

function convertSubstitutionError(e: EngineSubstitutionError): SubstitutionError {
  switch (e.kind) {
    case 'notSubstitutable': return { kind: 'notSubstitutable' }
    case 'missingCapture': return { kind: 'missing', name: e.name }
    case 'captureMismatch': return { kind: 'mismatch', name: e.name }
    case 'arrayLengthError': return { kind: 'lengthError', name: e.name, length: e.length, min: e.min, max: e.max }
    case 'noMatchingBranch': return { kind: 'noMatchingBranch' }
  }
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

export function compilePtern(source: string): { ok: true; ptern: Ptern } | { ok: false; error: CompileError } {
  try {
    return { ok: true, ptern: pternCompile(source) }
  } catch (e) {
    if (!(e instanceof PternCompileError)) throw e
    return { ok: false, error: convertCompileError(e.compileError) }
  }
}

function convertCompileError(err: EngineCompileError): CompileError {
  switch (err.kind) {
    case 'lexError': return { kind: 'lex', message: formatLexError(err.error) }
    case 'parseError': return { kind: 'parse', message: formatParseError(err.error) }
    case 'semanticErrors': return { kind: 'semantic', messages: err.errors.map(formatSemanticError) }
  }
}

// @ptern/tern doesn't export its internal `defaultFormatOptions` constant
// (see ptern-typescript/doc/user-guide.md's "FormatOptions" section) — this
// mirrors it exactly.
export function getDefaultFormatOptions(): FormatOptions {
  return { lineWidth: 80, compact: false, aligned: true, reordered: false }
}

export function formatPtern(source: string, options: FormatOptions): string | null {
  try {
    return pternFormat(source, options)
  } catch (e) {
    if (!(e instanceof PternFormatError)) throw e
    return null
  }
}

export function matchesAllOf(ptern: Ptern, input: string): boolean { return ptern.matchesAllOf(input) }
export function matchesStartOf(ptern: Ptern, input: string): boolean { return ptern.matchesStartOf(input) }
export function matchesEndOf(ptern: Ptern, input: string): boolean { return ptern.matchesEndOf(input) }
export function matchesIn(ptern: Ptern, input: string): boolean { return ptern.matchesIn(input) }

export function matchAllOf(ptern: Ptern, input: string): MatchOccurrence | null { return ptern.matchAllOf(input) }
export function matchStartOf(ptern: Ptern, input: string): MatchOccurrence | null { return ptern.matchStartOf(input) }
export function matchEndOf(ptern: Ptern, input: string): MatchOccurrence | null { return ptern.matchEndOf(input) }
export function matchFirstIn(ptern: Ptern, input: string): MatchOccurrence | null { return ptern.matchFirstIn(input) }

export function matchAllIn(ptern: Ptern, input: string): MatchOccurrence[] { return ptern.matchAllIn(input) }

function runReplacement(exec: () => string): string | ReplacementError {
  try {
    return exec()
  } catch (e) {
    if (!(e instanceof PternReplacementError)) throw e
    return convertReplacementError(e.replacementError)
  }
}

export function replaceAllOf(ptern: Ptern, input: string, captures: CaptureInput): string | ReplacementError {
  return runReplacement(() => ptern.replaceAllOf(input, captures))
}
export function replaceStartOf(ptern: Ptern, input: string, captures: CaptureInput): string | ReplacementError {
  return runReplacement(() => ptern.replaceStartOf(input, captures))
}
export function replaceEndOf(ptern: Ptern, input: string, captures: CaptureInput): string | ReplacementError {
  return runReplacement(() => ptern.replaceEndOf(input, captures))
}
export function replaceFirstIn(ptern: Ptern, input: string, captures: CaptureInput): string | ReplacementError {
  return runReplacement(() => ptern.replaceFirstIn(input, captures))
}
export function replaceAllIn(ptern: Ptern, input: string, captures: CaptureInput): string | ReplacementError {
  return runReplacement(() => ptern.replaceAllIn(input, captures))
}

export function substitute(ptern: Ptern, captures: CaptureInput): string | SubstitutionError {
  try {
    return ptern.substitute(captures)
  } catch (e) {
    if (!(e instanceof PternSubstitutionError)) throw e
    return convertSubstitutionError(e.substitutionError)
  }
}

export function getMinLength(ptern: Ptern): number { return ptern.minLength() }

export function getMaxLength(ptern: Ptern): number | null { return ptern.maxLength() }

export function isSubstitutable(ptern: Ptern): boolean { return ptern.isSubstitutable() }

export function getRegexSource(ptern: Ptern): string { return ptern.regexSource() }
export function getRegexFlags(ptern: Ptern): string { return ptern.regexFlags() }
