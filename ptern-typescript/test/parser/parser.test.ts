import { describe, expect, it } from "bun:test";
import { lex } from "../../src/lexer/lexer";
import { parse } from "../../src/parser/parser";
import type { Atom, Capture, Expression, ParseError, RepCount } from "../../src/parser/ast";

function parseInput(input: string): ReturnType<typeof parse> {
  const tokens = lex(input);
  if (!Array.isArray(tokens)) throw new Error("lex failed: " + JSON.stringify(tokens));
  return parse(tokens);
}

function isError(result: ReturnType<typeof parse>): result is ParseError {
  return "kind" in result;
}

function getBody(input: string): Expression {
  const result = parseInput(input);
  if (isError(result)) throw new Error("unexpected parse error: " + JSON.stringify(result));
  return result.body;
}

function firstItem(input: string): Capture {
  const body = getBody(input);
  const item = body.alternatives[0]?.items[0];
  if (!item) throw new Error("no first item");
  return item;
}

function firstAtom(input: string): Atom {
  return firstItem(input).inner.inner.base.atom;
}

function firstRepCount(input: string): RepCount {
  const count = firstItem(input).inner.count;
  if (!count) throw new Error("no rep count");
  return count;
}

// ---------------------------------------------------------------------------
// Parser errors
// ---------------------------------------------------------------------------

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

// ---------------------------------------------------------------------------
// Atom types
// ---------------------------------------------------------------------------

describe("atom types", () => {
  it("parses single-quoted literal", () => {
    expect(firstAtom("'hello'")).toEqual({ kind: "literal", content: "hello" });
  });

  it("parses double-quoted literal", () => {
    expect(firstAtom('"world"')).toEqual({ kind: "literal", content: "world" });
  });

  it("parses char class", () => {
    expect(firstAtom("%Digit")).toEqual({ kind: "charClass", name: "Digit" });
  });

  it("parses interpolation", () => {
    const result = parseInput("d = %Digit;\n{d}");
    if (isError(result)) throw new Error("unexpected error");
    const atom = result.body.alternatives[0]?.items[0]?.inner.inner.base.atom;
    expect(atom).toEqual({ kind: "interpolation", name: "d" });
  });

  it("parses group", () => {
    const atom = firstAtom("('a' | 'b')");
    expect(atom.kind).toBe("group");
    if (atom.kind === "group") {
      expect(atom.inner.alternatives).toHaveLength(2);
    }
  });

  it("parses char range", () => {
    const item = firstItem("'a'..'z'");
    expect(item.inner.inner.base.kind).toBe("charRange");
    if (item.inner.inner.base.kind === "charRange") {
      expect(item.inner.inner.base.from).toEqual({ kind: "literal", content: "a" });
      expect(item.inner.inner.base.to).toEqual({ kind: "literal", content: "z" });
    }
  });

  it("parses position assertion", () => {
    expect(firstAtom("@word-start %Alpha * 1..?")).toEqual({
      kind: "positionAssertion",
      name: "word-start",
    });
  });
});

// ---------------------------------------------------------------------------
// Exclusion
// ---------------------------------------------------------------------------

describe("exclusion", () => {
  it("parses exclusion", () => {
    const excl = firstItem("%Digit excluding '8'..'9'").inner.inner;
    expect(excl.excluded).not.toBeNull();
    expect(excl.base).toEqual({
      kind: "singleAtom",
      atom: { kind: "charClass", name: "Digit" },
    });
    if (excl.excluded) {
      expect(excl.excluded.kind).toBe("charRange");
    }
  });
});

// ---------------------------------------------------------------------------
// Repetition counts
// ---------------------------------------------------------------------------

describe("repetition counts", () => {
  it("parses exact repetition * 4", () => {
    const count = firstRepCount("%Digit * 4");
    expect(count.min).toBe(4);
    expect(count.max).toEqual({ kind: "none" });
    expect(count.lazy).toBe(false);
  });

  it("parses bounded repetition * 3..10", () => {
    const count = firstRepCount("%Digit * 3..10");
    expect(count.min).toBe(3);
    expect(count.max).toEqual({ kind: "exact", value: 10 });
    expect(count.lazy).toBe(false);
  });

  it("parses unbounded repetition * 1..?", () => {
    const count = firstRepCount("%Digit * 1..?");
    expect(count.min).toBe(1);
    expect(count.max).toEqual({ kind: "unbounded" });
    expect(count.lazy).toBe(false);
  });

  it("parses fewest * 1..? fewest", () => {
    const count = firstRepCount("%Digit * 1..? fewest");
    expect(count.min).toBe(1);
    expect(count.max).toEqual({ kind: "unbounded" });
    expect(count.lazy).toBe(true);
  });

  it("parses fewest * 0..1 fewest", () => {
    const count = firstRepCount("%Digit * 0..1 fewest");
    expect(count.min).toBe(0);
    expect(count.max).toEqual({ kind: "exact", value: 1 });
    expect(count.lazy).toBe(true);
  });

  it("parses fewest * 3..10 fewest", () => {
    const count = firstRepCount("%Digit * 3..10 fewest");
    expect(count.min).toBe(3);
    expect(count.max).toEqual({ kind: "exact", value: 10 });
    expect(count.lazy).toBe(true);
  });
});

// ---------------------------------------------------------------------------
// Capture
// ---------------------------------------------------------------------------

describe("capture", () => {
  it("parses named capture", () => {
    const item = firstItem("%Digit * 4 as year");
    expect(item.name).toBe("year");
  });

  it("no capture name when not specified", () => {
    const item = firstItem("%Digit * 4");
    expect(item.name).toBeNull();
  });
});

// ---------------------------------------------------------------------------
// Sequence and alternation
// ---------------------------------------------------------------------------

describe("sequence and alternation", () => {
  it("sequence has two items", () => {
    const body = getBody("'a' 'b'");
    expect(body.alternatives).toHaveLength(1);
    expect(body.alternatives[0]!.items).toHaveLength(2);
  });

  it("two-way alternation has two alternatives", () => {
    const body = getBody("'a' | 'b'");
    expect(body.alternatives).toHaveLength(2);
  });

  it("three-way alternation has three alternatives", () => {
    const body = getBody("'a' | 'b' | 'c'");
    expect(body.alternatives).toHaveLength(3);
  });
});

// ---------------------------------------------------------------------------
// Annotations
// ---------------------------------------------------------------------------

describe("annotations", () => {
  it("parses annotation with value true", () => {
    const result = parseInput("!case-insensitive = true\n\n'hello'");
    if (isError(result)) throw new Error("unexpected error");
    expect(result.annotations).toHaveLength(1);
    expect(result.annotations[0]!.name).toBe("case-insensitive");
    expect(result.annotations[0]!.value).toBe(true);
  });

  it("parses annotation with value false", () => {
    const result = parseInput("!multiline = false\n\n'hello'");
    if (isError(result)) throw new Error("unexpected error");
    expect(result.annotations).toHaveLength(1);
    expect(result.annotations[0]!.name).toBe("multiline");
    expect(result.annotations[0]!.value).toBe(false);
  });
});

// ---------------------------------------------------------------------------
// Doc comments
// ---------------------------------------------------------------------------

describe("doc comments", () => {
  it("body comment stored in bodyComments", () => {
    const result = parseInput("# describes the body\n'x'");
    if (isError(result)) throw new Error("unexpected error");
    expect(result.bodyComments).toContain(" describes the body");
  });

  it("ptern-level comment stored in pternComments", () => {
    const result = parseInput("# top comment\n\n'x'");
    if (isError(result)) throw new Error("unexpected error");
    expect(result.pternComments).toContain(" top comment");
    expect(result.bodyComments).toHaveLength(0);
  });

  it("annotation comment stored on annotation", () => {
    const result = parseInput("# flag comment\n!multiline = true\n\n'x'");
    if (isError(result)) throw new Error("unexpected error");
    expect(result.annotations[0]!.comments).toContain(" flag comment");
  });

  it("definition comment stored on definition", () => {
    const result = parseInput("# about word\nword = %Alpha * 1..? ;\n\n{word}");
    if (isError(result)) throw new Error("unexpected error");
    expect(result.definitions[0]!.comments).toContain(" about word");
  });

  it("multiple body comments collected", () => {
    const result = parseInput("# line one\n# line two\n'x'");
    if (isError(result)) throw new Error("unexpected error");
    expect(result.bodyComments).toHaveLength(2);
  });
});

// ---------------------------------------------------------------------------
// Parser success (complex patterns)
// ---------------------------------------------------------------------------

describe("parser success", () => {
  it("parses iso date pattern", () => {
    const input =
      "yyyy = %Digit * 4;\n" +
      "mm = ('0' '1'..'9') | ('1' '0'..'2');\n" +
      "dd = ('0' '1'..'9') | ('1'..'2' %Digit) | ('3' '0'..'1');\n" +
      "{yyyy} as year '-' {mm} as month '-' {dd} as day";
    const result = parseInput(input);
    expect(isError(result)).toBe(false);
    if (!isError(result)) {
      expect(result.definitions).toHaveLength(3);
    }
  });

  it("parses group in alternation", () => {
    const result = parseInput("('a' | 'b') 'c'");
    expect(isError(result)).toBe(false);
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
