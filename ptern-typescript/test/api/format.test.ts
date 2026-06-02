import { describe, expect, it } from "bun:test";
import { format, PternFormatError } from "../../src/index";
import type { FormatOptions } from "../../src/index";

function fmt(source: string): string {
  return format(source);
}

function fmtOpts(source: string, opts: Partial<FormatOptions>): string {
  return format(source, opts);
}

// ---------------------------------------------------------------------------
// Error cases
// ---------------------------------------------------------------------------

describe("format errors", () => {
  it("throws PternFormatError on lex error", () => {
    expect(() => format("@")).toThrow(PternFormatError);
  });

  it("throws PternFormatError on parse error", () => {
    expect(() => format("* 3")).toThrow(PternFormatError);
  });

  it("throws PternFormatError when lineWidth < 40", () => {
    expect(() => format("'x'", { lineWidth: 39 })).toThrow(PternFormatError);
    try {
      format("'x'", { lineWidth: 39 });
    } catch (e) {
      expect((e as PternFormatError).formatError.kind).toBe("invalidLineWidth");
    }
  });

  it("lineWidth exactly 40 is valid", () => {
    expect(() => format("'x'", { lineWidth: 40 })).not.toThrow();
  });

  it("propagates lex error", () => {
    expect(() => format("'unterminated")).toThrow(PternFormatError);
  });

  it("propagates parse error", () => {
    expect(() => format("* 3")).toThrow(PternFormatError);
  });
});

// ---------------------------------------------------------------------------
// Token normalisation
// ---------------------------------------------------------------------------

describe("token normalisation", () => {
  it("double-quoted literal becomes single-quoted", () => {
    expect(fmt('"hello"')).toBe("'hello'");
  });

  it("double-quoted preserved when contains single quote", () => {
    expect(fmt('"it\'s"')).toBe("\"it's\"");
  });

  it("char class preserved", () => {
    expect(fmt("%Alpha")).toBe("%Alpha");
  });

  it("interpolation braces normalised", () => {
    expect(fmt("d = 'x';\n{ d }")).toContain("{d}");
  });

  it("position assertion preserved", () => {
    expect(fmt("@word-start %Alpha * 1..? @word-end")).toBe("@word-start %Alpha * 1..? @word-end");
  });
});

// ---------------------------------------------------------------------------
// Body expression — basic normalisation
// ---------------------------------------------------------------------------

describe("body expression normalisation", () => {
  it("sequence spaced correctly", () => {
    expect(fmt("'a' 'b' 'c'")).toBe("'a' 'b' 'c'");
  });

  it("alternation gets spaces around |", () => {
    expect(fmt("'a'|'b'|'c'")).toBe("'a' | 'b' | 'c'");
  });

  it("exact repetition gets spaces around *", () => {
    expect(fmt("%Digit*4")).toBe("%Digit * 4");
  });

  it("range repetition normalised", () => {
    expect(fmt("%Alpha*1..?")).toBe("%Alpha * 1..?");
  });

  it("bounded repetition normalised", () => {
    expect(fmt("%Digit*3..10")).toBe("%Digit * 3..10");
  });

  it("lazy repetition normalised", () => {
    expect(fmt("%Digit*1..? fewest")).toBe("%Digit * 1..? fewest");
  });

  it("capture normalised", () => {
    expect(fmt("%Digit*4 as year")).toBe("%Digit * 4 as year");
  });

  it("exclusion normalised", () => {
    expect(fmt("%Alpha excluding 'q'")).toBe("%Alpha excluding 'q'");
  });

  it("char range normalised", () => {
    expect(fmt("'a'..'z'")).toBe("'a'..'z'");
  });

  it("group with non-compact formatting", () => {
    expect(fmt("('a'|'b')")).toBe("( 'a' | 'b' )");
  });
});

// ---------------------------------------------------------------------------
// Annotations
// ---------------------------------------------------------------------------

describe("annotations", () => {
  it("single annotation true", () => {
    expect(fmt("!multiline = true\n'x'")).toBe("!multiline = true\n\n'x'");
  });

  it("single annotation false", () => {
    expect(fmt("!multiline = false\n'x'")).toBe("!multiline = false\n\n'x'");
  });

  it("annotations sorted alphabetically", () => {
    const result = fmt("!multiline = true\n!case-insensitive = true\n'x'");
    expect(result).toBe("!case-insensitive = true\n!multiline        = true\n\n'x'");
  });

  it("two annotations aligned", () => {
    expect(fmt("!substitutable = true\n!multiline = true\n'x'")).toBe(
      "!multiline     = true\n!substitutable = true\n\n'x'",
    );
  });

  it("two annotations not aligned when aligned=false", () => {
    const result = fmtOpts("!substitutable = true\n!multiline = true\n'x'", { aligned: false });
    expect(result).toBe("!multiline = true\n!substitutable = true\n\n'x'");
  });
});

// ---------------------------------------------------------------------------
// Definitions
// ---------------------------------------------------------------------------

describe("definitions", () => {
  it("single definition aligned with 2 extra spaces", () => {
    expect(fmt("word = %Alpha * 1..? ;\n{word}")).toBe("word  = %Alpha * 1..? ;\n\n{word}");
  });

  it("two definitions aligned at same column", () => {
    expect(fmt("word = %Alpha * 1..? ;\ndigit = %Digit * 1..? ;\n{word} {digit}")).toBe(
      "word   = %Alpha * 1..? ;\ndigit  = %Digit * 1..? ;\n\n{word} {digit}",
    );
  });

  it("definitions not aligned when aligned=false", () => {
    const result = fmtOpts(
      "word = %Alpha * 1..? ;\ndigit = %Digit * 1..? ;\n{word} {digit}",
      { aligned: false },
    );
    expect(result).toBe("word = %Alpha * 1..? ;\ndigit = %Digit * 1..? ;\n\n{word} {digit}");
  });
});

// ---------------------------------------------------------------------------
// Definition line breaking — D1
// ---------------------------------------------------------------------------

describe("definition line breaking D1", () => {
  it("breaks after = when body fits on next line", () => {
    expect(fmtOpts(
      "word = %Digit * 4 %Alpha * 4 %Digit * 4 ;\n{word}",
      { lineWidth: 40, aligned: false },
    )).toBe("word =\n    %Digit * 4 %Alpha * 4 %Digit * 4 ;\n\n{word}");
  });
});

// ---------------------------------------------------------------------------
// Definition line breaking — D2
// ---------------------------------------------------------------------------

describe("definition line breaking D2", () => {
  it("wraps long definition body mid-line", () => {
    expect(fmtOpts(
      "word = 'aaaaaa' 'bbbbbb' 'cccccc' 'dddddd' 'eeeeee' ;\n{word}",
      { lineWidth: 40, aligned: false },
    )).toBe(
      "word = 'aaaaaa' 'bbbbbb' 'cccccc'\n       'dddddd' 'eeeeee' ;\n\n{word}",
    );
  });
});

// ---------------------------------------------------------------------------
// Body expression line breaking — B1
// ---------------------------------------------------------------------------

describe("body expression line breaking B1", () => {
  it("wraps long sequence at rightmost space ≤ lineWidth", () => {
    expect(fmtOpts(
      "'aaaaaa' 'bbbbbb' 'cccccc' 'dddddd' 'eeeeee'",
      { lineWidth: 40, aligned: false },
    )).toBe("'aaaaaa' 'bbbbbb' 'cccccc' 'dddddd'\n'eeeeee'");
  });

  it("repeated B1 breaks when needed", () => {
    expect(fmtOpts(
      "'aaaaaaaaaa' 'bbbbbbbbbb' 'cccccccccc' 'dddddddddd' 'eeeeeeeeee'",
      { lineWidth: 40, aligned: false },
    )).toBe(
      "'aaaaaaaaaa' 'bbbbbbbbbb' 'cccccccccc'\n'dddddddddd' 'eeeeeeeeee'",
    );
  });
});

// ---------------------------------------------------------------------------
// Body expression line breaking — B2
// ---------------------------------------------------------------------------

describe("body expression line breaking B2", () => {
  it("wraps alternation at rightmost | ≤ lineWidth", () => {
    expect(fmtOpts(
      "'alpha-bravo' | 'charlie-delta' | 'echo-foxtrot'",
      { lineWidth: 40, aligned: false },
    )).toBe("'alpha-bravo' | 'charlie-delta'\n| 'echo-foxtrot'");
  });
});

// ---------------------------------------------------------------------------
// B3 — no break available
// ---------------------------------------------------------------------------

describe("body line breaking B3 (no break)", () => {
  it("outputs long literal as-is when no break point", () => {
    const longLiteral = "'" + "x".repeat(50) + "'";
    expect(fmtOpts(longLiteral, { lineWidth: 40, aligned: false })).toBe(longLiteral);
  });
});

// ---------------------------------------------------------------------------
// Compact mode
// ---------------------------------------------------------------------------

describe("compact mode", () => {
  it("removes spaces around |", () => {
    expect(fmtOpts("'a' | 'b' | 'c'", { compact: true })).toBe("'a'|'b'|'c'");
  });

  it("removes spaces around *", () => {
    expect(fmtOpts("%Alpha * 1..?", { compact: true })).toBe("%Alpha*1..?");
  });

  it("removes spaces inside group", () => {
    expect(fmtOpts("( 'a' | 'b' )", { compact: true })).toBe("('a'|'b')");
  });

  it("suppresses blank separators between sections", () => {
    expect(fmtOpts(
      "!multiline = true\nword = %Alpha * 1..? ;\n{word}",
      { compact: true },
    )).toBe("!multiline = true\nword  = %Alpha*1..? ;\n{word}");
  });

  it("sequence space preserved in compact mode", () => {
    expect(fmtOpts("'a' 'b' 'c'", { compact: true })).toBe("'a' 'b' 'c'");
  });
});

// ---------------------------------------------------------------------------
// Doc comments
// ---------------------------------------------------------------------------

describe("doc comments", () => {
  it("ptern-level comment followed by blank line", () => {
    expect(fmt("# top comment\n\n'x'")).toBe("# top comment\n\n'x'");
  });

  it("body comment", () => {
    expect(fmt("# describes the body\n'x'")).toBe("# describes the body\n'x'");
  });

  it("annotation comment", () => {
    expect(fmt("# flag\n!multiline = true\n'x'")).toBe("# flag\n!multiline = true\n\n'x'");
  });

  it("definition with comment above", () => {
    expect(fmt("# about word\nword = %Alpha * 1..? ;\n{word}")).toBe(
      "# about word\nword  = %Alpha * 1..? ;\n\n{word}",
    );
  });

  it("blank line inserted before commented definition", () => {
    expect(fmt("a = 'x' ;\n# about b\nb = 'y' ;\n{a} {b}")).toBe(
      "a  = 'x' ;\n\n# about b\nb  = 'y' ;\n\n{a} {b}",
    );
  });

  it("comment content verbatim (spaces preserved)", () => {
    expect(fmt("#  two spaces  and trailing  \n'x'")).toBe("#  two spaces  and trailing  \n'x'");
  });

  it("compact: no blank before commented items", () => {
    expect(fmtOpts("a = 'x' ;\n# about b\nb = 'y' ;\n{a} {b}", { compact: true })).toBe(
      "a  = 'x' ;\n# about b\nb  = 'y' ;\n{a} {b}",
    );
  });
});

// ---------------------------------------------------------------------------
// Reordering
// ---------------------------------------------------------------------------

describe("reordering", () => {
  it("deps reordered before dependents", () => {
    expect(fmtOpts("b = {a} ;\na = 'x' ;\n{b}", { reordered: true, aligned: false })).toBe(
      "a = 'x' ;\nb = {a} ;\n\n{b}",
    );
  });

  it("alphabetical within same dependency layer", () => {
    expect(fmtOpts("c = 'z' ;\na = 'x' ;\n{a} {c}", { reordered: true, aligned: false })).toBe(
      "a = 'x' ;\nc = 'z' ;\n\n{a} {c}",
    );
  });

  it("reordered=false preserves source order", () => {
    expect(fmtOpts("b = {a} ;\na = 'x' ;\n{b}", { reordered: false, aligned: false })).toBe(
      "b = {a} ;\na = 'x' ;\n\n{b}",
    );
  });
});

// ---------------------------------------------------------------------------
// Idempotency
// ---------------------------------------------------------------------------

describe("idempotency", () => {
  it("simple pattern is idempotent", () => {
    const source = "'hello' 'world'";
    const first = fmt(source);
    expect(fmt(first)).toBe(first);
  });

  it("annotations and defs idempotent", () => {
    const source = "!case-insensitive = true\n!multiline = false\n\nword = %Alpha * 1..? ;\n\n{word}";
    const first = fmt(source);
    expect(fmt(first)).toBe(first);
  });

  it("comments idempotent", () => {
    const source = "# comment\n\n# about body\n'x'";
    const first = fmt(source);
    expect(fmt(first)).toBe(first);
  });
});
