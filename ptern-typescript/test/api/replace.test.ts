import { describe, expect, it } from "bun:test";
import { compile, PternReplacementError } from "../../src/index";

// ---------------------------------------------------------------------------
// replaceAllOf / replaceStartOf / replaceEndOf
// replaceFirstIn / replaceNextIn / replaceAllIn
// ---------------------------------------------------------------------------

describe("replaceAllOf", () => {
  it("replaces year in full match", () => {
    const p = compile("%Digit * 4 as year");
    expect(p.replaceAllOf("2026", { year: "2027" })).toBe("2027");
  });

  it("returns input unchanged when no full match", () => {
    const p = compile("%Digit * 4 as year");
    expect(p.replaceAllOf("2026 extra", { year: "2027" })).toBe("2026 extra");
  });

  it("multiple captures in full match", () => {
    const p = compile("%Alpha * 1..? as first '-' %Alpha * 1..? as last");
    expect(p.replaceAllOf("foo-bar", { first: "baz", last: "qux" })).toBe("baz-qux");
  });
});

describe("replaceStartOf", () => {
  it("replaces at start", () => {
    const p = compile("%Digit * 4 as year");
    expect(p.replaceStartOf("2026 is the year", { year: "2027" })).toBe("2027 is the year");
  });

  it("returns input unchanged when not at start", () => {
    const p = compile("%Digit * 4 as year");
    expect(p.replaceStartOf("the year is 2026", { year: "2027" })).toBe("the year is 2026");
  });
});

describe("replaceEndOf", () => {
  it("replaces at end", () => {
    const p = compile("%Digit * 4 as year");
    expect(p.replaceEndOf("the year is 2026", { year: "2027" })).toBe("the year is 2027");
  });

  it("returns input unchanged when not at end", () => {
    const p = compile("%Digit * 4 as year");
    expect(p.replaceEndOf("2026 is the year", { year: "2027" })).toBe("2026 is the year");
  });
});

describe("replaceFirstIn", () => {
  it("replaces first occurrence", () => {
    const p = compile("!replacements-ignore-matching = true\n%Digit * 4 as year");
    expect(p.replaceFirstIn("event in 2026, repeated in 2025", { year: "YYYY" })).toBe("event in YYYY, repeated in 2025");
  });

  it("returns input unchanged when no match", () => {
    const p = compile("!replacements-ignore-matching = true\n%Digit * 4 as year");
    expect(p.replaceFirstIn("no digits here", { year: "YYYY" })).toBe("no digits here");
  });
});

describe("replaceNextIn", () => {
  it("replaces occurrence at offset", () => {
    const p = compile("!replacements-ignore-matching = true\n%Digit * 4 as year");
    expect(p.replaceNextIn("2026 and 2025", 7, { year: "YYYY" })).toBe("2026 and YYYY");
  });

  it("returns input unchanged when no match at offset", () => {
    const p = compile("!replacements-ignore-matching = true\n%Digit * 4 as year");
    expect(p.replaceNextIn("2026", 1, { year: "YYYY" })).toBe("2026");
  });

  it("at offset 0 finds first occurrence", () => {
    const p = compile("!replacements-ignore-matching = true\n%Digit * 4 as year");
    expect(p.replaceNextIn("2026 and 2025", 0, { year: "YYYY" })).toBe("YYYY and 2025");
  });
});

describe("replaceAllIn", () => {
  it("replaces all occurrences", () => {
    const p = compile("!replacements-ignore-matching = true\n%Digit * 4 as year");
    expect(p.replaceAllIn("2026 and 2025", { year: "YYYY" })).toBe("YYYY and YYYY");
  });

  it("returns input unchanged when no match", () => {
    const p = compile("!replacements-ignore-matching = true\n%Digit * 4 as year");
    expect(p.replaceAllIn("no digits here", { year: "YYYY" })).toBe("no digits here");
  });
});

describe("replace multiple captures", () => {
  it("replaces two captures in one match", () => {
    const p = compile("%Digit * 4 as year '-' %Digit * 2 as month");
    expect(p.replaceFirstIn("date: 2026-07", { year: "2027", month: "12" })).toBe("date: 2027-12");
  });

  it("replaces two captures across all matches", () => {
    const p = compile("!replacements-ignore-matching = true\n%Digit * 4 as year '-' %Digit * 2 as month");
    expect(p.replaceAllIn("2026-07 and 2025-03", { year: "YYYY", month: "MM" })).toBe("YYYY-MM and YYYY-MM");
  });
});

// ---------------------------------------------------------------------------
// !replacements-ignore-matching
// ---------------------------------------------------------------------------

describe("!replacements-ignore-matching", () => {
  it("validates by default — valid value accepted", () => {
    const p = compile("%Digit * 4 as year");
    expect(p.replaceFirstIn("event 2026", { year: "2027" })).toBe("event 2027");
  });

  it("validates by default — invalid value throws", () => {
    const p = compile("%Digit * 4 as year");
    expect(() => p.replaceFirstIn("event 2026", { year: "202" })).toThrow(PternReplacementError);
    try {
      p.replaceFirstIn("event 2026", { year: "202" });
    } catch (e) {
      expect((e as PternReplacementError).replacementError.kind).toBe("invalidReplacementValue");
    }
  });

  it("ignore-matching annotation skips validation", () => {
    const p = compile("!replacements-ignore-matching = true\n%Digit * 4 as year");
    expect(p.replaceFirstIn("event 2026", { year: "abc" })).toBe("event abc");
  });

  it("validates interpolated capture", () => {
    const p = compile("yyyy = %Digit * 4;\n{yyyy} as year");
    expect(p.replaceFirstIn("2026", { year: "2027" })).toBe("2027");
    expect(() => p.replaceFirstIn("2026", { year: "abc" })).toThrow(PternReplacementError);
  });

  it("case-insensitive flag propagated to validation", () => {
    const p = compile("!case-insensitive = true\n'a'..'z' * 4 as word");
    expect(p.replaceFirstIn("stop", { word: "HALT" })).toBe("HALT");
  });
});

// ---------------------------------------------------------------------------
// Array replacement (captures inside repetitions)
// ---------------------------------------------------------------------------

describe("array replacement", () => {
  it("replaces each iteration of fixed repetition", () => {
    const p = compile("!replacements-ignore-matching = true\n(%Digit * 4 as yr) * 3");
    expect(p.replaceFirstIn("202420252026", { yr: ["A", "B", "C"] })).toBe("ABC");
  });

  it("replaces each iteration of bounded repetition", () => {
    const p = compile("!replacements-ignore-matching = true\n(%Digit * 4 as yr ' ') * 1..3");
    expect(p.replaceFirstIn("2024 2025 ", { yr: ["X", "Y"] })).toBe("X Y ");
  });

  it("scalar broadcasts to all iterations", () => {
    const p = compile("!replacements-ignore-matching = true\n(%Digit * 4 as yr ' ') * 1..3");
    expect(p.replaceFirstIn("2024 2025 2026 ", { yr: "YYYY" })).toBe("YYYY YYYY YYYY ");
  });

  it("throws WrongReplacementType for array on non-repeated capture", () => {
    const p = compile("%Digit * 4 as year");
    expect(() => p.replaceFirstIn("2026", { year: ["2027"] })).toThrow(PternReplacementError);
    try {
      p.replaceFirstIn("2026", { year: ["2027"] });
    } catch (e) {
      expect((e as PternReplacementError).replacementError.kind).toBe("wrongReplacementType");
    }
  });

  it("throws ArrayLengthMismatch for wrong array length", () => {
    const p = compile("!replacements-ignore-matching = true\n(%Digit * 4 as yr) * 3");
    expect(() => p.replaceFirstIn("202420252026", { yr: ["A", "B"] })).toThrow(PternReplacementError);
    try {
      p.replaceFirstIn("202420252026", { yr: ["A", "B"] });
    } catch (e) {
      const err = (e as PternReplacementError).replacementError;
      expect(err.kind).toBe("arrayLengthMismatch");
      if (err.kind === "arrayLengthMismatch") {
        expect(err.captureName).toBe("yr");
        expect(err.provided).toBe(2);
        expect(err.actual).toBe(3);
      }
    }
  });

  it("throws DuplicateRepetitionCapture for same name in two repetitions", () => {
    const p = compile("!replacements-ignore-matching = true\n(%Digit as n) * 2 (%Alpha as n) * 3");
    expect(() => p.replaceFirstIn("12abc", { n: ["x", "y"] })).toThrow(PternReplacementError);
    try {
      p.replaceFirstIn("12abc", { n: ["x", "y"] });
    } catch (e) {
      expect((e as PternReplacementError).replacementError.kind).toBe("duplicateRepetitionCapture");
    }
  });
});

// ---------------------------------------------------------------------------
// Empty string replacement values
// ---------------------------------------------------------------------------

describe("empty string replacements", () => {
  it("scalar empty deletes capture span", () => {
    const p = compile("!replacements-ignore-matching = true\n%Digit * 4 as year");
    expect(p.replaceFirstIn("event 2026", { year: "" })).toBe("event ");
  });

  it("scalar empty in replaceAllIn deletes all", () => {
    const p = compile("!replacements-ignore-matching = true\n%Digit * 4 as year");
    expect(p.replaceAllIn("2026 and 2025", { year: "" })).toBe(" and ");
  });

  it("array element empty deletes that iteration", () => {
    const p = compile("!replacements-ignore-matching = true\n(%Alpha as c) * 3");
    expect(p.replaceFirstIn("abc", { c: ["", "x", ""] })).toBe("x");
  });

  it("scalar empty validates (invalid for matching pattern)", () => {
    const p = compile("%Digit * 4 as year");
    expect(() => p.replaceFirstIn("event 2026", { year: "" })).toThrow(PternReplacementError);
  });
});

// ---------------------------------------------------------------------------
// Round-trip: replace with same values as captured
// ---------------------------------------------------------------------------

describe("round-trip replacement", () => {
  it("replaceAllOf round-trip", () => {
    const p = compile("%Digit * 4 as year '-' %Digit * 2 as month '-' %Digit * 2 as day");
    const input = "2026-04-27";
    const m = p.matchAllOf(input);
    expect(m).not.toBeNull();
    const replacements = Object.fromEntries(Object.entries(m!.captures).map(([k, v]) => [k, v]));
    expect(p.replaceAllOf(input, replacements)).toBe(input);
  });

  it("replaceStartOf round-trip", () => {
    const p = compile("%Digit * 4 as year");
    const input = "2026 is a great year";
    const m = p.matchStartOf(input);
    expect(m).not.toBeNull();
    expect(p.replaceStartOf(input, m!.captures)).toBe(input);
  });

  it("replaceEndOf round-trip", () => {
    const p = compile("%Digit * 4 as year");
    const input = "the year is 2026";
    const m = p.matchEndOf(input);
    expect(m).not.toBeNull();
    expect(p.replaceEndOf(input, m!.captures)).toBe(input);
  });

  it("replaceFirstIn round-trip", () => {
    const p = compile("%Digit * 4 as year");
    const input = "event in 2026, repeated in 2025";
    const m = p.matchFirstIn(input);
    expect(m).not.toBeNull();
    expect(p.replaceFirstIn(input, m!.captures)).toBe(input);
  });

  it("replaceNextIn round-trip", () => {
    const p = compile("%Digit * 4 as year");
    const input = "2026 and 2025";
    const m = p.matchNextIn(input, 7);
    expect(m).not.toBeNull();
    expect(p.replaceNextIn(input, 7, m!.captures)).toBe(input);
  });

  it("replaceAllIn round-trip with uniform captures", () => {
    const p = compile("'v' %Digit as ver");
    expect(p.replaceAllIn("v1 v1 v1", { ver: "1" })).toBe("v1 v1 v1");
  });

  it("repetition capture round-trip broadcasts last value", () => {
    const p = compile("!replacements-ignore-matching = true\n(%Digit * 4 as yr) * 3");
    const input = "202420252026";
    const m = p.matchFirstIn(input);
    expect(m).not.toBeNull();
    expect(m!.captures["yr"]).toBe("2026");
    expect(p.replaceFirstIn(input, m!.captures)).toBe("202620262026");
  });
});

// ---------------------------------------------------------------------------
// Duplicate capture name — only first occurrence patched
// ---------------------------------------------------------------------------

describe("duplicate capture name behavior", () => {
  it("only patches first occurrence", () => {
    const p = compile("!replacements-ignore-matching = true\n'foo' as x '-' 'bar' as x");
    expect(p.replaceFirstIn("foo-bar", { x: "Z" })).toBe("Z-bar");
  });
});

// ---------------------------------------------------------------------------
// Array element fails validation
// ---------------------------------------------------------------------------

describe("array element validation", () => {
  it("throws InvalidReplacementValue for bad array element", () => {
    const p = compile("(%Digit * 2 as n) * 3");
    expect(() => p.replaceFirstIn("121314", { n: ["12", "ab", "34"] })).toThrow(PternReplacementError);
    try {
      p.replaceFirstIn("121314", { n: ["12", "ab", "34"] });
    } catch (e) {
      expect((e as PternReplacementError).replacementError.kind).toBe("invalidReplacementValue");
    }
  });
});

// ---------------------------------------------------------------------------
// Scalar broadcast with validation
// ---------------------------------------------------------------------------

describe("scalar broadcast with validation", () => {
  it("valid scalar broadcasts to all iterations", () => {
    const p = compile("(%Digit * 2 as n) * 3");
    expect(p.replaceAllOf("121314", { n: "99" })).toBe("999999");
  });

  it("invalid scalar throws", () => {
    const p = compile("(%Digit * 2 as n) * 3");
    expect(() => p.replaceAllOf("121314", { n: "ab" })).toThrow(PternReplacementError);
  });
});

// ---------------------------------------------------------------------------
// Mixed repeated and non-repeated captures
// ---------------------------------------------------------------------------

describe("mixed repeated and scalar captures", () => {
  it("scalar tag and array n in same replacement", () => {
    const p = compile("!replacements-ignore-matching = true\n%Alpha * 1..? as tag ('-' %Digit * 2 as n) * 1..3");
    expect(p.replaceFirstIn("abc-12-34", { tag: "Z", n: ["01", "02"] })).toBe("Z-01-02");
  });
});

// ---------------------------------------------------------------------------
// Bounded repetition array length at boundaries
// ---------------------------------------------------------------------------

describe("bounded repetition array boundaries", () => {
  it("array at min boundary", () => {
    const p = compile("!replacements-ignore-matching = true\n(%Digit * 2 as n) * 2..4");
    expect(p.replaceFirstIn("1234", { n: ["X", "Y"] })).toBe("XY");
  });

  it("array at max boundary", () => {
    const p = compile("!replacements-ignore-matching = true\n(%Digit * 2 as n) * 2..4");
    expect(p.replaceFirstIn("12345678", { n: ["A", "B", "C", "D"] })).toBe("ABCD");
  });

  it("array length mismatch throws", () => {
    const p = compile("!replacements-ignore-matching = true\n(%Digit * 2 as n) * 2..4");
    expect(() => p.replaceFirstIn("1234", { n: ["X"] })).toThrow(PternReplacementError);
    try {
      p.replaceFirstIn("1234", { n: ["X"] });
    } catch (e) {
      const err = (e as PternReplacementError).replacementError;
      expect(err.kind).toBe("arrayLengthMismatch");
      if (err.kind === "arrayLengthMismatch") {
        expect(err.captureName).toBe("n");
        expect(err.provided).toBe(1);
        expect(err.actual).toBe(2);
      }
    }
  });
});

// ---------------------------------------------------------------------------
// Empty replacements dict
// ---------------------------------------------------------------------------

describe("empty replacements dict", () => {
  it("leaves match unchanged", () => {
    const p = compile("%Digit * 4 as year");
    expect(p.replaceFirstIn("event 2026", {})).toBe("event 2026");
  });
});

// ---------------------------------------------------------------------------
// Case-insensitive uppercase match
// ---------------------------------------------------------------------------

describe("case-insensitive replacement", () => {
  it("replaces uppercase match text", () => {
    const p = compile("!case-insensitive = true\n!replacements-ignore-matching = true\n'hello' as word");
    expect(p.replaceFirstIn("HELLO world", { word: "greetings" })).toBe("greetings world");
  });
});

// ---------------------------------------------------------------------------
// Backreference — only original capture span patched
// ---------------------------------------------------------------------------

describe("backreference span patching", () => {
  it("only patches capture span, not backreference position", () => {
    const p = compile("!replacements-ignore-matching = true\n%Alpha * 3 as tag ',' {tag}");
    expect(p.replaceFirstIn("abc,abc", { tag: "xyz" })).toBe("xyz,abc");
  });
});
