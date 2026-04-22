/**
 * Ptern — readable pattern language that compiles to JavaScript regular
 * expressions.
 *
 * Usage (tagged template literal):
 *
 *   import { ptern } from "./index.ts"
 *
 *   const date = ptern`
 *     yyyy = %Digit * 4;
 *     mm   = ('0' '1'..'9') | ('1' '0'..'2');
 *     dd   = ('0' '1'..'9') | ('1'..'2' %Digit) | ('3' '0'..'1');
 *     {yyyy} as year '-' {mm} as month '-' {dd} as day
 *   `
 *
 *   date.matchesAllOf("2024-03-15")  // true
 *   date.matchAllOf("2024-03-15")    // { index: 0, length: 10, captures: { year: "2024", ... } }
 */

// ---------------------------------------------------------------------------
// Gleam runtime helpers
// ---------------------------------------------------------------------------

interface GleamResult {
  isOk(): boolean;
  0: unknown;
}

interface GleamOption {
  0?: number;
}

interface GleamCompiledPattern {
  source: string;
  flags: string;
  min_length: number;
  max_length: GleamOption;
}

// ---------------------------------------------------------------------------
// Public types
// ---------------------------------------------------------------------------

export interface MatchResult {
  [groupName: string]: string;
}

export interface MatchOccurrence {
  /** Code-unit index of the start of the match within the input string. */
  index: number;
  /** Length of the matched text in code units. */
  length: number;
  /** Named capture groups from this match. */
  captures: MatchResult;
}

export interface Ptern {
  /** Returns true if the entire input matches this pattern. */
  matchesAllOf(input: string): boolean;
  /** Returns true if the input starts with this pattern. */
  matchesStartOf(input: string): boolean;
  /** Returns true if the input ends with this pattern. */
  matchesEndOf(input: string): boolean;
  /** Returns true if the pattern appears anywhere in the input. */
  matchesIn(input: string): boolean;
  /** Returns the occurrence if the entire input matches, otherwise null. */
  matchAllOf(input: string): MatchOccurrence | null;
  /** Returns the occurrence if the input starts with this pattern, otherwise null. */
  matchStartOf(input: string): MatchOccurrence | null;
  /** Returns the occurrence if the input ends with this pattern, otherwise null. */
  matchEndOf(input: string): MatchOccurrence | null;
  /** Returns the first occurrence anywhere in the input, or null. */
  matchFirstIn(input: string): MatchOccurrence | null;
  /** Returns the next occurrence at or after startIndex, or null. */
  matchNextIn(input: string, startIndex: number): MatchOccurrence | null;
  /** Returns all occurrences in the input. */
  matchAllIn(input: string): MatchOccurrence[];
  /** Minimum number of characters this pattern can match. */
  minLength(): number;
  /**
   * Maximum number of characters this pattern can match, or null if the
   * pattern is unbounded (e.g. uses `*` or `+` repetition).
   */
  maxLength(): number | null;
}

export type CompileError =
  | { kind: "LexError"; message: string }
  | { kind: "ParseError"; message: string }
  | { kind: "SemanticErrors"; errors: string[] };

// ---------------------------------------------------------------------------
// Internal implementation
// ---------------------------------------------------------------------------

class PternImpl implements Ptern {
  private readonly _full: RegExp;
  private readonly _starts: RegExp;
  private readonly _ends: RegExp;
  private readonly _contains: RegExp;
  private readonly _containsG: RegExp;
  private readonly _min: number;
  private readonly _max: number | null;

  constructor(
    source: string,
    flags: string,
    minLen: number,
    maxLen: number | null,
  ) {
    this._full = new RegExp(`^(?:${source})$`, flags);
    this._starts = new RegExp(`^(?:${source})`, flags);
    this._ends = new RegExp(`(?:${source})$`, flags);
    this._contains = new RegExp(source, flags);
    this._containsG = new RegExp(source, flags.includes("g") ? flags : flags + "g");
    this._min = minLen;
    this._max = maxLen;
  }

  private static toOccurrence(m: RegExpExecArray): MatchOccurrence {
    const groups = m.groups ?? {};
    const captures: MatchResult = {};
    for (const [k, v] of Object.entries(groups)) {
      if (typeof v === "string") captures[k] = v;
    }
    return { index: m.index, length: m[0].length, captures };
  }

  matchesAllOf(input: string): boolean {
    this._full.lastIndex = 0;
    return this._full.test(input);
  }

  matchesStartOf(input: string): boolean {
    this._starts.lastIndex = 0;
    return this._starts.test(input);
  }

  matchesEndOf(input: string): boolean {
    this._ends.lastIndex = 0;
    return this._ends.test(input);
  }

  matchesIn(input: string): boolean {
    this._contains.lastIndex = 0;
    return this._contains.test(input);
  }

  matchAllOf(input: string): MatchOccurrence | null {
    this._full.lastIndex = 0;
    const m = this._full.exec(input);
    return m === null ? null : PternImpl.toOccurrence(m);
  }

  matchStartOf(input: string): MatchOccurrence | null {
    this._starts.lastIndex = 0;
    const m = this._starts.exec(input);
    return m === null ? null : PternImpl.toOccurrence(m);
  }

  matchEndOf(input: string): MatchOccurrence | null {
    this._ends.lastIndex = 0;
    const m = this._ends.exec(input);
    return m === null ? null : PternImpl.toOccurrence(m);
  }

  matchFirstIn(input: string): MatchOccurrence | null {
    this._contains.lastIndex = 0;
    const m = this._contains.exec(input);
    return m === null ? null : PternImpl.toOccurrence(m);
  }

  matchNextIn(input: string, startIndex: number): MatchOccurrence | null {
    this._containsG.lastIndex = startIndex;
    const m = this._containsG.exec(input);
    return m === null ? null : PternImpl.toOccurrence(m);
  }

  matchAllIn(input: string): MatchOccurrence[] {
    this._containsG.lastIndex = 0;
    const results: MatchOccurrence[] = [];
    let m: RegExpExecArray | null;
    while ((m = this._containsG.exec(input)) !== null) {
      results.push(PternImpl.toOccurrence(m));
      if (m[0].length === 0) this._containsG.lastIndex++;
    }
    return results;
  }

  minLength(): number {
    return this._min;
  }

  maxLength(): number | null {
    return this._max;
  }
}

// ---------------------------------------------------------------------------
// Compile
// ---------------------------------------------------------------------------

/**
 * Compile a Ptern source string into a `Ptern` object.
 *
 * Throws a `CompileError`-shaped object if compilation fails.
 */
export function compile(source: string): Ptern {
  // Dynamic import to avoid hard-coding the build path at module load time.
  // eslint-disable-next-line @typescript-eslint/no-require-imports
  const lib = require("./ptern-gleam/build/dev/javascript/ptern/ptern.mjs");
  const result = lib.compile(source) as GleamResult;

  if (!result.isOk()) {
    const err = result[0] as { [key: string]: unknown };
    // Gleam variant tag is the constructor name.
    const tag = (err as object).constructor.name;
    if (tag === "LexError") {
      throw { kind: "LexError", message: String(err[0]) } satisfies CompileError;
    }
    if (tag === "ParseError") {
      const inner = err[0] as { [key: string]: unknown };
      const msg =
        inner.constructor?.name === "UnexpectedToken"
          ? `Expected ${inner.expected}, got ${inner.got}`
          : "Unexpected end of input";
      throw { kind: "ParseError", message: msg } satisfies CompileError;
    }
    // SemanticErrors — err[0] is a Gleam List
    const errs = gleamListToArray(err[0]) as Array<unknown>;
    throw {
      kind: "SemanticErrors",
      errors: errs.map((e) => {
        const eName = (e as object).constructor.name;
        const ev = e as { [k: string]: unknown };
        switch (eName) {
          case "UndefinedReference":
            return `Undefined reference: ${ev[0]}`;
          case "DuplicateDefinition":
            return `Duplicate definition: ${ev[0]}`;
          case "CircularDefinition":
            return `Circular definition: ${gleamListToArray(ev[0]).join(", ")}`;
          case "DuplicateCapture":
            return `Duplicate capture: ${ev[0]}`;
          case "CaptureDefinitionConflict":
            return `Capture/definition conflict: ${ev[0]}`;
          case "CaptureInRepetition":
            return `Named capture inside repetition: ${ev[0]}`;
          case "InvalidRangeEndpoint":
            return `Invalid range endpoint: ${ev[0]}`;
          case "InvertedRange":
            return `Inverted range: ${ev.from}..${ev.to}`;
          case "InvertedRepetitionBounds":
            return `Inverted repetition bounds: ${ev.min}..${ev.max}`;
          case "InvalidExclusionOperand":
            return "Invalid exclusion operand";
          case "UnknownAnnotation":
            return `Unknown annotation: ${ev[0]}`;
          case "DuplicateAnnotation":
            return `Duplicate annotation: ${ev[0]}`;
          case "InvalidEscapeSequence":
            return `Invalid escape sequence: ${ev[0]}`;
          default:
            return eName;
        }
      }),
    } satisfies CompileError;
  }

  const cp = result[0] as GleamCompiledPattern;
  const maxLen =
    cp.max_length[0] !== undefined ? (cp.max_length[0] as number) : null;

  return new PternImpl(cp.source, cp.flags, cp.min_length, maxLen);
}

// ---------------------------------------------------------------------------
// Tagged template literal
// ---------------------------------------------------------------------------

/**
 * Compile a Ptern pattern written as a tagged template literal.
 *
 * Only static (no interpolations) tagged templates are supported; template
 * expressions are not used — the full source is the raw string.
 *
 * @example
 * const digit = ptern`%Digit * 4`
 */
export function ptern(strings: TemplateStringsArray): Ptern {
  return compile(strings.raw.join(""));
}

// ---------------------------------------------------------------------------
// Gleam linked-list helper
// ---------------------------------------------------------------------------

function gleamListToArray(list: unknown): unknown[] {
  const result: unknown[] = [];
  let node = list as { head?: unknown; tail?: unknown } | null;
  while (node && "head" in node) {
    result.push(node.head);
    node = node.tail as typeof node;
  }
  return result;
}
