import { describe, it, expect } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { lex } from "../src/lexer/lexer";
import { parse } from "../src/parser/parser";
import { compile as compileCodegen } from "../src/codegen/codegen";
import { compile, format, PternFormatError } from "../src/index";
import { validate } from "../src/semantic/validator";
import { resolve } from "../src/semantic/resolver";
import { check } from "../src/semantic/backtracking";
import type { ParsedPtern } from "../src/parser/ast";
import type { SemanticError } from "../src/semantic/error";

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
            case "minLength":
              expect(p.minLength()).toBe(c.expect as number);
              break;
            case "maxLength":
              expect(p.maxLength()).toBe(c.expect as number | null);
              break;
            default:
              throw new Error("unknown op: " + c.op);
          }
        });
      }
    });
  }
});

// ---------------------------------------------------------------------------
// Semantic validator fixtures
// ---------------------------------------------------------------------------

type SemanticFixture = { id: string; pattern: string; expect: string | { error: string } };

function lexAndParseUnsafe(pattern: string): ParsedPtern {
  const tokens = lex(pattern);
  if (!Array.isArray(tokens)) throw new Error("lex failed: " + JSON.stringify(tokens));
  const ast = parse(tokens);
  if ("kind" in ast) throw new Error("parse failed: " + JSON.stringify(ast));
  return ast as ParsedPtern;
}

describe("fixtures/semantic/validator", () => {
  const cases = load("semantic/validator.json") as SemanticFixture[];
  for (const c of cases) {
    it(c.id, () => {
      const parsed = lexAndParseUnsafe(c.pattern);
      const errors = validate(parsed);
      if (typeof c.expect === "string") {
        expect(errors).toEqual([]);
      } else {
        const kind = c.expect.error;
        expect(errors.some(e => (e as { kind: string }).kind === kind)).toBe(true);
      }
    });
  }
});

// ---------------------------------------------------------------------------
// Semantic resolver fixtures
// ---------------------------------------------------------------------------

describe("fixtures/semantic/resolver", () => {
  const cases = load("semantic/resolver.json") as SemanticFixture[];
  for (const c of cases) {
    it(c.id, () => {
      const parsed = lexAndParseUnsafe(c.pattern);
      // DuplicateCapture is filtered by the compile pipeline; fixture tests post-filter state
      const errors = resolve(parsed).filter(e => (e as { kind: string }).kind !== "duplicateCapture");
      if (typeof c.expect === "string") {
        expect(errors).toEqual([]);
      } else {
        const kind = c.expect.error;
        expect(errors.some(e => (e as { kind: string }).kind === kind)).toBe(true);
      }
    });
  }
});

// The raw resolver DOES produce duplicateCapture before the pipeline filters it.
// This test documents that intentional internal behaviour.
it("raw resolver reports duplicateCapture before pipeline filtering", () => {
  const parsed = lexAndParseUnsafe("'a' as x 'b' as x");
  const errors = resolve(parsed);
  expect(errors.some(e => (e as SemanticError & { kind: string }).kind === "duplicateCapture")).toBe(true);
});

// ---------------------------------------------------------------------------
// Semantic backtracking fixtures
// ---------------------------------------------------------------------------

type BacktrackingFixture = { id: string; pattern: string; expect: string | { error: string } };

describe("fixtures/semantic/backtracking", () => {
  const cases = load("semantic/backtracking.json") as BacktrackingFixture[];
  for (const c of cases) {
    it(c.id, () => {
      let threw = false;
      let errorKind = "";
      try {
        compile(c.pattern);
      } catch (e: unknown) {
        threw = true;
        const ce = e as { compileError?: { kind: string; errors?: { kind: string }[] } };
        if (ce.compileError?.kind === "semanticErrors" && ce.compileError.errors?.length) {
          errorKind = ce.compileError.errors[0]!.kind;
        }
      }
      if (typeof c.expect === "string") {
        expect(threw).toBe(false);
      } else {
        expect(threw).toBe(true);
        expect(errorKind).toBe(c.expect.error);
      }
    });
  }
});

// ---------------------------------------------------------------------------
// Format fixtures
// ---------------------------------------------------------------------------

type FormatFixture = { id: string; input: string; options?: Record<string, unknown>; expect: string | { error: string } };

describe("fixtures/format", () => {
  const cases = load("format/format.json") as FormatFixture[];
  for (const c of cases) {
    it(c.id, () => {
      const opts = c.options as Parameters<typeof format>[1] | undefined;
      if (typeof c.expect === "object" && "error" in c.expect) {
        let threw = false;
        let kind = "";
        try {
          format(c.input, opts);
        } catch (e: unknown) {
          threw = true;
          kind = (e as PternFormatError).formatError?.kind ?? "";
        }
        const expectedKind = c.expect.error === "lexError" ? "formatLexError"
          : c.expect.error === "parseError" ? "formatParseError"
          : c.expect.error;
        expect(threw).toBe(true);
        expect(kind).toBe(expectedKind);
      } else {
        expect(format(c.input, opts)).toBe(c.expect as string);
      }
    });
  }
});

// ---------------------------------------------------------------------------
// Parser AST structure tests (cannot be expressed in the error-only fixture format)
// ---------------------------------------------------------------------------

describe("parser/atom types", () => {
  it("parses single-quoted literal", () => {
    const ast = lexAndParse("'hello'");
    const atom = ast.body.alternatives[0]?.items[0]?.inner.inner.base.atom;
    expect(atom).toEqual({ kind: "literal", content: "hello" });
  });

  it("parses double-quoted literal", () => {
    const ast = lexAndParse('"world"');
    const atom = ast.body.alternatives[0]?.items[0]?.inner.inner.base.atom;
    expect(atom).toEqual({ kind: "literal", content: "world" });
  });

  it("parses char class", () => {
    const ast = lexAndParse("%Digit");
    const atom = ast.body.alternatives[0]?.items[0]?.inner.inner.base.atom;
    expect(atom).toEqual({ kind: "charClass", name: "Digit" });
  });

  it("parses group", () => {
    const ast = lexAndParse("('a' | 'b')");
    const atom = ast.body.alternatives[0]?.items[0]?.inner.inner.base.atom;
    expect(atom?.kind).toBe("group");
    if (atom?.kind === "group") expect(atom.inner.alternatives).toHaveLength(2);
  });

  it("parses char range", () => {
    const ast = lexAndParse("'a'..'z'");
    const item = ast.body.alternatives[0]?.items[0];
    expect(item?.inner.inner.base.kind).toBe("charRange");
  });

  it("parses position assertion", () => {
    const ast = lexAndParse("@word-start %Alpha * 1..?");
    const atom = ast.body.alternatives[0]?.items[0]?.inner.inner.base.atom;
    expect(atom).toEqual({ kind: "positionAssertion", name: "word-start" });
  });

  it("parses interpolation", () => {
    const ast = lexAndParse("d = %Digit;\n{d}");
    const atom = ast.body.alternatives[0]?.items[0]?.inner.inner.base.atom;
    expect(atom).toEqual({ kind: "interpolation", name: "d" });
  });
});

describe("parser/repetition counts", () => {
  function repCount(input: string) {
    const ast = lexAndParse(input);
    return ast.body.alternatives[0]?.items[0]?.inner.count;
  }

  it("exact repetition * 4", () => {
    const c = repCount("%Digit * 4");
    expect(c?.min).toBe(4);
    expect(c?.max).toEqual({ kind: "none" });
    expect(c?.lazy).toBe(false);
  });

  it("bounded repetition * 3..10", () => {
    const c = repCount("%Digit * 3..10");
    expect(c?.min).toBe(3);
    expect(c?.max).toEqual({ kind: "exact", value: 10 });
  });

  it("unbounded repetition * 1..?", () => {
    const c = repCount("%Digit * 1..?");
    expect(c?.min).toBe(1);
    expect(c?.max).toEqual({ kind: "unbounded" });
  });

  it("fewest * 1..? fewest", () => {
    const c = repCount("%Digit * 1..? fewest");
    expect(c?.min).toBe(1);
    expect(c?.lazy).toBe(true);
  });
});

describe("parser/capture and structure", () => {
  it("named capture", () => {
    const ast = lexAndParse("%Digit * 4 as year");
    expect(ast.body.alternatives[0]?.items[0]?.name).toBe("year");
  });

  it("sequence has two items", () => {
    const ast = lexAndParse("'a' 'b'");
    expect(ast.body.alternatives[0]?.items).toHaveLength(2);
  });

  it("two-way alternation", () => {
    const ast = lexAndParse("'a' | 'b'");
    expect(ast.body.alternatives).toHaveLength(2);
  });

  it("annotation value true", () => {
    const ast = lexAndParse("!case-insensitive = true\n\n'hello'");
    expect(ast.annotations[0]?.name).toBe("case-insensitive");
    expect(ast.annotations[0]?.value).toBe(true);
  });

  it("annotation value false", () => {
    const ast = lexAndParse("!multiline = false\n\n'hello'");
    expect(ast.annotations[0]?.value).toBe(false);
  });

  it("body comment stored in bodyComments", () => {
    const ast = lexAndParse("# describes the body\n'x'");
    expect(ast.bodyComments).toContain(" describes the body");
  });

  it("ptern-level comment stored in pternComments", () => {
    const ast = lexAndParse("# top comment\n\n'x'");
    expect(ast.pternComments).toContain(" top comment");
    expect(ast.bodyComments).toHaveLength(0);
  });

  it("definition comment stored on definition", () => {
    const ast = lexAndParse("# about word\nword = %Alpha * 1..? ;\n\n{word}");
    expect(ast.definitions[0]?.comments).toContain(" about word");
  });

  it("parses iso date pattern", () => {
    const input =
      "yyyy = %Digit * 4;\n" +
      "mm = ('0' '1'..'9') | ('1' '0'..'2');\n" +
      "dd = ('0' '1'..'9') | ('1'..'2' %Digit) | ('3' '0'..'1');\n" +
      "{yyyy} as year '-' {mm} as month '-' {dd} as day";
    const ast = lexAndParse(input);
    expect(ast.definitions).toHaveLength(3);
  });
});
