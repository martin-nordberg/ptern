import { describe, it, expect } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { lex } from "../src/lexer/lexer";
import { parse } from "../src/parser/parser";
import { compile as compileCodegen } from "../src/codegen/codegen";
import { compile } from "../src/index";
import type { ParsedPtern } from "../src/parser/ast";

const fixturesDir = join(import.meta.dir, "../../test-fixtures");

function load(rel: string): unknown[] {
  return JSON.parse(readFileSync(join(fixturesDir, rel), "utf-8")) as unknown[];
}

function lexAndParse(input: string): ParsedPtern {
  const tokens = lex(input);
  if (!Array.isArray(tokens)) throw new Error("lex failed: " + JSON.stringify(tokens));
  const ast = parse(tokens);
  if ("kind" in ast) throw new Error("parse failed: " + JSON.stringify(ast));
  return ast as ParsedPtern;
}

// ---------------------------------------------------------------------------
// Codegen fixtures
// ---------------------------------------------------------------------------

type CodegenFixture = { id: string; pattern: string; expect: { source: string; flags: string } };

describe("fixtures/codegen", () => {
  const cases = load("codegen/codegen.json") as CodegenFixture[];
  for (const c of cases) {
    it(c.id, () => {
      const result = compileCodegen(lexAndParse(c.pattern));
      expect(result.source).toBe(c.expect.source);
      expect(result.flags).toBe(c.expect.flags);
    });
  }
});

// ---------------------------------------------------------------------------
// Lexer fixtures
// ---------------------------------------------------------------------------

type LexerFixture = { id: string; input: string; expect: unknown };

describe("fixtures/lexer", () => {
  const cases = load("lexer/lexer.json") as LexerFixture[];
  for (const c of cases) {
    it(c.id, () => {
      const result = lex(c.input);
      if (Array.isArray(c.expect)) {
        expect(result).toEqual(c.expect);
      } else {
        expect(Array.isArray(result)).toBe(false);
        const err = c.expect as { error: string };
        expect((result as { kind: string }).kind).toBe(err.error);
      }
    });
  }
});

// ---------------------------------------------------------------------------
// Parser fixtures
// ---------------------------------------------------------------------------

type ParserFixture = { id: string; input: string; expect: { error: string } };

describe("fixtures/parser", () => {
  const cases = load("parser/parser.json") as ParserFixture[];
  for (const c of cases) {
    it(c.id, () => {
      const tokens = lex(c.input);
      if (!Array.isArray(tokens)) throw new Error("unexpected lex error: " + JSON.stringify(tokens));
      const result = parse(tokens);
      expect("kind" in result).toBe(true);
      expect((result as { kind: string }).kind).toBe(c.expect.error);
    });
  }
});

// ---------------------------------------------------------------------------
// API compile-error fixtures
// ---------------------------------------------------------------------------

type CompileFixture = { id: string; pattern: string; expect: { error: string } };

describe("fixtures/api/compile", () => {
  const cases = load("api/compile.json") as CompileFixture[];
  for (const c of cases) {
    it(c.id, () => {
      let threw = false;
      let kind = "";
      try {
        compile(c.pattern);
      } catch (e: unknown) {
        threw = true;
        kind = (e as { compileError?: { kind: string } }).compileError?.kind ?? "";
      }
      expect(threw).toBe(true);
      expect(kind).toBe(c.expect.error);
    });
  }
});

// ---------------------------------------------------------------------------
// API operation fixtures (match / replace / substitute)
// ---------------------------------------------------------------------------

type OccurrenceExpect = { index: number; length: number; captures: Record<string, string> };

type ApiCase = {
  op: string;
  input?: string;
  startIndex?: number;
  expect: unknown;
  replacements?: Record<string, string | string[]>;
  captures?: Record<string, string | string[]>;
};

type ApiFixture = { id: string; pattern: string; cases: ApiCase[] };

describe("fixtures/api", () => {
  const fixtures = load("api/api.json") as ApiFixture[];
  for (const f of fixtures) {
    describe(f.id, () => {
      const p = compile(f.pattern);
      for (const c of f.cases) {
        const label = c.input !== undefined
          ? `${c.op}(${JSON.stringify(c.input)})`
          : `${c.op}(${JSON.stringify(c.captures)})`;
        it(label, () => {
          const input = c.input ?? "";
          switch (c.op) {
            case "matchesAllOf":
              expect(p.matchesAllOf(input)).toBe(c.expect as boolean);
              break;
            case "matchesStartOf":
              expect(p.matchesStartOf(input)).toBe(c.expect as boolean);
              break;
            case "matchesEndOf":
              expect(p.matchesEndOf(input)).toBe(c.expect as boolean);
              break;
            case "matchesIn":
              expect(p.matchesIn(input)).toBe(c.expect as boolean);
              break;
            case "matchAllOf":
              expect(p.matchAllOf(input)).toEqual(c.expect as OccurrenceExpect | null);
              break;
            case "matchStartOf":
              expect(p.matchStartOf(input)).toEqual(c.expect as OccurrenceExpect | null);
              break;
            case "matchEndOf":
              expect(p.matchEndOf(input)).toEqual(c.expect as OccurrenceExpect | null);
              break;
            case "matchFirstIn":
              expect(p.matchFirstIn(input)).toEqual(c.expect as OccurrenceExpect | null);
              break;
            case "matchNextIn":
              expect(p.matchNextIn(input, c.startIndex ?? 0)).toEqual(c.expect as OccurrenceExpect | null);
              break;
            case "matchAllIn":
              expect(p.matchAllIn(input)).toEqual(c.expect as OccurrenceExpect[]);
              break;
            case "replaceAllOf":
              expect(p.replaceAllOf(input, c.replacements ?? {})).toBe(c.expect as string);
              break;
            case "replaceStartOf":
              expect(p.replaceStartOf(input, c.replacements ?? {})).toBe(c.expect as string);
              break;
            case "replaceEndOf":
              expect(p.replaceEndOf(input, c.replacements ?? {})).toBe(c.expect as string);
              break;
            case "replaceFirstIn":
              expect(p.replaceFirstIn(input, c.replacements ?? {})).toBe(c.expect as string);
              break;
            case "replaceNextIn":
              expect(p.replaceNextIn(input, c.startIndex ?? 0, c.replacements ?? {})).toBe(c.expect as string);
              break;
            case "replaceAllIn":
              expect(p.replaceAllIn(input, c.replacements ?? {})).toBe(c.expect as string);
              break;
            case "substitute":
              expect(p.substitute(c.captures ?? {})).toBe(c.expect as string);
              break;
            default:
              throw new Error("unknown op: " + c.op);
          }
        });
      }
    });
  }
});
