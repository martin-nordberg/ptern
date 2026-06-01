import { describe, expect, it } from "bun:test";
import { lex } from "../../src/lexer/lexer";
import { parse } from "../../src/parser/parser";
import type { ParseError } from "../../src/parser/ast";

function parseInput(input: string): ReturnType<typeof parse> {
  const tokens = lex(input);
  if (!Array.isArray(tokens)) throw new Error("lex failed: " + JSON.stringify(tokens));
  return parse(tokens);
}

function isError(result: ReturnType<typeof parse>): result is ParseError {
  return "kind" in result;
}

describe("parser errors", () => {
  it("empty input returns unexpectedEndOfInput", () => {
    const result = parseInput("");
    expect(result).toEqual({ kind: "unexpectedEndOfInput" });
  });

  it("unclosed group returns unexpectedToken expecting )", () => {
    const result = parseInput("('a'");
    expect(result).toEqual({
      kind: "unexpectedToken",
      expected: ")",
      got: "end of input",
    });
  });

  it("missing semicolon on definition returns unexpectedToken", () => {
    const result = parseInput("d = %Digit {d}");
    expect(result).toEqual({
      kind: "unexpectedToken",
      expected: ";",
      got: "end of input",
    });
  });

  it("stray token after body returns error", () => {
    const result = parseInput("'a' )");
    expect(isError(result)).toBe(true);
  });

  it("orphaned comment after annotation followed by blank line", () => {
    const result = parseInput("!case-insensitive = true\n# orphaned\n\n'x'");
    expect(result).toEqual({ kind: "orphanedComment" });
  });

  it("trailing comment after body expression", () => {
    const result = parseInput("'x'\n# trailing");
    expect(result).toEqual({ kind: "trailingComment" });
  });

  it("orphaned comment before body with blank line", () => {
    const result = parseInput("d = %Digit;\n# orphaned\n\n{d}");
    expect(result).toEqual({ kind: "orphanedComment" });
  });
});

describe("parser success", () => {
  it("parses iso date pattern", () => {
    const input =
      "yyyy = %Digit * 4;\n" +
      "mm = ('0' '1'..'9') | ('1' '0'..'2');\n" +
      "dd = ('0' '1'..'9') | ('1'..'2' %Digit) | ('3' '0'..'1');\n" +
      "{yyyy} as year '-' {mm} as month '-' {dd} as day";
    const result = parseInput(input);
    expect(isError(result)).toBe(false);
  });

  it("parses group in alternation", () => {
    const result = parseInput("('a' | 'b') 'c'");
    expect(isError(result)).toBe(false);
  });

  it("parses a single-quoted literal", () => {
    const result = parseInput("'hello'");
    expect(isError(result)).toBe(false);
    if (!isError(result)) {
      expect(result.body.alternatives).toHaveLength(1);
    }
  });

  it("parses annotation and body", () => {
    const result = parseInput("!case-insensitive = true\n\n'hello'");
    expect(isError(result)).toBe(false);
    if (!isError(result)) {
      expect(result.annotations).toHaveLength(1);
      expect(result.annotations[0]!.name).toBe("case-insensitive");
      expect(result.annotations[0]!.value).toBe(true);
    }
  });

  it("parses definition and body", () => {
    const result = parseInput("d = %Digit;\n\n{d} * 4");
    expect(isError(result)).toBe(false);
    if (!isError(result)) {
      expect(result.definitions).toHaveLength(1);
      expect(result.definitions[0]!.name).toBe("d");
    }
  });
});
