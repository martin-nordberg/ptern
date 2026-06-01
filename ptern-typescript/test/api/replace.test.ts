import { describe, expect, it } from "bun:test";
import { compile, PternReplacementError } from "../../src/index";

describe("replaceAllOf", () => {
  it("replaces a named capture in full match", () => {
    const p = compile("%Digit * 4 as year");
    expect(p.replaceAllOf("2024", { year: "2099" })).toBe("2099");
  });

  it("returns input unchanged when no full match", () => {
    const p = compile("%Digit * 4 as year");
    expect(p.replaceAllOf("abc", { year: "2099" })).toBe("abc");
  });

  it("throws on invalid replacement value", () => {
    const p = compile("%Digit * 4 as year");
    expect(() => p.replaceAllOf("2024", { year: "abcd" })).toThrow(PternReplacementError);
  });

  it("replaceAllOf with multiple captures", () => {
    const p = compile("%Alpha * 1..? as first '-' %Alpha * 1..? as last");
    expect(p.replaceAllOf("foo-bar", { first: "baz", last: "qux" })).toBe("baz-qux");
  });
});

describe("replaceStartOf", () => {
  it("replaces at start", () => {
    const p = compile("%Digit * 1..? as n");
    expect(p.replaceStartOf("123abc", { n: "999" })).toBe("999abc");
  });

  it("returns input unchanged when no start match", () => {
    const p = compile("%Digit * 1..? as n");
    expect(p.replaceStartOf("abc123", { n: "999" })).toBe("abc123");
  });
});

describe("replaceEndOf", () => {
  it("replaces at end", () => {
    const p = compile("%Digit * 1..? as n");
    expect(p.replaceEndOf("abc123", { n: "999" })).toBe("abc999");
  });
});

describe("replaceFirstIn", () => {
  it("replaces first occurrence", () => {
    const p = compile("%Digit * 1..? as n");
    expect(p.replaceFirstIn("abc 42 def 99", { n: "0" })).toBe("abc 0 def 99");
  });
});

describe("replaceNextIn", () => {
  it("replaces occurrence at or after startIndex", () => {
    const p = compile("%Digit * 1..? as n");
    expect(p.replaceNextIn("abc 42 def 99", 7, { n: "0" })).toBe("abc 42 def 0");
  });
});

describe("replaceAllIn", () => {
  it("replaces all occurrences", () => {
    const p = compile("!replacements-ignore-matching = true\n%Digit * 1..? as n");
    expect(p.replaceAllIn("a1 b22 c333", { n: "X" })).toBe("aX bX cX");
  });

  it("returns input unchanged when no match", () => {
    const p = compile("!replacements-ignore-matching = true\n%Digit * 1..? as n");
    expect(p.replaceAllIn("abcdef", { n: "X" })).toBe("abcdef");
  });
});

describe("replacement with array values (repetition groups)", () => {
  it("replaces each iteration of a repeated capture", () => {
    const p = compile("!replacements-ignore-matching = true\n(%Digit * 1..? as n ',') * 1..?");
    const input = "1,22,333,";
    const result = p.replaceAllOf(input, { n: ["A", "BB", "CCC"] });
    expect(result).toBe("A,BB,CCC,");
  });

  it("throws WrongReplacementType for array on non-repeated capture", () => {
    const p = compile("%Digit * 4 as year");
    expect(() => p.replaceAllOf("2024", { year: ["a", "b"] })).toThrow(PternReplacementError);
    try {
      p.replaceAllOf("2024", { year: ["a", "b"] });
    } catch (e) {
      expect((e as PternReplacementError).replacementError.kind).toBe("wrongReplacementType");
    }
  });
});

describe("replacements-ignore-matching annotation", () => {
  it("allows any replacement value with annotation", () => {
    const p = compile("!replacements-ignore-matching = true\n%Digit * 4 as year");
    expect(() => p.replaceAllOf("2024", { year: "abcd" })).not.toThrow();
    expect(p.replaceAllOf("2024", { year: "abcd" })).toBe("abcd");
  });
});
