import { describe, expect, it } from "bun:test";
import { lex } from "../../src/lexer/lexer";
import { parse } from "../../src/parser/parser";
import { resolve } from "../../src/semantic/resolver";
import type { ParsedPtern } from "../../src/parser/ast";
import type { SemanticError } from "../../src/semantic/error";

function resolveInput(input: string): SemanticError[] {
  const tokens = lex(input);
  if (!Array.isArray(tokens)) throw new Error("lex failed: " + JSON.stringify(tokens));
  const ast = parse(tokens);
  if ("kind" in ast) throw new Error("parse failed: " + JSON.stringify(ast));
  return resolve(ast as ParsedPtern);
}

function hasError(errs: SemanticError[], target: SemanticError): boolean {
  return errs.some(e => JSON.stringify(e) === JSON.stringify(target));
}

// ---------------------------------------------------------------------------
// No errors — valid patterns
// ---------------------------------------------------------------------------

describe("valid patterns", () => {
  it("simple literal", () => {
    expect(resolveInput("'hello'")).toEqual([]);
  });

  it("definition and interpolation", () => {
    expect(resolveInput("d = %Digit; {d}")).toEqual([]);
  });

  it("multiple definitions", () => {
    expect(resolveInput("a = 'x'; b = 'y'; {a} {b}")).toEqual([]);
  });

  it("body capture", () => {
    expect(resolveInput("%Digit * 4 as year")).toEqual([]);
  });

  it("definition reference in body", () => {
    expect(resolveInput("d = %Digit * 4; {d} as year")).toEqual([]);
  });
});

// ---------------------------------------------------------------------------
// Duplicate definitions
// ---------------------------------------------------------------------------

describe("duplicateDefinition", () => {
  it("duplicate definition", () => {
    const errs = resolveInput("foo = 'a'; foo = 'b'; {foo}");
    expect(hasError(errs, { kind: "duplicateDefinition", name: "foo" })).toBe(true);
  });

  it("duplicate definition three times", () => {
    const errs = resolveInput("d = 'a'; d = 'b'; d = 'c'; {d}");
    expect(hasError(errs, { kind: "duplicateDefinition", name: "d" })).toBe(true);
  });
});

// ---------------------------------------------------------------------------
// Circular definitions
// ---------------------------------------------------------------------------

describe("circularDefinition", () => {
  it("self-reference", () => {
    const errs = resolveInput("a = {a}; {a}");
    expect(hasError(errs, { kind: "circularDefinition", names: ["a"] })).toBe(true);
  });

  it("two-node cycle", () => {
    const errs = resolveInput("a = {b}; b = {a}; {a}");
    expect(hasError(errs, { kind: "circularDefinition", names: ["a", "b"] })).toBe(true);
  });

  it("no circular with chain", () => {
    expect(resolveInput("a = 'x'; b = {a}; {b}")).toEqual([]);
  });
});

// ---------------------------------------------------------------------------
// Undefined references
// ---------------------------------------------------------------------------

describe("undefinedReference", () => {
  it("undefined interpolation in body", () => {
    expect(resolveInput("{foo}")).toEqual([{ kind: "undefinedReference", name: "foo" }]);
  });

  it("undefined interpolation in definition", () => {
    const errs = resolveInput("a = {missing}; {a}");
    expect(hasError(errs, { kind: "undefinedReference", name: "missing" })).toBe(true);
  });

  it("backreference to capture is valid", () => {
    expect(resolveInput("%Digit * 4 as year '-' {year}")).toEqual([]);
  });
});

// ---------------------------------------------------------------------------
// Duplicate captures
// ---------------------------------------------------------------------------

describe("duplicateCapture", () => {
  it("duplicate capture in body", () => {
    expect(resolveInput("%Digit * 4 as year '-' %Digit * 2 as year")).toEqual([
      { kind: "duplicateCapture", name: "year" },
    ]);
  });

  it("duplicate capture three times", () => {
    const errs = resolveInput("'a' as x '-' 'b' as x '-' 'c' as x");
    expect(hasError(errs, { kind: "duplicateCapture", name: "x" })).toBe(true);
  });
});

// ---------------------------------------------------------------------------
// Capture / definition name conflict
// ---------------------------------------------------------------------------

describe("captureDefinitionConflict", () => {
  it("capture name matches definition name", () => {
    const errs = resolveInput("year = %Digit * 4; {year} as year");
    expect(hasError(errs, { kind: "captureDefinitionConflict", name: "year" })).toBe(true);
  });

  it("capture inside definition matches definition name", () => {
    const errs = resolveInput("year = %Digit * 4 as year; {year}");
    expect(hasError(errs, { kind: "captureDefinitionConflict", name: "year" })).toBe(true);
  });
});

// ---------------------------------------------------------------------------
// Multiple independent errors collected together
// ---------------------------------------------------------------------------

describe("multiple errors collected", () => {
  it("two undefined refs and duplicate definition", () => {
    const errs = resolveInput("d = 'a'; d = 'b'; {x} {y}");
    expect(hasError(errs, { kind: "duplicateDefinition", name: "d" })).toBe(true);
    expect(hasError(errs, { kind: "undefinedReference", name: "x" })).toBe(true);
    expect(hasError(errs, { kind: "undefinedReference", name: "y" })).toBe(true);
  });
});

// ---------------------------------------------------------------------------
// Unused definitions
// ---------------------------------------------------------------------------

describe("unusedDefinition", () => {
  it("single unused definition", () => {
    const errs = resolveInput("spare = 'x'; 'y'");
    expect(hasError(errs, { kind: "unusedDefinition", name: "spare" })).toBe(true);
  });

  it("two defs, one used — unused one flagged", () => {
    const errs = resolveInput("a = 'x'; b = 'y'; {a}");
    expect(hasError(errs, { kind: "unusedDefinition", name: "b" })).toBe(true);
    expect(hasError(errs, { kind: "unusedDefinition", name: "a" })).toBe(false);
  });

  it("chain neither reachable", () => {
    const errs = resolveInput("a = 'x'; b = {a}; 'y'");
    expect(hasError(errs, { kind: "unusedDefinition", name: "a" })).toBe(true);
    expect(hasError(errs, { kind: "unusedDefinition", name: "b" })).toBe(true);
  });

  it("chain transitively reachable — no unused error", () => {
    expect(resolveInput("a = 'x'; b = {a} 'y'; {b}")).toEqual([]);
  });
});
