import { describe, expect, it } from "bun:test";
import { compile, PternCompileError, PternSubstitutionError } from "../../src/index";
import type { SemanticError } from "../../src/semantic/error";

function hasSemanticError(src: string, target: SemanticError): boolean {
  try {
    compile(src);
    return false;
  } catch (e) {
    if (e instanceof PternCompileError && e.compileError.kind === "semanticErrors") {
      return e.compileError.errors.some(
        err => JSON.stringify(err) === JSON.stringify(target),
      );
    }
    return false;
  }
}

// ---------------------------------------------------------------------------
// Substitution — compile-time errors
// ---------------------------------------------------------------------------

describe("substitution compile-time errors", () => {
  it("bare charclass without capture is notSubstitutableBody", () => {
    expect(hasSemanticError("!substitutable = true\n%Digit", { kind: "notSubstitutableBody" })).toBe(true);
  });

  it("substitutions-ignore-matching without substitutable", () => {
    expect(hasSemanticError(
      "!substitutions-ignore-matching = true\n'hello'",
      { kind: "substitutionsIgnoreMatchingWithoutSubstitutable" },
    )).toBe(true);
  });

  it("bounded rep without capture needs capture", () => {
    expect(hasSemanticError("!substitutable = true\n%Digit * 1..4", { kind: "boundedRepetitionNeedsCapture" })).toBe(true);
  });

  it("substitutable with literal compiles ok", () => {
    expect(() => compile("!substitutable = true\n'hello'")).not.toThrow();
  });

  it("substitutable with named capture compiles ok", () => {
    expect(() => compile("!substitutable = true\n%Digit * 4 as year")).not.toThrow();
  });

  it("substitutable with bounded rep and capture compiles ok", () => {
    expect(() => compile("!substitutable = true\n%Any * 1..100 as field")).not.toThrow();
  });

  it("substitutable with ignore-matching compiles ok", () => {
    expect(() => compile("!substitutable = true\n!substitutions-ignore-matching = true\n'hello'")).not.toThrow();
  });

  it("substitutable with duplicate captures compiles ok", () => {
    expect(() => compile(
      "!substitutable = true\nword = %Alpha * 1..20;\n'<' {word} as tag '>' {word} as body '</' {word} as tag '>'",
    )).not.toThrow();
  });

  it("substitutable iso date compiles ok", () => {
    expect(() => compile(
      "!substitutable = true\nyyyy = %Digit * 4;\nmm = '0' '1'..'9' | '1' '0'..'2';\ndd = '0' '1'..'9' | '1'..'2' %Digit | '3' '0'..'1';\n{yyyy} as year '-' {mm} as month '-' {dd} as day",
    )).not.toThrow();
  });

  it("substitutable csv compiles ok", () => {
    expect(() => compile(
      "!substitutable = true\nfield = %Any excluding ',' * 1..100;\n{field} as col (',' {field} as col) * 0..20",
    )).not.toThrow();
  });
});

// ---------------------------------------------------------------------------
// substitute — NotSubstitutable
// ---------------------------------------------------------------------------

describe("substitute NotSubstitutable", () => {
  it("throws notSubstitutable when !substitutable not set", () => {
    const p = compile("%Digit * 4 as year");
    expect(() => p.substitute({ year: "2026" })).toThrow(PternSubstitutionError);
    try {
      p.substitute({ year: "2026" });
    } catch (e) {
      expect((e as PternSubstitutionError).substitutionError.kind).toBe("notSubstitutable");
    }
  });
});

// ---------------------------------------------------------------------------
// substitute — literal-only pattern
// ---------------------------------------------------------------------------

describe("substitute literal pattern", () => {
  it("returns literal text with empty captures", () => {
    const p = compile("!substitutable = true\n'hello'");
    expect(p.substitute({})).toBe("hello");
  });

  it("extra keys ignored", () => {
    const p = compile("!substitutable = true\n'hello'");
    expect(p.substitute({ x: "y" })).toBe("hello");
  });
});

// ---------------------------------------------------------------------------
// substitute — scalar capture
// ---------------------------------------------------------------------------

describe("substitute scalar capture", () => {
  it("single capture", () => {
    const p = compile("!substitutable = true\n%Digit * 4 as year");
    expect(p.substitute({ year: "2026" })).toBe("2026");
  });

  it("sequence of captures", () => {
    const p = compile("!substitutable = true\n%Digit * 4 as year '-' %Digit * 2 as month '-' %Digit * 2 as day");
    expect(p.substitute({ year: "2026", month: "04", day: "28" })).toBe("2026-04-28");
  });

  it("missing capture with class body falls through to MissingCapture", () => {
    const p = compile("!substitutable = true\n'v' %Digit as ver");
    expect(() => p.substitute({})).toThrow(PternSubstitutionError);
    try {
      p.substitute({});
    } catch (e) {
      const err = (e as PternSubstitutionError).substitutionError;
      expect(err.kind).toBe("missingCapture");
      if (err.kind === "missingCapture") expect(err.name).toBe("ver");
    }
  });
});

// ---------------------------------------------------------------------------
// substitute — MissingCapture
// ---------------------------------------------------------------------------

describe("substitute MissingCapture", () => {
  it("throws missingCapture when capture not provided", () => {
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
});

// ---------------------------------------------------------------------------
// substitute — CaptureMismatch (validation)
// ---------------------------------------------------------------------------

describe("substitute CaptureMismatch", () => {
  it("throws captureMismatch when value doesn't match pattern", () => {
    const p = compile("!substitutable = true\n%Digit * 4 as year");
    expect(() => p.substitute({ year: "abcd" })).toThrow(PternSubstitutionError);
    try {
      p.substitute({ year: "abcd" });
    } catch (e) {
      const err = (e as PternSubstitutionError).substitutionError;
      expect(err.kind).toBe("captureMismatch");
      if (err.kind === "captureMismatch") {
        expect(err.name).toBe("year");
        expect(err.value).toBe("abcd");
      }
    }
  });

  it("ignore-matching skips validation", () => {
    const p = compile("!substitutable = true\n!substitutions-ignore-matching = true\n%Digit * 4 as year");
    expect(p.substitute({ year: "YYYY" })).toBe("YYYY");
  });
});

// ---------------------------------------------------------------------------
// substitute — alternation (NoMatchingBranch)
// ---------------------------------------------------------------------------

describe("substitute alternation", () => {
  it("first branch taken when first capture provided", () => {
    const p = compile("!substitutable = true\n%Digit * 4 as year | %Alpha * 1..? as word");
    expect(p.substitute({ year: "2026" })).toBe("2026");
  });

  it("second branch taken when second capture provided", () => {
    const p = compile("!substitutable = true\n%Digit * 4 as year | %Alpha * 1..? as word");
    expect(p.substitute({ word: "hello" })).toBe("hello");
  });

  it("throws noMatchingBranch when no captures provided", () => {
    const p = compile("!substitutable = true\n%Digit * 4 as year | %Alpha * 1..? as word");
    expect(() => p.substitute({})).toThrow(PternSubstitutionError);
    try {
      p.substitute({});
    } catch (e) {
      expect((e as PternSubstitutionError).substitutionError.kind).toBe("noMatchingBranch");
    }
  });
});

// ---------------------------------------------------------------------------
// substitute — fixed repetition
// ---------------------------------------------------------------------------

describe("substitute fixed repetition", () => {
  it("scalar value broadcasts to all iterations", () => {
    const p = compile("!substitutable = true\n(%Digit as d) * 3");
    expect(p.substitute({ d: "7" })).toBe("777");
  });

  it("array values consumed positionally", () => {
    const p = compile("!substitutable = true\n(%Digit as d) * 3");
    expect(p.substitute({ d: ["1", "2", "3"] })).toBe("123");
  });
});

// ---------------------------------------------------------------------------
// substitute — bounded repetition
// ---------------------------------------------------------------------------

describe("substitute bounded repetition", () => {
  it("CSV with array", () => {
    const p = compile("!substitutable = true\nfield = %Any excluding ',' * 1..20;\n{field} as col (',' {field} as col) * 0..5");
    expect(p.substitute({ col: ["alice", "bob", "carol"] })).toBe("alice,bob,carol");
  });

  it("min=0 with empty array gives zero iterations", () => {
    const p = compile("!substitutable = true\n'[' (%Digit as d ',' ) * 0..5 ']'");
    expect(p.substitute({ d: [] })).toBe("[]");
  });
});

// ---------------------------------------------------------------------------
// substitute — ArrayLengthError
// ---------------------------------------------------------------------------

describe("substitute ArrayLengthError", () => {
  it("throws when array below min", () => {
    const p = compile("!substitutable = true\n(%Digit as d) * 3..5");
    expect(() => p.substitute({ d: ["1", "2"] })).toThrow(PternSubstitutionError);
    try {
      p.substitute({ d: ["1", "2"] });
    } catch (e) {
      const err = (e as PternSubstitutionError).substitutionError;
      expect(err.kind).toBe("arrayLengthError");
      if (err.kind === "arrayLengthError") {
        expect(err.name).toBe("d");
        expect(err.length).toBe(2);
        expect(err.min).toBe(3);
        expect(err.max).toBe(5);
      }
    }
  });

  it("throws when array above max", () => {
    const p = compile("!substitutable = true\n(%Digit as d) * 1..3");
    expect(() => p.substitute({ d: ["1", "2", "3", "4", "5"] })).toThrow(PternSubstitutionError);
    try {
      p.substitute({ d: ["1", "2", "3", "4", "5"] });
    } catch (e) {
      const err = (e as PternSubstitutionError).substitutionError;
      expect(err.kind).toBe("arrayLengthError");
      if (err.kind === "arrayLengthError") {
        expect(err.name).toBe("d");
        expect(err.length).toBe(5);
        expect(err.min).toBe(1);
        expect(err.max).toBe(3);
      }
    }
  });
});

// ---------------------------------------------------------------------------
// substitute — subpattern definitions
// ---------------------------------------------------------------------------

describe("substitute with definitions", () => {
  it("substitutes using definition-resolved pattern", () => {
    const p = compile(
      "!substitutable = true\nyyyy = %Digit * 4;\nmm = %Digit * 2;\ndd = %Digit * 2;\n{yyyy} as year '-' {mm} as month '-' {dd} as day",
    );
    expect(p.substitute({ year: "2026", month: "04", day: "28" })).toBe("2026-04-28");
  });
});

// ---------------------------------------------------------------------------
// substitute — duplicate capture name
// ---------------------------------------------------------------------------

describe("substitute duplicate capture", () => {
  it("same value applied at all positions", () => {
    const p = compile(
      "!substitutable = true\nword = %Alpha * 1..20;\n'<' {word} as tag '>' {word} as body '</' {word} as tag '>'",
    );
    expect(p.substitute({ tag: "em", body: "hello" })).toBe("<em>hello</em>");
  });
});

// ---------------------------------------------------------------------------
// substitute — array capture consumed positionally
// ---------------------------------------------------------------------------

describe("substitute array consumed in order", () => {
  it("array values consumed in iteration order", () => {
    const p = compile("!substitutable = true\n(%Alpha * 1..? as w ' ') * 1..4");
    expect(p.substitute({ w: ["one", "two", "three"] })).toBe("one two three ");
  });
});

// ---------------------------------------------------------------------------
// substitute — array CaptureMismatch
// ---------------------------------------------------------------------------

describe("substitute array element mismatch", () => {
  it("throws captureMismatch for bad array element", () => {
    const p = compile("!substitutable = true\n(%Digit as d) * 3");
    expect(() => p.substitute({ d: ["1", "x", "3"] })).toThrow(PternSubstitutionError);
    try {
      p.substitute({ d: ["1", "x", "3"] });
    } catch (e) {
      const err = (e as PternSubstitutionError).substitutionError;
      expect(err.kind).toBe("captureMismatch");
      if (err.kind === "captureMismatch") expect(err.value).toBe("x");
    }
  });
});

// ---------------------------------------------------------------------------
// substitute — unbounded repetition (min..?)
// ---------------------------------------------------------------------------

describe("substitute unbounded repetition", () => {
  it("array consumed until exhausted", () => {
    const p = compile("!substitutable = true\n(%Alpha * 1..? as w ' ') * 1..?");
    expect(p.substitute({ w: ["a", "bb", "ccc"] })).toBe("a bb ccc ");
  });

  it("unbounded rep accepts any length >= min", () => {
    const p = compile("!substitutable = true\n(%Digit as d) * 1..?");
    expect(p.substitute({ d: ["1", "2", "3", "4", "5"] })).toBe("12345");
  });

  it("throws when below min for unbounded", () => {
    const p = compile("!substitutable = true\n(%Digit as d) * 3..?");
    expect(() => p.substitute({ d: ["1", "2"] })).toThrow(PternSubstitutionError);
    try {
      p.substitute({ d: ["1", "2"] });
    } catch (e) {
      const err = (e as PternSubstitutionError).substitutionError;
      expect(err.kind).toBe("arrayLengthError");
      if (err.kind === "arrayLengthError") {
        expect(err.name).toBe("d");
        expect(err.length).toBe(2);
        expect(err.min).toBe(3);
        expect(err.max).toBeNull();
      }
    }
  });
});

// ---------------------------------------------------------------------------
// substitute — empty string values
// ---------------------------------------------------------------------------

describe("substitute empty string values", () => {
  it("empty scalar validates as captureMismatch", () => {
    const p = compile("!substitutable = true\n%Digit * 4 as year");
    expect(() => p.substitute({ year: "" })).toThrow(PternSubstitutionError);
    try {
      p.substitute({ year: "" });
    } catch (e) {
      expect((e as PternSubstitutionError).substitutionError.kind).toBe("captureMismatch");
    }
  });

  it("empty scalar with ignore-matching gives empty slot", () => {
    const p = compile("!substitutable = true\n!substitutions-ignore-matching = true\n'[' %Digit as d ']'");
    expect(p.substitute({ d: "" })).toBe("[]");
  });

  it("empty array element with ignore-matching omits that iteration", () => {
    const p = compile("!substitutable = true\n!substitutions-ignore-matching = true\n(%Digit as d) * 3");
    expect(p.substitute({ d: ["1", "", "3"] })).toBe("13");
  });
});

// ---------------------------------------------------------------------------
// Substitution — edge cases
// ---------------------------------------------------------------------------

describe("substitution edge cases", () => {
  it("alternation literal fallback branch", () => {
    const p = compile("!substitutable = true\n%Digit * 4 as year | 'unknown'");
    expect(p.substitute({})).toBe("unknown");
  });

  it("alternation mismatch propagates immediately", () => {
    const p = compile("!substitutable = true\n%Digit * 4 as year | %Alpha * 1..? as word");
    expect(() => p.substitute({ year: "abcd" })).toThrow(PternSubstitutionError);
    try {
      p.substitute({ year: "abcd" });
    } catch (e) {
      expect((e as PternSubstitutionError).substitutionError.kind).toBe("captureMismatch");
    }
  });

  it("missing capture falls back to literal inner", () => {
    const p = compile("!substitutable = true\n'prefix-' 'X' as ver");
    expect(p.substitute({})).toBe("prefix-X");
  });

  it("mismatched array lengths for two captures", () => {
    const p = compile("!substitutable = true\n(%Digit as a %Alpha as b) * 1..3");
    expect(() => p.substitute({ a: ["1", "2", "3"], b: ["x", "y"] })).toThrow(PternSubstitutionError);
  });

  it("scalar for bounded rep min=0 gives empty", () => {
    const p = compile("!substitutable = true\n(%Digit as d) * 0..3");
    expect(p.substitute({ d: "5" })).toBe("");
  });

  it("three-branch alternation selects second branch", () => {
    const p = compile("!substitutable = true\n%Digit * 4 as year | %Alpha * 1..? as word | 'fallback'");
    expect(p.substitute({ word: "hello" })).toBe("hello");
    expect(p.substitute({})).toBe("fallback");
  });
});
