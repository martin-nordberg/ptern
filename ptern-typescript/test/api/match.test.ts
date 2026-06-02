import { describe, expect, it } from "bun:test";
import { compile, PternCompileError } from "../../src/index";
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
// Compile — success cases
// ---------------------------------------------------------------------------

describe("compile success", () => {
  it("simple literal", () => {
    expect(() => compile("'hello'")).not.toThrow();
  });

  it("charclass", () => {
    expect(() => compile("%Digit")).not.toThrow();
  });

  it("range", () => {
    expect(() => compile("'a'..'z'")).not.toThrow();
  });

  it("alternation", () => {
    expect(() => compile("'foo' | 'bar'")).not.toThrow();
  });

  it("named capture", () => {
    expect(() => compile("%Digit * 4 as year")).not.toThrow();
  });

  it("definition and interpolation", () => {
    expect(() => compile("d = %Digit * 4; {d}")).not.toThrow();
  });

  it("valid escape sequences", () => {
    expect(() => compile("'\\n\\t\\r\\\\'")).not.toThrow();
  });

  it("excluding", () => {
    expect(() => compile("'a'..'z' excluding 'q'")).not.toThrow();
  });
});

// ---------------------------------------------------------------------------
// matchesAllOf / matchesStartOf / matchesEndOf / matchesIn
// ---------------------------------------------------------------------------

describe("matchesAllOf", () => {
  it("full match succeeds", () => {
    const p = compile("'hello'");
    expect(p.matchesAllOf("hello")).toBe(true);
  });

  it("partial match fails", () => {
    const p = compile("'hello'");
    expect(p.matchesAllOf("hello world")).toBe(false);
  });

  it("empty input fails", () => {
    const p = compile("'hello'");
    expect(p.matchesAllOf("")).toBe(false);
  });

  it("case-sensitive by default", () => {
    const p = compile("'hello'");
    expect(p.matchesAllOf("HELLO")).toBe(false);
  });

  it("case-insensitive when annotated", () => {
    const p = compile("!case-insensitive = true\n'hello'");
    expect(p.matchesAllOf("HELLO")).toBe(true);
  });

  it("digit class matches digit", () => {
    const p = compile("%Digit");
    expect(p.matchesAllOf("5")).toBe(true);
    expect(p.matchesAllOf("a")).toBe(false);
  });

  it("digit pattern accepts 4-digit string", () => {
    const p = compile("%Digit * 4");
    expect(p.matchesAllOf("2026")).toBe(true);
    expect(p.matchesAllOf("abcd")).toBe(false);
  });

  it("alternation matches either branch", () => {
    const p = compile("'cat' | 'dog'");
    expect(p.matchesAllOf("cat")).toBe(true);
    expect(p.matchesAllOf("dog")).toBe(true);
    expect(p.matchesAllOf("fish")).toBe(false);
  });
});

describe("matchesStartOf", () => {
  it("matches at start", () => {
    const p = compile("'hello'");
    expect(p.matchesStartOf("hello world")).toBe(true);
  });

  it("does not match at non-start", () => {
    const p = compile("'hello'");
    expect(p.matchesStartOf("say hello")).toBe(false);
  });
});

describe("matchesEndOf", () => {
  it("matches at end", () => {
    const p = compile("'hello'");
    expect(p.matchesEndOf("say hello")).toBe(true);
  });

  it("does not match at non-end", () => {
    const p = compile("'hello'");
    expect(p.matchesEndOf("hello world")).toBe(false);
  });
});

describe("matchesIn", () => {
  it("finds match anywhere", () => {
    const p = compile("'hello'");
    expect(p.matchesIn("say hello world")).toBe(true);
  });

  it("returns false when not found", () => {
    const p = compile("'hello'");
    expect(p.matchesIn("goodbye world")).toBe(false);
  });
});

// ---------------------------------------------------------------------------
// matchFirstIn / matchAllOf / matchStartOf / matchEndOf
// matchNextIn / matchAllIn
// ---------------------------------------------------------------------------

describe("matchFirstIn", () => {
  it("returns null when no match", () => {
    const p = compile("'hello'");
    expect(p.matchFirstIn("goodbye")).toBeNull();
  });

  it("returns non-null when found", () => {
    const p = compile("'hello'");
    expect(p.matchFirstIn("say hello world")).not.toBeNull();
  });

  it("returns correct index and length", () => {
    const p = compile("'hello'");
    const m = p.matchFirstIn("say hello world");
    expect(m).not.toBeNull();
    expect(m!.index).toBe(4);
    expect(m!.length).toBe(5);
  });

  it("returns named captures", () => {
    const p = compile("%Digit * 4 as year");
    const m = p.matchFirstIn("2026");
    expect(m).not.toBeNull();
    expect(m!.captures["year"]).toBe("2026");
  });

  it("returns multiple captures for ISO date", () => {
    const p = compile(
      "yyyy = %Digit * 4;\n" +
      "mm = ('0' '1'..'9') | ('1' '0'..'2');\n" +
      "dd = ('0' '1'..'9') | ('1'..'2' %Digit) | ('3' '0'..'1');\n" +
      "{yyyy} as year '-' {mm} as month '-' {dd} as day",
    );
    const m = p.matchFirstIn("2026-07-04");
    expect(m).not.toBeNull();
    expect(m!.captures["year"]).toBe("2026");
    expect(m!.captures["month"]).toBe("07");
    expect(m!.captures["day"]).toBe("04");
  });
});

describe("matchAllOf", () => {
  it("returns null for partial match", () => {
    const p = compile("'hello'");
    expect(p.matchAllOf("hello world")).toBeNull();
  });

  it("returns occurrence for full match", () => {
    const p = compile("'hello'");
    const m = p.matchAllOf("hello");
    expect(m).not.toBeNull();
    expect(m!.index).toBe(0);
    expect(m!.length).toBe(5);
  });
});

describe("matchStartOf", () => {
  it("returns null when not at start", () => {
    const p = compile("'hello'");
    expect(p.matchStartOf("say hello")).toBeNull();
  });

  it("returns occurrence at start", () => {
    const p = compile("'hello'");
    const m = p.matchStartOf("hello world");
    expect(m).not.toBeNull();
    expect(m!.index).toBe(0);
    expect(m!.length).toBe(5);
  });
});

describe("matchEndOf", () => {
  it("returns null when not at end", () => {
    const p = compile("'hello'");
    expect(p.matchEndOf("hello world")).toBeNull();
  });

  it("returns occurrence at end", () => {
    const p = compile("'hello'");
    const m = p.matchEndOf("say hello");
    expect(m).not.toBeNull();
    expect(m!.index).toBe(4);
    expect(m!.length).toBe(5);
  });
});

describe("matchNextIn", () => {
  it("resumes after given index", () => {
    const p = compile("'hello'");
    const first = p.matchNextIn("hello hello", 0);
    expect(first).not.toBeNull();
    expect(first!.index).toBe(0);
    const second = p.matchNextIn("hello hello", first!.index + first!.length);
    expect(second).not.toBeNull();
    expect(second!.index).toBe(6);
  });

  it("returns null past end", () => {
    const p = compile("'hello'");
    expect(p.matchNextIn("hello", 1)).toBeNull();
  });
});

describe("matchAllIn", () => {
  it("returns all occurrences", () => {
    const p = compile("'hello'");
    const occs = p.matchAllIn("hello say hello");
    expect(occs).toHaveLength(2);
    expect(occs[0]!.index).toBe(0);
    expect(occs[1]!.index).toBe(10);
  });

  it("returns empty array for no match", () => {
    const p = compile("'hello'");
    expect(p.matchAllIn("goodbye")).toHaveLength(0);
  });
});

// ---------------------------------------------------------------------------
// Length bounds
// ---------------------------------------------------------------------------

describe("minLength / maxLength", () => {
  it("literal length", () => {
    const p = compile("'hello'");
    expect(p.minLength()).toBe(5);
    expect(p.maxLength()).toBe(5);
  });

  it("digit class length", () => {
    const p = compile("%Digit");
    expect(p.minLength()).toBe(1);
    expect(p.maxLength()).toBe(1);
  });

  it("exact repetition length", () => {
    const p = compile("%Digit * 4");
    expect(p.minLength()).toBe(4);
    expect(p.maxLength()).toBe(4);
  });

  it("bounded repetition lengths", () => {
    const p = compile("%Digit * 2..5");
    expect(p.minLength()).toBe(2);
    expect(p.maxLength()).toBe(5);
  });

  it("unbounded repetition: min=1, max=null", () => {
    const p = compile("%Digit * 1..?");
    expect(p.minLength()).toBe(1);
    expect(p.maxLength()).toBeNull();
  });

  it("optional (0..1): min=0, max=1", () => {
    const p = compile("%Digit * 0..1");
    expect(p.minLength()).toBe(0);
    expect(p.maxLength()).toBe(1);
  });

  it("sequence length", () => {
    const p = compile("'ab' %Digit");
    expect(p.minLength()).toBe(3);
    expect(p.maxLength()).toBe(3);
  });

  it("alternation min/max", () => {
    const p = compile("'a' | 'bcd'");
    expect(p.minLength()).toBe(1);
    expect(p.maxLength()).toBe(3);
  });

  it("alternation with unbounded: max=null", () => {
    const p = compile("'a' | %Digit * 1..?");
    expect(p.maxLength()).toBeNull();
  });

  it("definition interpolation", () => {
    const p = compile("d = %Digit * 4; {d}");
    expect(p.minLength()).toBe(4);
    expect(p.maxLength()).toBe(4);
  });

  it("position assertion contributes zero length", () => {
    const p = compile("@word-start %Digit * 4 @word-end");
    expect(p.minLength()).toBe(4);
    expect(p.maxLength()).toBe(4);
  });
});

// ---------------------------------------------------------------------------
// Lex errors
// ---------------------------------------------------------------------------

describe("lex errors", () => {
  it("unterminated single-quoted string", () => {
    expect(() => compile("'hello")).toThrow(PternCompileError);
    try {
      compile("'hello");
    } catch (e) {
      expect((e as PternCompileError).compileError.kind).toBe("lexError");
    }
  });

  it("unterminated double-quoted string", () => {
    expect(() => compile('"world')).toThrow(PternCompileError);
    try {
      compile('"world');
    } catch (e) {
      expect((e as PternCompileError).compileError.kind).toBe("lexError");
    }
  });

  it("unexpected character ~", () => {
    expect(() => compile("~")).toThrow(PternCompileError);
    try {
      compile("~");
    } catch (e) {
      expect((e as PternCompileError).compileError.kind).toBe("lexError");
    }
  });

  it("unexpected character $", () => {
    expect(() => compile("$")).toThrow(PternCompileError);
    try {
      compile("$");
    } catch (e) {
      expect((e as PternCompileError).compileError.kind).toBe("lexError");
    }
  });
});

// ---------------------------------------------------------------------------
// Parse errors
// ---------------------------------------------------------------------------

describe("parse errors", () => {
  it("empty input", () => {
    expect(() => compile("")).toThrow(PternCompileError);
    try {
      compile("");
    } catch (e) {
      expect((e as PternCompileError).compileError.kind).toBe("parseError");
    }
  });

  it("unclosed group", () => {
    expect(() => compile("('a'")).toThrow(PternCompileError);
    try {
      compile("('a'");
    } catch (e) {
      expect((e as PternCompileError).compileError.kind).toBe("parseError");
    }
  });

  it("missing semicolon", () => {
    expect(() => compile("d = %Digit")).toThrow(PternCompileError);
    try {
      compile("d = %Digit");
    } catch (e) {
      expect((e as PternCompileError).compileError.kind).toBe("parseError");
    }
  });

  it("stray token", () => {
    expect(() => compile("'a' )")).toThrow(PternCompileError);
    try {
      compile("'a' )");
    } catch (e) {
      expect((e as PternCompileError).compileError.kind).toBe("parseError");
    }
  });

  it("missing rep count after *", () => {
    expect(() => compile("%Digit *")).toThrow(PternCompileError);
    try {
      compile("%Digit *");
    } catch (e) {
      expect((e as PternCompileError).compileError.kind).toBe("parseError");
    }
  });

  it("missing upper bound after ..", () => {
    expect(() => compile("%Digit * 1..")).toThrow(PternCompileError);
    try {
      compile("%Digit * 1..");
    } catch (e) {
      expect((e as PternCompileError).compileError.kind).toBe("parseError");
    }
  });

  it("unclosed interpolation", () => {
    expect(() => compile("{name")).toThrow(PternCompileError);
    try {
      compile("{name");
    } catch (e) {
      expect((e as PternCompileError).compileError.kind).toBe("parseError");
    }
  });
});

// ---------------------------------------------------------------------------
// Semantic — annotation errors
// ---------------------------------------------------------------------------

describe("semantic annotation errors", () => {
  it("unknown annotation typo", () => {
    expect(hasSemanticError("!typo = true\n'x'", { kind: "unknownAnnotation", name: "typo" })).toBe(true);
  });

  it("unknown annotation wrong case", () => {
    expect(hasSemanticError("!Case-Insensitive = true\n'x'", { kind: "unknownAnnotation", name: "Case-Insensitive" })).toBe(true);
  });

  it("duplicate annotation", () => {
    expect(hasSemanticError(
      "!case-insensitive = true\n!case-insensitive = false\n'x'",
      { kind: "duplicateAnnotation", name: "case-insensitive" },
    )).toBe(true);
  });
});

// ---------------------------------------------------------------------------
// Semantic — escape sequence errors
// ---------------------------------------------------------------------------

describe("semantic escape errors", () => {
  it("invalid escape \\z", () => {
    expect(hasSemanticError("'\\z'", { kind: "invalidEscapeSequence", seq: "\\z" })).toBe(true);
  });

  it("invalid escape \\x (not \\uXXXX)", () => {
    expect(hasSemanticError("'\\x41'", { kind: "invalidEscapeSequence", seq: "\\x" })).toBe(true);
  });
});

// ---------------------------------------------------------------------------
// Semantic — repetition errors
// ---------------------------------------------------------------------------

describe("semantic repetition errors", () => {
  it("inverted bounds 5..2", () => {
    expect(hasSemanticError("%Digit * 5..2", { kind: "invertedRepetitionBounds", min: 5, max: 2 })).toBe(true);
  });

  it("inverted bounds 100..1", () => {
    expect(hasSemanticError("'a' * 100..1", { kind: "invertedRepetitionBounds", min: 100, max: 1 })).toBe(true);
  });

  it("capture inside repetition compiles and matches", () => {
    const p = compile("('a' as x) * 3");
    expect(p.matchesAllOf("aaa")).toBe(true);
  });

  it("capture in bounded repetition", () => {
    const p = compile("('a' as val) * 1..5");
    expect(p.matchesAllOf("aaa")).toBe(true);
  });

  it("capture in optional repetition", () => {
    const p = compile("('a' as opt) * 0..1");
    expect(p.matchesAllOf("a")).toBe(true);
  });

  it("capture in unbounded repetition", () => {
    const p = compile("(%Digit as d) * 1..?");
    expect(p.matchesAllOf("123")).toBe(true);
  });
});

// ---------------------------------------------------------------------------
// Semantic — range and exclusion errors
// ---------------------------------------------------------------------------

describe("semantic range errors", () => {
  it("multi-char left endpoint", () => {
    expect(hasSemanticError("'ab'..'z'", { kind: "invalidRangeEndpoint", content: "ab" })).toBe(true);
  });

  it("multi-char right endpoint", () => {
    expect(hasSemanticError("'a'..'yz'", { kind: "invalidRangeEndpoint", content: "yz" })).toBe(true);
  });

  it("inverted range z..a", () => {
    expect(hasSemanticError("'z'..'a'", { kind: "invertedRange", from: "z", to: "a" })).toBe(true);
  });

  it("inverted range 9..0", () => {
    expect(hasSemanticError("'9'..'0'", { kind: "invertedRange", from: "9", to: "0" })).toBe(true);
  });

  it("invalid exclusion operand group sequence", () => {
    expect(hasSemanticError("'a'..'z' excluding ('x' 'y')", { kind: "invalidExclusionOperand" })).toBe(true);
  });
});

// ---------------------------------------------------------------------------
// Semantic — reference and definition errors
// ---------------------------------------------------------------------------

describe("semantic reference errors", () => {
  it("undefined reference", () => {
    expect(hasSemanticError("{missing}", { kind: "undefinedReference", name: "missing" })).toBe(true);
  });

  it("undefined reference in definition", () => {
    expect(hasSemanticError("a = {undefined}; {a}", { kind: "undefinedReference", name: "undefined" })).toBe(true);
  });

  it("duplicate definition", () => {
    expect(hasSemanticError("a = 'x'; a = 'y'; {a}", { kind: "duplicateDefinition", name: "a" })).toBe(true);
  });

  it("duplicate definition triple", () => {
    expect(hasSemanticError("d = '1'; d = '2'; d = '3'; {d}", { kind: "duplicateDefinition", name: "d" })).toBe(true);
  });

  it("circular definition self", () => {
    expect(hasSemanticError("a = {a}; {a}", { kind: "circularDefinition", names: ["a"] })).toBe(true);
  });

  it("circular definition two-node", () => {
    expect(hasSemanticError("a = {b}; b = {a}; {a}", { kind: "circularDefinition", names: ["a", "b"] })).toBe(true);
  });

  it("duplicate capture name: compiles and matches", () => {
    const p = compile("'a' as x '-' 'b' as x");
    expect(p.matchesAllOf("a-b")).toBe(true);
  });

  it("duplicate capture three uses: compiles and matches", () => {
    const p = compile("'a' as v '-' 'b' as v '-' 'c' as v");
    expect(p.matchesAllOf("a-b-c")).toBe(true);
  });

  it("capture-definition conflict", () => {
    expect(hasSemanticError("d = 'x'; 'a' as d", { kind: "captureDefinitionConflict", name: "d" })).toBe(true);
  });

  it("capture-definition conflict named", () => {
    expect(hasSemanticError("year = %Digit * 4; %Digit * 4 as year", { kind: "captureDefinitionConflict", name: "year" })).toBe(true);
  });
});

// ---------------------------------------------------------------------------
// Position assertions
// ---------------------------------------------------------------------------

describe("position assertions", () => {
  it("word boundary matches whole word", () => {
    const p = compile("@word-start %Alpha * 1..? @word-end");
    expect(p.matchesAllOf("hello")).toBe(true);
    expect(p.matchesIn("say hello there")).toBe(true);
    expect(p.matchesIn("123")).toBe(false);
  });

  it("@word-start does not match mid-word", () => {
    const p = compile("@word-start 'un'");
    expect(p.matchesIn("undo")).toBe(true);
    expect(p.matchesIn("fun")).toBe(false);
  });

  it("@word-end does not match mid-word", () => {
    const p = compile("'ing' @word-end");
    expect(p.matchesIn("running")).toBe(true);
    expect(p.matchesIn("rings")).toBe(false);
  });

  it("@line-start matches at line beginning", () => {
    const p = compile("@line-start %Digit * 1..?");
    expect(p.matchesIn("42 items")).toBe(true);
    expect(p.matchAllIn("1 first\n2 second\n3 third")).toHaveLength(3);
  });

  it("@line-end matches at line end", () => {
    const p = compile("%Alpha * 1..? @line-end");
    expect(p.matchAllIn("hello\nworld\n123")).toHaveLength(2);
  });

  it("@line-start and @line-end matches full line", () => {
    const p = compile("@line-start %Alpha * 1..? @line-end");
    expect(p.matchAllIn("hello\nworld\n123")).toHaveLength(2);
  });

  it("unknown position assertion error", () => {
    expect(hasSemanticError("@bogus 'x'", { kind: "unknownPositionAssertion", name: "bogus" })).toBe(true);
  });

  it("position assertion in repetition error", () => {
    expect(hasSemanticError("@word-start * 3", { kind: "positionAssertionInRepetition", name: "word-start" })).toBe(true);
  });
});

// ---------------------------------------------------------------------------
// Fewest (lazy matching)
// ---------------------------------------------------------------------------

describe("fewest (lazy matching)", () => {
  it("greedy matches full span, lazy stops at first close", () => {
    const greedy = compile("'<' %Any * 0..? '>'");
    const lazy = compile("'<' %Any * 0..? fewest '>'");
    const gm = greedy.matchFirstIn("<b><i>");
    const lm = lazy.matchFirstIn("<b><i>");
    expect(gm).not.toBeNull();
    expect(lm).not.toBeNull();
    expect(gm!.length).toBe(6);
    expect(lm!.length).toBe(3);
  });

  it("lazy matchAllIn finds each tag", () => {
    const p = compile("'<' %Any * 1..? fewest '>'");
    expect(p.matchAllIn("<b><i><em>")).toHaveLength(3);
  });
});

// ---------------------------------------------------------------------------
// Extended capture scenarios
// ---------------------------------------------------------------------------

describe("extended capture scenarios", () => {
  it("repetition capture returns last iteration value", () => {
    const p = compile("(%Digit * 4 as yr) * 3");
    const m = p.matchFirstIn("202420252026");
    expect(m).not.toBeNull();
    expect(m!.captures["yr"]).toBe("2026");
  });

  it("optional capture absent when not matched", () => {
    const p = compile("('a' as opt) * 0..1");
    const m = p.matchFirstIn("b");
    expect(m).not.toBeNull();
    expect(m!.captures["opt"]).toBeUndefined();
  });

  it("duplicate capture: value is from first occurrence", () => {
    const p = compile("'a' as x '-' 'b' as x");
    const m = p.matchFirstIn("a-b");
    expect(m).not.toBeNull();
    expect(m!.captures["x"]).toBe("a");
  });

  it("alternative branch capture absent when branch not taken", () => {
    const p = compile("'a' as x | 'b' as y");
    const m1 = p.matchFirstIn("a");
    expect(m1).not.toBeNull();
    expect(m1!.captures["x"]).toBe("a");
    expect(m1!.captures["y"]).toBeUndefined();
    const m2 = p.matchFirstIn("b");
    expect(m2).not.toBeNull();
    expect(m2!.captures["x"]).toBeUndefined();
    expect(m2!.captures["y"]).toBe("b");
  });

  it("matchAllIn: each occurrence has independent captures", () => {
    const p = compile("%Digit * 1..? as n");
    const matches = p.matchAllIn("42 and 7");
    expect(matches).toHaveLength(2);
    expect(matches[0]!.captures["n"]).toBe("42");
    expect(matches[1]!.captures["n"]).toBe("7");
  });

  it("matchNextIn: returned occurrence has correct captures", () => {
    const p = compile("%Digit * 1..? as n");
    const first = p.matchNextIn("42 and 7", 0);
    expect(first).not.toBeNull();
    expect(first!.captures["n"]).toBe("42");
    const second = p.matchNextIn("42 and 7", first!.index + first!.length);
    expect(second).not.toBeNull();
    expect(second!.captures["n"]).toBe("7");
  });

  it("synthetic __rep_N groups not in captures", () => {
    const p = compile("(%Digit as d) * 3");
    const m = p.matchFirstIn("123");
    expect(m).not.toBeNull();
    const keys = Object.keys(m!.captures);
    expect(keys.every(k => !k.startsWith("__rep_"))).toBe(true);
  });

  it("case-insensitive flag propagates to backreferences", () => {
    const p = compile("!case-insensitive = true\n%Alpha * 1..? as word ' ' {word}");
    expect(p.matchesAllOf("Hello hello")).toBe(true);
    expect(p.matchesAllOf("Hello HELLO")).toBe(true);
    expect(p.matchesAllOf("Hello world")).toBe(false);
  });
});

// ---------------------------------------------------------------------------
// Backreferences
// ---------------------------------------------------------------------------

describe("backreferences", () => {
  it("matches repeated word", () => {
    const p = compile("%Alpha * 1..? as word '-' {word}");
    expect(p.matchesAllOf("abc-abc")).toBe(true);
    expect(p.matchesAllOf("hello-hello")).toBe(true);
    expect(p.matchesAllOf("abc-xyz")).toBe(false);
    expect(p.matchesAllOf("abc-ab")).toBe(false);
  });

  it("captures the matched text", () => {
    const p = compile("%Digit * 1..3 as code ':' {code}");
    const m = p.matchFirstIn("42:42 rest");
    expect(m).not.toBeNull();
    expect(m!.captures["code"]).toBe("42");
  });

  it("case-sensitive by default", () => {
    const p = compile("%Alpha * 1..? as word ' ' {word}");
    expect(p.matchesAllOf("Hello Hello")).toBe(true);
    expect(p.matchesAllOf("Hello hello")).toBe(false);
  });
});

// ---------------------------------------------------------------------------
// Multiline annotation
// ---------------------------------------------------------------------------

describe("!multiline", () => {
  it("matchesAllOf matches any complete line when multiline", () => {
    const plain = compile("%Alpha * 1..?");
    expect(plain.matchesAllOf("hello\nworld\n123")).toBe(false);
    const p = compile("!multiline = true\n%Alpha * 1..?");
    expect(p.matchesAllOf("hello\nworld\n123")).toBe(true);
    expect(p.matchesAllOf("hello world\n123 go")).toBe(false);
  });

  it("matchesStartOf matches any line start when multiline", () => {
    const plain = compile("%Alpha * 1..?");
    expect(plain.matchesStartOf("123\nhello world")).toBe(false);
    const p = compile("!multiline = true\n%Alpha * 1..?");
    expect(p.matchesStartOf("123\nhello world")).toBe(true);
    expect(p.matchesStartOf("hello world")).toBe(true);
  });

  it("matchesEndOf matches any line end when multiline", () => {
    const plain = compile("%Alpha * 1..?");
    expect(plain.matchesEndOf("hello world\n123")).toBe(false);
    const p = compile("!multiline = true\n%Alpha * 1..?");
    expect(p.matchesEndOf("hello world\n123")).toBe(true);
    expect(p.matchesEndOf("say hello")).toBe(true);
  });
});

// ---------------------------------------------------------------------------
// Sub-pattern scenarios
// ---------------------------------------------------------------------------

describe("sub-pattern scenarios", () => {
  it("same definition interpolated twice", () => {
    const p = compile("d = %Digit * 4; {d} '-' {d}");
    expect(p.matchesAllOf("2024-2026")).toBe(true);
    expect(p.matchesAllOf("2024-202")).toBe(false);
  });

  it("definition inside repetition", () => {
    const p = compile("seg = %Digit * 2; {seg} * 3");
    expect(p.matchesAllOf("123456")).toBe(true);
    expect(p.matchesAllOf("12345")).toBe(false);
  });

  it("definition body alternation", () => {
    const p = compile("sep = ',' | ';'; %Digit {sep} %Digit");
    expect(p.matchesAllOf("1,2")).toBe(true);
    expect(p.matchesAllOf("1;2")).toBe(true);
    expect(p.matchesAllOf("1|2")).toBe(false);
  });

  it("three-node circular definition", () => {
    expect(hasSemanticError("a = {b}; b = {c}; c = {a}; {a}", {
      kind: "circularDefinition", names: ["a", "b", "c"],
    })).toBe(true);
  });

  it("unused definition is a semantic error", () => {
    expect(hasSemanticError("spare = 'x'; 'y'", { kind: "unusedDefinition", name: "spare" })).toBe(true);
  });

  it("backreference after definition-interpolation capture", () => {
    const p = compile("num = %Digit * 1..3; {num} as tag ':' {tag}");
    expect(p.matchesAllOf("42:42")).toBe(true);
    expect(p.matchesAllOf("42:43")).toBe(false);
    const m = p.matchFirstIn("99:99 rest");
    expect(m).not.toBeNull();
    expect(m!.captures["tag"]).toBe("99");
  });

  it("three-level definition chain", () => {
    const p = compile("a = 'x'; b = {a} 'y'; c = {b} 'z'; {c}");
    expect(p.matchesAllOf("xyz")).toBe(true);
    expect(p.matchesAllOf("xy")).toBe(false);
  });
});
