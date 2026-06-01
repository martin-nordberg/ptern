import { describe, expect, it } from "bun:test";
import { lex } from "../../src/lexer/lexer";
import { parse } from "../../src/parser/parser";
import { compile } from "../../src/codegen/codegen";
import type { ParsedPtern } from "../../src/parser/ast";

function compileInput(input: string): ReturnType<typeof compile> {
  const tokens = lex(input);
  if (!Array.isArray(tokens)) throw new Error("lex failed: " + JSON.stringify(tokens));
  const result = parse(tokens);
  if ("kind" in result) throw new Error("parse failed: " + JSON.stringify(result));
  return compile(result as ParsedPtern);
}

function source(input: string): string {
  return compileInput(input).source;
}

function flags(input: string): string {
  return compileInput(input).flags;
}

describe("codegen flags", () => {
  it("default flags are v", () => {
    expect(flags("'x'")).toBe("v");
  });

  it("case-insensitive = true adds i flag", () => {
    expect(flags("!case-insensitive = true\n'x'")).toBe("vi");
  });

  it("case-insensitive = false no i flag", () => {
    expect(flags("!case-insensitive = false\n'x'")).toBe("v");
  });

  it("multiline annotation adds m flag", () => {
    expect(flags("!multiline = true\n'x'")).toBe("vm");
  });

  it("multiline with case-insensitive", () => {
    expect(flags("!multiline = true\n!case-insensitive = true\n'x'")).toBe("vim");
  });

  it("line-start auto-enables multiline flag", () => {
    expect(flags("@line-start %Alpha * 1..?")).toBe("vm");
  });

  it("line-end auto-enables multiline flag", () => {
    expect(flags("%Alpha * 1..? @line-end")).toBe("vm");
  });

  it("word boundary does not add multiline flag", () => {
    expect(flags("@word-start %Alpha * 1..? @word-end")).toBe("v");
  });

  it("line boundary in definition auto-enables multiline", () => {
    expect(flags("row = @line-start %Alpha * 1..? @line-end; {row}")).toBe("vm");
  });
});

describe("codegen literals", () => {
  it("plain literal", () => {
    expect(source("'hello'")).toBe("hello");
  });

  it("literal dot is escaped", () => {
    expect(source("'a.b'")).toBe("a\\.b");
  });

  it("literal parens are escaped", () => {
    expect(source("'(x)'")).toBe("\\(x\\)");
  });

  it("literal pipe is escaped", () => {
    expect(source("'a|b'")).toBe("a\\|b");
  });

  it("literal star is escaped", () => {
    expect(source("'a*'")).toBe("a\\*");
  });

  it("literal backslash escape", () => {
    expect(source("'\\\\'")).toBe("\\\\");
  });

  it("literal newline escape", () => {
    expect(source("'\\n'")).toBe("\\n");
  });

  it("literal tab escape", () => {
    expect(source("'\\t'")).toBe("\\t");
  });

  it("literal single quote escape", () => {
    expect(source("'it\\'s'")).toBe("it's");
  });

  it("literal unicode escape", () => {
    expect(source("'\\u0041'")).toBe("\\u0041");
  });
});

describe("codegen character classes", () => {
  it("%Digit", () => expect(source("%Digit")).toBe("[0-9]"));
  it("%Alpha", () => expect(source("%Alpha")).toBe("[A-Za-z]"));
  it("%Alnum", () => expect(source("%Alnum")).toBe("[A-Za-z0-9]"));
  it("%Lower", () => expect(source("%Lower")).toBe("[a-z]"));
  it("%Upper", () => expect(source("%Upper")).toBe("[A-Z]"));
  it("%Word", () => expect(source("%Word")).toBe("[A-Za-z0-9_]"));
  it("%Xdigit", () => expect(source("%Xdigit")).toBe("[0-9A-Fa-f]"));
  it("%Any", () => expect(source("%Any")).toBe("[\\s\\S]"));
  it("%L", () => expect(source("%L")).toBe("\\p{L}"));
  it("%Letter", () => expect(source("%Letter")).toBe("\\p{L}"));
  it("%Ll", () => expect(source("%Ll")).toBe("\\p{Ll}"));
  it("%N", () => expect(source("%N")).toBe("\\p{N}"));
});

describe("codegen character ranges", () => {
  it("a..z", () => expect(source("'a'..'z'")).toBe("[a-z]"));
  it("0..9", () => expect(source("'0'..'9'")).toBe("[0-9]"));
});

describe("codegen repetition", () => {
  it("exact repetition", () => expect(source("%Digit * 4")).toBe("[0-9]{4}"));
  it("bounded repetition", () => expect(source("%Digit * 1..10")).toBe("[0-9]{1,10}"));
  it("unbounded repetition", () => expect(source("%Digit * 1..?")).toBe("[0-9]+"));
  it("zero or more", () => expect(source("%Digit * 0..?")).toBe("[0-9]*"));
  it("optional", () => expect(source("%Digit * 0..1")).toBe("[0-9]?"));
  it("multi-char literal wraps in (?:...)", () => expect(source("'ab' * 3")).toBe("(?:ab){3}"));
  it("group repetition", () => expect(source("('a' | 'b') * 3")).toBe("(?:[ab]){3}"));
});

describe("codegen sequence and alternation", () => {
  it("sequence", () => expect(source("'a' 'b' 'c'")).toBe("abc"));
  it("mixed sequence", () => expect(source("'x' %Digit")).toBe("x[0-9]"));
  it("two-way alternation merges to class", () => expect(source("'a' | 'b'")).toBe("[ab]"));
  it("three-way alternation merges to class", () => expect(source("'a' | 'b' | 'c'")).toBe("[abc]"));
});

describe("codegen captures", () => {
  it("named capture", () => expect(source("%Digit * 4 as year")).toBe("(?<year>[0-9]{4})"));
  it("named capture on literal", () => expect(source("'hello' as greeting")).toBe("(?<greeting>hello)"));
});

describe("codegen exclusion", () => {
  it("digit excluding range", () => expect(source("%Digit excluding '8'..'9'")).toBe("[[0-9]--[8-9]]"));
  it("alpha excluding char", () => expect(source("%Alpha excluding 'x'")).toBe("[[A-Za-z]--[x]]"));
  it("range excluding char", () => expect(source("'a'..'z' excluding 'x'")).toBe("[[a-z]--[x]]"));
  it("excluding group of single chars", () => expect(source("%Digit excluding ('1'|'3'|'5'|'7'|'9')")).toBe("[[0-9]--[13579]]"));
  it("excluding group with range", () => expect(source("%Alpha excluding ('a'..'e' | 'x')")).toBe("[[A-Za-z]--[[a-e]x]]"));
  it("excluding group single alt", () => expect(source("'a'..'z' excluding ('x')")).toBe("[[a-z]--[x]]"));
  it("excluding interpolation with grouped body", () =>
    expect(source("oddDigit = ('1'|'3'|'5'|'7'|'9');\n%Digit excluding {oddDigit}")).toBe("[[0-9]--[13579]]"));
  it("excluding interpolation flat body", () =>
    expect(source("odds = '1'|'3'|'5';\n%Alpha excluding {odds}")).toBe("[[A-Za-z]--[135]]"));
  it("excluding interpolation charclass body", () =>
    expect(source("d = %Digit;\n%Alpha excluding {d}")).toBe("[[A-Za-z]--[[0-9]]]"));
  it("excluding interp range alts", () =>
    expect(source("rangeAlt = ('a'..'m' | 'n'..'z');\n%Alpha excluding {rangeAlt}")).toBe("[[A-Za-z]--[[a-m][n-z]]]"));
});

describe("codegen groups", () => {
  it("group", () => expect(source("('a' | 'b')")).toBe("(?:[ab])"));
  it("nested group", () => expect(source("(('a' | 'b') 'c')")).toBe("(?:(?:[ab])c)"));
});

describe("codegen definitions and interpolations", () => {
  it("definition interpolation", () => expect(source("d = %Digit; {d}")).toBe("(?:[0-9])"));
  it("definition repeated", () => expect(source("d = %Digit * 4; {d} '-' {d}")).toBe("(?:[0-9]{4})-(?:[0-9]{4})"));
  it("definition chain", () => expect(source("a = 'x'; b = {a} 'y'; {b}")).toBe("(?:(?:x)y)"));
  it("definition with capture", () => expect(source("yyyy = %Digit * 4; {yyyy} as year")).toBe("(?<year>(?:[0-9]{4}))"));
});

describe("codegen position assertions", () => {
  it("word-start compiles to \\b", () => expect(source("@word-start %Alpha * 1..?")).toBe("\\b[A-Za-z]+"));
  it("word-end compiles to \\b", () => expect(source("%Alpha * 1..? @word-end")).toBe("[A-Za-z]+\\b"));
  it("word boundaries around word", () => expect(source("@word-start %Alpha * 1..? @word-end")).toBe("\\b[A-Za-z]+\\b"));
  it("line-start compiles to ^", () => expect(source("@line-start %Digit * 1..?")).toBe("^[0-9]+"));
  it("line-end compiles to $", () => expect(source("%Digit * 1..? @line-end")).toBe("[0-9]+$"));
});

describe("codegen backreferences", () => {
  it("backreference emits \\k<name> syntax", () =>
    expect(source("%Alpha * 1..? as word '-' {word}")).toBe("(?<word>[A-Za-z]+)-\\k<word>"));
  it("backreference after definition interpolation", () =>
    expect(source("num = %Digit * 1..3; {num} as tag ':' {tag}")).toBe("(?<tag>(?:[0-9]{1,3})):\\k<tag>"));
});

describe("codegen fewest (lazy quantifiers)", () => {
  it("one or more fewest", () => expect(source("%Any * 1..? fewest")).toBe("[\\s\\S]+?"));
  it("zero or more fewest", () => expect(source("%Any * 0..? fewest")).toBe("[\\s\\S]*?"));
  it("optional fewest", () => expect(source("%Any * 0..1 fewest")).toBe("[\\s\\S]??"));
  it("bounded fewest", () => expect(source("%Any * 3..10 fewest")).toBe("[\\s\\S]{3,10}?"));
  it("at-least-n fewest", () => expect(source("%Any * 3..? fewest")).toBe("[\\s\\S]{3,}?"));
  it("greedy remains default", () => expect(source("%Any * 1..?")).toBe("[\\s\\S]+"));
});

describe("codegen integration", () => {
  it("iso date", () => {
    const input =
      "yyyy = %Digit * 4;\n" +
      "mm = ('0' '1'..'9') | ('1' '0'..'2');\n" +
      "dd = ('0' '1'..'9') | ('1'..'2' %Digit) | ('3' '0'..'1');\n" +
      "{yyyy} as year '-' {mm} as month '-' {dd} as day";
    const result = compileInput(input);
    expect(result.flags).toBe("v");
    expect(result.source).toBe(
      "(?<year>(?:[0-9]{4}))-(?<month>(?:(?:0[1-9])|(?:1[0-2])))-(?<day>(?:(?:0[1-9])|(?:[1-2][0-9])|(?:3[0-1])))",
    );
  });

  it("semantic version", () => {
    const input = "num = %Digit * 1..10; {num} as major '.' {num} as minor '.' {num} as patch";
    expect(source(input)).toBe(
      "(?<major>(?:[0-9]{1,10}))\\.(?<minor>(?:[0-9]{1,10}))\\.(?<patch>(?:[0-9]{1,10}))",
    );
  });

  it("zip code", () => {
    expect(source("%Digit * 5 ('-' %Digit * 4) * 0..1")).toBe("[0-9]{5}(?:-[0-9]{4})?");
  });
});
