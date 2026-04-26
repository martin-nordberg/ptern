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
  // Fields from the Ptern opaque record (Gleam field names match JS property names)
  min_len: number;
  max_len: GleamOption;
  ignore_matching: boolean;
  is_substitutable: boolean;
  ignore_substitution_matching: boolean;
  substitution_plan: GleamOption; // Gleam Option(SubstitutionPlan)
  // Extra fields added for TypeScript interop
  source: string;
  flags: string;
  capture_validator_list: unknown; // Gleam List(#(String, String))
}

// Gleam SubstitutionPlan ADT nodes as emitted by the compiler.
// Each variant is a JS class with named fields matching the Gleam field names.
type GleamPlan = Record<string, unknown> & { constructor: { name: string } };

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
  /**
   * Replace the match if the entire input matches, otherwise return input unchanged.
   * Throws `ReplacementError` if a replacement value does not satisfy the capture's
   * subpattern. Set `!replacements-ignore-matching = true` to disable this check.
   */
  replaceAllOf(input: string, replacements: MatchResult): string;
  /** Replace the match at the start of input, otherwise return input unchanged. */
  replaceStartOf(input: string, replacements: MatchResult): string;
  /** Replace the match at the end of input, otherwise return input unchanged. */
  replaceEndOf(input: string, replacements: MatchResult): string;
  /** Replace the first occurrence anywhere in the input, otherwise return input unchanged. */
  replaceFirstIn(input: string, replacements: MatchResult): string;
  /** Replace the next occurrence at or after startIndex, otherwise return input unchanged. */
  replaceNextIn(input: string, startIndex: number, replacements: MatchResult): string;
  /** Replace all occurrences with the same replacements. */
  replaceAllIn(input: string, replacements: MatchResult): string;
  /** Minimum number of characters this pattern can match. */
  minLength(): number;
  /**
   * Maximum number of characters this pattern can match, or null if the
   * pattern is unbounded (e.g. uses `*` or `+` repetition).
   */
  maxLength(): number | null;
  /**
   * Assemble a string from named capture values.
   * Requires `!substitutable = true` to be declared in the ptern source.
   * Throws `SubstitutionError` on failure.
   */
  substitute(captures: Record<string, string | string[]>): string;
}

export type CompileError =
  | { kind: "LexError"; message: string }
  | { kind: "ParseError"; message: string }
  | { kind: "SemanticErrors"; errors: string[] };

export type ReplacementError = {
  kind: "InvalidReplacementValue";
  captureName: string;
  value: string;
};

export type SubstitutionError =
  | { kind: "NotSubstitutable" }
  | { kind: "MissingCapture"; captureName: string }
  | { kind: "CaptureMismatch"; captureName: string; value: string }
  | { kind: "WrongCaptureType"; captureName: string }
  | { kind: "ArrayLengthError"; captureName: string; length: number; min: number; max: number | null }
  | { kind: "NoMatchingBranch" };

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
  private readonly _ignoreMatching: boolean;
  private readonly _captureValidators: Map<string, RegExp>;
  private readonly _isSubstitutable: boolean;
  private readonly _ignoreSubstitutionMatching: boolean;
  private readonly _substitutionPlan: GleamPlan | null;

  constructor(
    source: string,
    flags: string,
    minLen: number,
    maxLen: number | null,
    ignoreMatching: boolean,
    captureValidators: Map<string, RegExp>,
    isSubstitutable: boolean,
    ignoreSubstitutionMatching: boolean,
    substitutionPlan: GleamPlan | null,
  ) {
    const df = flags.includes("d") ? flags : flags + "d";
    this._full = new RegExp(`^(?:${source})$`, df);
    this._starts = new RegExp(`^(?:${source})`, df);
    this._ends = new RegExp(`(?:${source})$`, df);
    this._contains = new RegExp(source, df);
    this._containsG = new RegExp(source, df.includes("g") ? df : df + "g");
    this._min = minLen;
    this._max = maxLen;
    this._ignoreMatching = ignoreMatching;
    this._captureValidators = captureValidators;
    this._isSubstitutable = isSubstitutable;
    this._ignoreSubstitutionMatching = ignoreSubstitutionMatching;
    this._substitutionPlan = substitutionPlan;
  }

  private validateReplacements(replacements: MatchResult): void {
    if (this._ignoreMatching) return;
    for (const [name, value] of Object.entries(replacements)) {
      const re = this._captureValidators.get(name);
      if (re !== undefined && !re.test(value)) {
        throw { kind: "InvalidReplacementValue", captureName: name, value } satisfies ReplacementError;
      }
    }
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

  // Build the replacement text for a single match, substituting named captures.
  // Requires the regex to have the 'd' flag so that m.indices.groups is populated.
  private static applyReplacements(
    m: RegExpExecArray & { indices?: { groups?: Record<string, [number, number] | undefined> } },
    replacements: MatchResult,
  ): string {
    const matchStart = m.index;
    const groupIndices = m.indices?.groups ?? {};
    let matchText = m[0];
    const patches = Object.entries(replacements)
      .filter(([name]) => groupIndices[name] !== undefined)
      .map(([name, newVal]) => ({
        relStart: groupIndices[name]![0] - matchStart,
        relEnd: groupIndices[name]![1] - matchStart,
        newVal,
      }))
      .sort((a, b) => b.relStart - a.relStart);
    for (const { relStart, relEnd, newVal } of patches) {
      matchText = matchText.slice(0, relStart) + newVal + matchText.slice(relEnd);
    }
    return matchText;
  }

  private spliceReplacement(input: string, m: RegExpExecArray, replacements: MatchResult): string {
    const newText = PternImpl.applyReplacements(
      m as RegExpExecArray & { indices?: { groups?: Record<string, [number, number] | undefined> } },
      replacements,
    );
    return input.slice(0, m.index) + newText + input.slice(m.index + m[0].length);
  }

  replaceAllOf(input: string, replacements: MatchResult): string {
    this.validateReplacements(replacements);
    this._full.lastIndex = 0;
    const m = this._full.exec(input);
    return m === null ? input : this.spliceReplacement(input, m, replacements);
  }

  replaceStartOf(input: string, replacements: MatchResult): string {
    this.validateReplacements(replacements);
    this._starts.lastIndex = 0;
    const m = this._starts.exec(input);
    return m === null ? input : this.spliceReplacement(input, m, replacements);
  }

  replaceEndOf(input: string, replacements: MatchResult): string {
    this.validateReplacements(replacements);
    this._ends.lastIndex = 0;
    const m = this._ends.exec(input);
    return m === null ? input : this.spliceReplacement(input, m, replacements);
  }

  replaceFirstIn(input: string, replacements: MatchResult): string {
    this.validateReplacements(replacements);
    this._contains.lastIndex = 0;
    const m = this._contains.exec(input);
    return m === null ? input : this.spliceReplacement(input, m, replacements);
  }

  replaceNextIn(input: string, startIndex: number, replacements: MatchResult): string {
    this.validateReplacements(replacements);
    this._containsG.lastIndex = startIndex;
    const m = this._containsG.exec(input);
    return m === null ? input : this.spliceReplacement(input, m, replacements);
  }

  replaceAllIn(input: string, replacements: MatchResult): string {
    this.validateReplacements(replacements);
    this._containsG.lastIndex = 0;
    const parts: string[] = [];
    let lastEnd = 0;
    let m: RegExpExecArray | null;
    while ((m = this._containsG.exec(input)) !== null) {
      parts.push(input.slice(lastEnd, m.index));
      parts.push(PternImpl.applyReplacements(
        m as RegExpExecArray & { indices?: { groups?: Record<string, [number, number] | undefined> } },
        replacements,
      ));
      lastEnd = m.index + m[0].length;
      if (m[0].length === 0) this._containsG.lastIndex++;
    }
    parts.push(input.slice(lastEnd));
    return parts.join("");
  }

  minLength(): number {
    return this._min;
  }

  maxLength(): number | null {
    return this._max;
  }

  substitute(captures: Record<string, string | string[]>): string {
    if (!this._isSubstitutable || this._substitutionPlan === null) {
      throw { kind: "NotSubstitutable" } satisfies SubstitutionError;
    }
    const cursors = new Map<string, number>();
    return evaluatePlan(
      this._substitutionPlan,
      captures,
      this._captureValidators,
      this._ignoreSubstitutionMatching,
      cursors,
    );
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
            return `Undefined reference: ${ev["name"]}`;
          case "DuplicateDefinition":
            return `Duplicate definition: ${ev["name"]}`;
          case "CircularDefinition":
            return `Circular definition: ${gleamListToArray(ev["names"]).join(", ")}`;
          case "DuplicateCapture":
            return `Duplicate capture: ${ev["name"]}`;
          case "CaptureDefinitionConflict":
            return `Capture/definition conflict: ${ev["name"]}`;
          case "CaptureInRepetition":
            return `Named capture inside repetition: ${ev["name"]}`;
          case "InvalidRangeEndpoint":
            return `Invalid range endpoint: ${ev["content"]}`;
          case "InvertedRange":
            return `Inverted range: ${ev["from"]}..${ev["to"]}`;
          case "InvertedRepetitionBounds":
            return `Inverted repetition bounds: ${ev["min"]}..${ev["max"]}`;
          case "InvalidExclusionOperand":
            return "Invalid exclusion operand";
          case "UnknownAnnotation":
            return `Unknown annotation: ${ev["name"]}`;
          case "DuplicateAnnotation":
            return `Duplicate annotation: ${ev["name"]}`;
          case "InvalidEscapeSequence":
            return `Invalid escape sequence: ${ev["seq"]}`;
          case "UnknownPositionAssertion":
            return `Unknown position assertion: ${ev["name"]}`;
          case "PositionAssertionInRepetition":
            return `Position assertion inside repetition: ${ev["name"]}`;
          case "SubstitutionsIgnoreMatchingWithoutSubstitutable":
            return "!substitutions-ignore-matching requires !substitutable = true";
          case "NotSubstitutableBody":
            return "Pattern body is not substitutable (set !substitutable = true only on fully substitutable patterns)";
          case "BoundedRepetitionNeedsCapture":
            return "Bounded repetition in substitutable pattern must contain at least one named capture";
          default:
            return eName;
        }
      }),
    } satisfies CompileError;
  }

  const cp = result[0] as GleamCompiledPattern;
  const maxLen = cp.max_len[0] !== undefined ? (cp.max_len[0] as number) : null;

  const cvEntries = gleamListToArray(cp.capture_validator_list) as Array<[string, string]>;
  // Keep the first fragment for each name (subsequent ones are back-reference
  // captures whose compiled body is (?:(?!)) and would break validation).
  const captureValidators = new Map<string, RegExp>();
  for (const [name, fragment] of cvEntries) {
    if (!captureValidators.has(name)) {
      captureValidators.set(name, new RegExp(`^(?:${fragment})$`, cp.flags));
    }
  }

  const substitutionPlan =
    cp.substitution_plan[0] !== undefined
      ? (cp.substitution_plan[0] as GleamPlan)
      : null;

  return new PternImpl(
    cp.source,
    cp.flags,
    cp.min_len,
    maxLen,
    cp.ignore_matching,
    captureValidators,
    cp.is_substitutable,
    cp.ignore_substitution_matching,
    substitutionPlan,
  );
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

// ---------------------------------------------------------------------------
// Substitution plan evaluation
// ---------------------------------------------------------------------------

// Collect all PlanCapture names directly within a plan subtree, treating
// each PlanCapture as a leaf (not recursing into its inner).
function collectDirectCaptureNames(plan: GleamPlan): string[] {
  switch (plan.constructor.name) {
    case "PlanCapture":
      return [plan["name"] as string];
    case "PlanSequence":
      return gleamListToArray(plan["items"]).flatMap(
        (p) => collectDirectCaptureNames(p as GleamPlan),
      );
    case "PlanAlternation": {
      const all = gleamListToArray(plan["branches"]).flatMap(
        (p) => collectDirectCaptureNames(p as GleamPlan),
      );
      return [...new Set(all)];
    }
    case "PlanFixedRep":
    case "PlanBoundedRep":
      return collectDirectCaptureNames(plan["inner"] as GleamPlan);
    default:
      return [];
  }
}

function evaluatePlan(
  plan: GleamPlan,
  captures: Record<string, string | string[]>,
  validators: Map<string, RegExp>,
  ignoreMatching: boolean,
  cursors: Map<string, number>,
): string {
  switch (plan.constructor.name) {
    case "PlanLiteral":
      return plan["text"] as string;

    case "PlanPositionAssertion":
      return "";

    case "PlanNotEvaluable":
      // Reached only when a named capture above this was absent. Callers
      // must throw MissingCapture before reaching here; this is a safety net.
      throw { kind: "NoMatchingBranch" } satisfies SubstitutionError;

    case "PlanCapture": {
      const name = plan["name"] as string;
      const inner = plan["inner"] as GleamPlan;
      if (name in captures) {
        const val = captures[name];
        if (Array.isArray(val)) {
          const cursor = cursors.get(name) ?? 0;
          if (cursor >= val.length) {
            throw { kind: "MissingCapture", captureName: name } satisfies SubstitutionError;
          }
          const elem = val[cursor]!;
          if (!ignoreMatching) {
            const re = validators.get(name);
            if (re !== undefined && !re.test(elem)) {
              throw { kind: "CaptureMismatch", captureName: name, value: elem } satisfies SubstitutionError;
            }
          }
          cursors.set(name, cursor + 1);
          return elem;
        }
        // scalar string
        if (typeof val !== "string") {
          throw { kind: "WrongCaptureType", captureName: name } satisfies SubstitutionError;
        }
        if (!ignoreMatching) {
          const re = validators.get(name);
          if (re !== undefined && !re.test(val)) {
            throw { kind: "CaptureMismatch", captureName: name, value: val } satisfies SubstitutionError;
          }
        }
        return val;
      }
      // Absent: evaluate inner. NoMatchingBranch from a non-substitutable
      // inner expression means the capture was required — convert to MissingCapture.
      try {
        return evaluatePlan(inner, captures, validators, ignoreMatching, cursors);
      } catch (e) {
        const err = e as SubstitutionError;
        if (err.kind === "NoMatchingBranch") {
          throw { kind: "MissingCapture", captureName: name } satisfies SubstitutionError;
        }
        throw e;
      }
    }

    case "PlanSequence": {
      const items = gleamListToArray(plan["items"]) as GleamPlan[];
      return items
        .map((item) => evaluatePlan(item, captures, validators, ignoreMatching, cursors))
        .join("");
    }

    case "PlanAlternation": {
      const branches = gleamListToArray(plan["branches"]) as GleamPlan[];
      for (const branch of branches) {
        const savedCursors = new Map(cursors);
        try {
          return evaluatePlan(branch, captures, validators, ignoreMatching, cursors);
        } catch (e) {
          const err = e as SubstitutionError;
          if (err.kind === "MissingCapture" || err.kind === "NoMatchingBranch") {
            // Restore cursors and try next branch.
            cursors.clear();
            for (const [k, v] of savedCursors) cursors.set(k, v);
            continue;
          }
          throw e;
        }
      }
      throw { kind: "NoMatchingBranch" } satisfies SubstitutionError;
    }

    case "PlanFixedRep": {
      const inner = plan["inner"] as GleamPlan;
      const count = plan["count"] as number;
      let out = "";
      for (let i = 0; i < count; i++) {
        out += evaluatePlan(inner, captures, validators, ignoreMatching, cursors);
      }
      return out;
    }

    case "PlanBoundedRep": {
      const inner = plan["inner"] as GleamPlan;
      const minVal = plan["min"] as number;
      const maxOpt = plan["max"] as GleamOption;
      const maxVal = maxOpt[0] !== undefined ? (maxOpt[0] as number) : null;

      const captureNames = collectDirectCaptureNames(inner);

      // Determine iteration count from array-valued captures.
      let iterCount: number | null = null;
      let firstArrayName: string | null = null;
      for (const name of captureNames) {
        const val = captures[name];
        if (Array.isArray(val)) {
          const cursor = cursors.get(name) ?? 0;
          const remaining = val.length - cursor;
          if (iterCount === null) {
            iterCount = remaining;
            firstArrayName = name;
          } else if (iterCount !== remaining) {
            throw {
              kind: "ArrayLengthError",
              captureName: name,
              length: val.length,
              min: minVal,
              max: maxVal,
            } satisfies SubstitutionError;
          }
        }
      }

      // No array captures: produce empty string when min=0 and all captures
      // are absent; otherwise error.
      if (iterCount === null) {
        if (minVal === 0) return "";
        throw { kind: "NoMatchingBranch" } satisfies SubstitutionError;
      }

      if (iterCount < minVal || (maxVal !== null && iterCount > maxVal)) {
        throw {
          kind: "ArrayLengthError",
          captureName: firstArrayName!,
          length: (captures[firstArrayName!] as string[]).length,
          min: minVal,
          max: maxVal,
        } satisfies SubstitutionError;
      }

      let out = "";
      for (let i = 0; i < iterCount; i++) {
        out += evaluatePlan(inner, captures, validators, ignoreMatching, cursors);
      }
      return out;
    }

    default:
      return "";
  }
}
