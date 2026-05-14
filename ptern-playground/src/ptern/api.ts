// Typed wrapper around the compiled Gleam ptern library.
// All Gleam runtime types are treated as `any`; this file is the typed surface.

// eslint-disable-next-line @typescript-eslint/no-explicit-any
type Any = any

import * as gleamPtern from './ptern/ptern.mjs'
import { insert as dictInsert, new$ as dictNew, to_list as dictToList } from './gleam_stdlib/gleam/dict.mjs'
import { toList as gleamToList } from './prelude.mjs'
import { FormatOptions$FormatOptions as makeGleamFormatOptions } from './ptern/formatter/formatter.mjs'

function isOk(result: Any): boolean { return result?.constructor?.name === 'Ok' }

// ---------------------------------------------------------------------------
// Public types
// ---------------------------------------------------------------------------

export type Ptern = Any

export type CompileError =
  | { kind: 'lex'; message: string }
  | { kind: 'parse'; message: string }
  | { kind: 'semantic'; messages: string[] }

export type FormatOptions = {
  aligned: boolean
  compact: boolean
  lineWidth: number
  reordered: boolean
}

export type MatchOccurrence = {
  index: number
  length: number
  captures: Record<string, string>
}

export type CaptureInput = Record<string, string | string[]>

export type ReplacementError =
  | { kind: 'invalid'; captureName: string; value: string }
  | { kind: 'wrongType'; captureName: string }
  | { kind: 'lengthMismatch'; captureName: string; provided: number; actual: number }
  | { kind: 'duplicateRepetition'; captureName: string }

export type SubstitutionError =
  | { kind: 'notSubstitutable' }
  | { kind: 'missing'; name: string }
  | { kind: 'mismatch'; name: string }
  | { kind: 'lengthError'; name: string; length: number; min: number; max: number }
  | { kind: 'noMatchingBranch' }

// ---------------------------------------------------------------------------
// Gleam runtime helpers
// ---------------------------------------------------------------------------

function gleamListToArray<T>(list: Any): T[] {
  const result: T[] = []
  let node = list
  while (node && node.head !== undefined) {
    result.push(node.head as T)
    node = node.tail
  }
  return result
}

function gleamDictToRecord(dict: Any): Record<string, string> {
  const result: Record<string, string> = {}
  for (const [k, v] of gleamListToArray<[string, string]>(dictToList(dict))) {
    result[k] = v
  }
  return result
}

function jsToGleamReplacementDict(input: CaptureInput): Any {
  let dict = dictNew()
  for (const [key, value] of Object.entries(input)) {
    const rv = Array.isArray(value)
      ? new gleamPtern.ArrayReplacement(gleamToList(value))
      : new gleamPtern.ScalarReplacement(value)
    dict = dictInsert(dict, key, rv)
  }
  return dict
}

function convertOccurrence(occ: Any): MatchOccurrence {
  return {
    index: occ.index as number,
    length: occ.length as number,
    captures: gleamDictToRecord(occ.captures),
  }
}

function formatLexError(inner: Any): string {
  const name: string = inner?.constructor?.name ?? ''
  if (name === 'UnexpectedCharacter') return `Unexpected character '${inner[0]}'`
  if (name === 'UnterminatedString') return 'Unterminated string literal'
  if (name === 'InlineComment') return 'Inline comments are not allowed'
  return `Lex error: ${name}`
}

function formatParseError(inner: Any): string {
  const name: string = inner?.constructor?.name ?? ''
  if (name === 'UnexpectedToken') return `Unexpected token: expected ${inner.expected}, got ${inner.got}`
  if (name === 'UnexpectedEndOfInput') return 'Unexpected end of input'
  return `Parse error: ${name}`
}

function formatSemanticError(e: Any): string {
  const name: string = e?.constructor?.name ?? ''
  switch (name) {
    case 'UndefinedReference': return `Undefined reference: ${e.name}`
    case 'DuplicateDefinition': return `Duplicate definition: ${e.name}`
    case 'CircularDefinition': return `Circular definition: ${gleamListToArray<string>(e.names).join(', ')}`
    case 'CaptureDefinitionConflict': return `Name used as both a capture and a definition: ${e.name}`
    case 'InvalidRangeEndpoint': return `Invalid character range endpoint: '${e.content}'`
    case 'InvertedRange': return `Inverted character range: '${e.from}'..'${e.to}'`
    case 'InvertedRepetitionBounds': return `Inverted repetition bounds: ${e.min}..${e.max}`
    case 'InvalidExclusionOperand': return 'Invalid operand for excluding'
    case 'UnknownAnnotation': return `Unknown annotation: !${e.name}`
    case 'DuplicateAnnotation': return `Duplicate annotation: !${e.name}`
    case 'InvalidEscapeSequence': return `Invalid escape sequence: ${e.seq}`
    case 'UnknownPositionAssertion': return `Unknown position assertion: @${e.name}`
    case 'PositionAssertionInRepetition': return `Position assertion @${e.name} cannot appear inside a repetition`
    case 'SubstitutionsIgnoreMatchingWithoutSubstitutable': return '!substitutions-ignore-matching requires !substitutable'
    case 'NotSubstitutableBody': return 'Pattern body is not substitutable'
    case 'BoundedRepetitionNeedsCapture': return 'Bounded repetition inside substitutable pattern must have a capture'
    case 'EmptyLiteral': return 'Empty string literal'
    case 'EmptyCharacterSet': return 'Empty character set (excluding removes all characters)'
    case 'AmbiguousRepetitionAdjacency': return 'Ambiguous: repetition adjacent to another repetition in an alternation'
    case 'AmbiguousRepetitionBody': return 'Ambiguous: repetition body could match empty string'
    case 'AmbiguousAdjacentRepetition': return 'Ambiguous: two repetitions are adjacent'
    case 'FewestOnExactRepetition': return '!fewest cannot be used on an exact repetition'
    case 'UnusedDefinition': return `Unused definition: ${e.name}`
    default: return name || 'Unknown semantic error'
  }
}

function convertReplacementError(e: Any): ReplacementError {
  const name: string = e?.constructor?.name ?? ''
  switch (name) {
    case 'InvalidReplacementValue': return { kind: 'invalid', captureName: e.capture_name, value: e.value }
    case 'WrongReplacementType': return { kind: 'wrongType', captureName: e.capture_name }
    case 'ArrayLengthMismatch': return { kind: 'lengthMismatch', captureName: e.capture_name, provided: e.provided, actual: e.actual }
    case 'DuplicateRepetitionCapture': return { kind: 'duplicateRepetition', captureName: e.capture_name }
    default: return { kind: 'wrongType', captureName: '' }
  }
}

function convertSubstitutionError(e: Any): SubstitutionError {
  const name: string = e?.constructor?.name ?? ''
  switch (name) {
    case 'NotSubstitutable': return { kind: 'notSubstitutable' }
    case 'MissingCapture': return { kind: 'missing', name: e.name }
    case 'CaptureMismatch': return { kind: 'mismatch', name: e.name }
    case 'ArrayLengthError': return { kind: 'lengthError', name: e.name, length: e.length, min: e.min, max: e.max }
    case 'NoMatchingBranch': return { kind: 'noMatchingBranch' }
    default: return { kind: 'notSubstitutable' }
  }
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

export function compilePtern(source: string): { ok: true; ptern: Ptern } | { ok: false; error: CompileError } {
  const result: Any = gleamPtern.compile(source)
  if (isOk(result)) {
    return { ok: true, ptern: result[0] }
  }
  const err: Any = result[0]
  const errName: string = err?.constructor?.name ?? ''
  if (errName === 'LexError') return { ok: false, error: { kind: 'lex', message: formatLexError(err[0]) } }
  if (errName === 'ParseError') return { ok: false, error: { kind: 'parse', message: formatParseError(err[0]) } }
  if (errName === 'SemanticErrors') {
    const messages = gleamListToArray<Any>(err[0]).map(formatSemanticError)
    return { ok: false, error: { kind: 'semantic', messages } }
  }
  return { ok: false, error: { kind: 'parse', message: 'Unknown compile error' } }
}

export function getDefaultFormatOptions(): FormatOptions {
  const opts: Any = gleamPtern.default_format_options()
  return { aligned: opts.aligned, compact: opts.compact, lineWidth: opts.line_width, reordered: opts.reordered }
}

export function formatPtern(source: string, options: FormatOptions): string | null {
  const gleamOpts = makeGleamFormatOptions(options.lineWidth, options.compact, options.aligned, options.reordered)
  const result: Any = gleamPtern.format(source, gleamOpts)
  if (isOk(result)) return result[0] as string
  return null
}

export function matchesAllOf(ptern: Ptern, input: string): boolean { return gleamPtern.matches_all_of(ptern, input) as boolean }
export function matchesStartOf(ptern: Ptern, input: string): boolean { return gleamPtern.matches_start_of(ptern, input) as boolean }
export function matchesEndOf(ptern: Ptern, input: string): boolean { return gleamPtern.matches_end_of(ptern, input) as boolean }
export function matchesIn(ptern: Ptern, input: string): boolean { return gleamPtern.matches_in(ptern, input) as boolean }

function unwrapOccurrenceOption(opt: Any): MatchOccurrence | null {
  if (opt?.constructor?.name === 'Some') return convertOccurrence(opt[0])
  return null
}

export function matchAllOf(ptern: Ptern, input: string): MatchOccurrence | null { return unwrapOccurrenceOption(gleamPtern.match_all_of(ptern, input)) }
export function matchStartOf(ptern: Ptern, input: string): MatchOccurrence | null { return unwrapOccurrenceOption(gleamPtern.match_start_of(ptern, input)) }
export function matchEndOf(ptern: Ptern, input: string): MatchOccurrence | null { return unwrapOccurrenceOption(gleamPtern.match_end_of(ptern, input)) }
export function matchFirstIn(ptern: Ptern, input: string): MatchOccurrence | null { return unwrapOccurrenceOption(gleamPtern.match_first_in(ptern, input)) }

export function matchAllIn(ptern: Ptern, input: string): MatchOccurrence[] {
  return gleamListToArray<Any>(gleamPtern.match_all_in(ptern, input)).map(convertOccurrence)
}

function runReplacement(fn: Any, ptern: Ptern, input: string, captures: CaptureInput): string | ReplacementError {
  const dict = jsToGleamReplacementDict(captures)
  const result: Any = fn(ptern, input, dict)
  if (isOk(result)) return result[0] as string
  return convertReplacementError(result[0])
}

export function replaceAllOf(ptern: Ptern, input: string, captures: CaptureInput): string | ReplacementError { return runReplacement(gleamPtern.replace_all_of, ptern, input, captures) }
export function replaceStartOf(ptern: Ptern, input: string, captures: CaptureInput): string | ReplacementError { return runReplacement(gleamPtern.replace_start_of, ptern, input, captures) }
export function replaceEndOf(ptern: Ptern, input: string, captures: CaptureInput): string | ReplacementError { return runReplacement(gleamPtern.replace_end_of, ptern, input, captures) }
export function replaceFirstIn(ptern: Ptern, input: string, captures: CaptureInput): string | ReplacementError { return runReplacement(gleamPtern.replace_first_in, ptern, input, captures) }
export function replaceAllIn(ptern: Ptern, input: string, captures: CaptureInput): string | ReplacementError { return runReplacement(gleamPtern.replace_all_in, ptern, input, captures) }

export function substitute(ptern: Ptern, captures: CaptureInput): string | SubstitutionError {
  const dict = jsToGleamReplacementDict(captures)
  const result: Any = gleamPtern.substitute(ptern, dict)
  if (isOk(result)) return result[0] as string
  return convertSubstitutionError(result[0])
}

export function getMinLength(ptern: Ptern): number { return gleamPtern.min_length(ptern) as number }

export function getMaxLength(ptern: Ptern): number | null {
  const opt: Any = gleamPtern.max_length(ptern)
  if (opt?.constructor?.name === 'Some') return opt[0] as number
  return null
}

export function isSubstitutable(ptern: Ptern): boolean { return (ptern as Any).is_substitutable as boolean }

export function getRegexSource(ptern: Ptern): string { return (ptern as Any).source as string }
export function getRegexFlags(ptern: Ptern): string { return (ptern as Any).flags as string }
