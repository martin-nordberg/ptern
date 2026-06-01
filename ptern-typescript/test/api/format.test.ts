import { describe, expect, it } from "bun:test";
import { format, PternFormatError } from "../../src/index";

describe("format errors", () => {
  it("throws PternFormatError on lex error", () => {
    expect(() => format("@")).toThrow(PternFormatError);
  });

  it("throws PternFormatError on parse error", () => {
    expect(() => format("")).toThrow(PternFormatError);
  });

  it("throws PternFormatError when lineWidth < 40", () => {
    expect(() => format("'x'", { lineWidth: 39 })).toThrow(PternFormatError);
    try {
      format("'x'", { lineWidth: 39 });
    } catch (e) {
      expect((e as PternFormatError).formatError.kind).toBe("invalidLineWidth");
    }
  });
});

describe("format basic", () => {
  it("formats a simple literal", () => {
    expect(format("'hello'")).toBe("'hello'");
  });

  it("formats annotation on its own line", () => {
    const result = format("!case-insensitive = true\n'hello'");
    expect(result).toContain("!case-insensitive = true");
    expect(result).toContain("'hello'");
  });

  it("formats definition and body", () => {
    const result = format("d = %Digit;\n{d} * 4");
    expect(result).toContain("d");
    expect(result).toContain("%Digit");
  });

  it("uses default options when none provided", () => {
    expect(() => format("'x'")).not.toThrow();
  });

  it("accepts lineWidth option", () => {
    expect(() => format("'hello'", { lineWidth: 80 })).not.toThrow();
  });

  it("compact mode removes spaces around pipe", () => {
    const result = format("'a' | 'b'", { compact: true });
    expect(result).toContain("|");
    expect(result).not.toContain(" | ");
  });

  it("non-compact mode has spaces around pipe", () => {
    const result = format("'a' | 'b'");
    expect(result).toContain(" | ");
  });
});

describe("format annotation sorting", () => {
  it("sorts annotations alphabetically", () => {
    const result = format("!multiline = true\n!case-insensitive = true\n'x'");
    const caseIdx = result.indexOf("case-insensitive");
    const multiIdx = result.indexOf("multiline");
    expect(caseIdx).toBeLessThan(multiIdx);
  });
});

describe("format definition alignment", () => {
  it("aligns = signs when aligned is true (default)", () => {
    const result = format("x = 'a';\nlonger = 'b';\n{x}");
    const lines = result.split("\n");
    const xLine = lines.find(l => l.startsWith("x"));
    const longerLine = lines.find(l => l.startsWith("longer"));
    if (xLine && longerLine) {
      const xEqCol = xLine.indexOf("=");
      const longerEqCol = longerLine.indexOf("=");
      expect(xEqCol).toBe(longerEqCol);
    }
  });

  it("does not align when aligned is false", () => {
    const result = format("x = 'a';\nlonger = 'b';\n{x}", { aligned: false });
    const lines = result.split("\n");
    const xLine = lines.find(l => l.startsWith("x"));
    const longerLine = lines.find(l => l.startsWith("longer"));
    if (xLine && longerLine) {
      expect(xLine).toContain("x = ");
      expect(longerLine).toContain("longer = ");
    }
  });
});

describe("format reordered definitions", () => {
  it("reorders definitions by dependency when reordered = true", () => {
    const result = format("b = {a} 'y';\na = 'x';\n{b}", { reordered: true });
    const lines = result.split("\n");
    const aLineIdx = lines.findIndex(l => l.startsWith("a"));
    const bLineIdx = lines.findIndex(l => l.startsWith("b"));
    expect(aLineIdx).toBeGreaterThanOrEqual(0);
    expect(bLineIdx).toBeGreaterThanOrEqual(0);
    expect(aLineIdx).toBeLessThan(bLineIdx);
  });
});

describe("format line breaking", () => {
  it("wraps long alternations", () => {
    const longPattern = "'verylongword1' | 'verylongword2' | 'verylongword3' | 'verylongword4'";
    const result = format(longPattern, { lineWidth: 40 });
    expect(result.split("\n").length).toBeGreaterThan(1);
  });

  it("does not wrap short patterns", () => {
    const result = format("'a' | 'b' | 'c'", { lineWidth: 80 });
    expect(result.split("\n")).toHaveLength(1);
  });
});
