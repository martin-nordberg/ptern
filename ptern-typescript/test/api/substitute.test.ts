import { describe, expect, it } from "bun:test";
import { compile, PternSubstitutionError } from "../../src/index";

describe("substitute errors", () => {
  it("throws NotSubstitutable when !substitutable not set", () => {
    const p = compile("%Digit * 4 as year");
    expect(() => p.substitute({ year: "2024" })).toThrow(PternSubstitutionError);
    try {
      p.substitute({ year: "2024" });
    } catch (e) {
      expect((e as PternSubstitutionError).substitutionError.kind).toBe("notSubstitutable");
    }
  });

  it("throws MissingCapture when capture not provided", () => {
    const p = compile("!substitutable = true\n%Digit * 4 as year");
    expect(() => p.substitute({})).toThrow(PternSubstitutionError);
    try {
      p.substitute({});
    } catch (e) {
      const err = (e as PternSubstitutionError).substitutionError;
      expect(err.kind).toBe("missingCapture");
      if (err.kind === "missingCapture") expect(err.name).toBe("year");
    }
  });

  it("throws CaptureMismatch when value doesn't match pattern", () => {
    const p = compile("!substitutable = true\n%Digit * 4 as year");
    expect(() => p.substitute({ year: "abcd" })).toThrow(PternSubstitutionError);
    try {
      p.substitute({ year: "abcd" });
    } catch (e) {
      const err = (e as PternSubstitutionError).substitutionError;
      expect(err.kind).toBe("captureMismatch");
    }
  });
});

describe("substitute success", () => {
  it("substitutes a single capture", () => {
    const p = compile("!substitutable = true\n%Digit * 4 as year");
    expect(p.substitute({ year: "2024" })).toBe("2024");
  });

  it("substitutes multiple captures", () => {
    const p = compile(
      "!substitutable = true\n" +
      "%Digit * 4 as year '-' %Digit * 2 as month '-' %Digit * 2 as day",
    );
    expect(p.substitute({ year: "2024", month: "03", day: "15" })).toBe("2024-03-15");
  });

  it("substitutes literal text between captures", () => {
    const p = compile("!substitutable = true\n%Alpha * 1..? as first ' ' %Alpha * 1..? as last");
    expect(p.substitute({ first: "John", last: "Doe" })).toBe("John Doe");
  });

  it("substitutes alternation by trying each branch", () => {
    const p = compile(
      "!substitutable = true\n" +
      "(%Alpha * 1..? as word) | (%Digit * 1..? as num)",
    );
    expect(p.substitute({ word: "hello" })).toBe("hello");
    expect(p.substitute({ num: "42" })).toBe("42");
  });

  it("substitute with array values (bounded repetition)", () => {
    const p = compile(
      "!substitutable = true\n" +
      "(%Digit * 1..? as n '-') * 1..?",
    );
    expect(p.substitute({ n: ["1", "22", "333"] })).toBe("1-22-333-");
  });

  it("substitutions-ignore-matching allows invalid values", () => {
    const p = compile(
      "!substitutable = true\n" +
      "!substitutions-ignore-matching = true\n" +
      "%Digit * 4 as year",
    );
    expect(p.substitute({ year: "abcd" })).toBe("abcd");
  });
});
