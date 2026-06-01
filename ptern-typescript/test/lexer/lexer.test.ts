import { describe, expect, it } from "bun:test";
import { lex } from "../../src/lexer/lexer";
import type { Token } from "../../src/lexer/token";

const ws = (hasBlankLine: boolean): Token => ({ kind: "whitespace", hasBlankLine });
const comment = (content: string): Token => ({ kind: "comment", content });
const sq = (content: string): Token => ({ kind: "singleQuotedLiteral", content });
const dq = (content: string): Token => ({ kind: "doubleQuotedLiteral", content });
const cc = (name: string): Token => ({ kind: "characterClass", name });
const pa = (name: string): Token => ({ kind: "positionAssertion", name });
const id = (name: string): Token => ({ kind: "identifier", name });
const int = (value: number): Token => ({ kind: "integer", value });

describe("lexer", () => {
  it("lex empty string", () => {
    expect(lex("")).toEqual([]);
  });

  it("lex single-quoted literal", () => {
    expect(lex("'hello'")).toEqual([sq("hello")]);
  });

  it("lex double-quoted literal", () => {
    expect(lex('"world"')).toEqual([dq("world")]);
  });

  it("lex string with escaped quote", () => {
    expect(lex("'it\\'s'")).toEqual([sq("it\\'s")]);
  });

  it("lex string with unicode escape", () => {
    expect(lex("'\\u0041'")).toEqual([sq("\\u0041")]);
  });

  it("lex single-quoted with Unicode characters", () => {
    expect(lex("'café'")).toEqual([sq("café")]);
  });

  it("lex double-quoted with Unicode characters", () => {
    expect(lex('"naïve"')).toEqual([dq("naïve")]);
  });

  it("lex CJK string", () => {
    expect(lex("'日本語'")).toEqual([sq("日本語")]);
  });

  it("lex emoji string", () => {
    expect(lex("'🎉'")).toEqual([sq("🎉")]);
  });

  it("lex mixed unicode", () => {
    expect(lex("'abc défg'")).toEqual([sq("abc défg")]);
  });

  it("lex character class", () => {
    expect(lex("%Digit")).toEqual([cc("Digit")]);
  });

  it("lex single-letter character class", () => {
    expect(lex("%L")).toEqual([cc("L")]);
  });

  it("lex integer", () => {
    expect(lex("42")).toEqual([int(42)]);
  });

  it("lex range operator", () => {
    expect(lex("..")).toEqual([{ kind: "rangeOperator" }]);
  });

  it("lex operators", () => {
    expect(lex("*|=;{}()")).toEqual([
      { kind: "asterisk" },
      { kind: "alternativeOperator" },
      { kind: "equals" },
      { kind: "semicolon" },
      { kind: "leftBrace" },
      { kind: "rightBrace" },
      { kind: "leftParen" },
      { kind: "rightParen" },
    ]);
  });

  it("lex as keyword", () => {
    expect(lex("as")).toEqual([{ kind: "as" }]);
  });

  it("lex excluding keyword", () => {
    expect(lex("excluding")).toEqual([{ kind: "excluding" }]);
  });

  it("lex fewest keyword", () => {
    expect(lex("fewest")).toEqual([{ kind: "fewest" }]);
  });

  it("fewest not consumed as prefix of longer identifier", () => {
    expect(lex("fewest-more")).toEqual([id("fewest-more")]);
  });

  it("lex identifier with hyphen", () => {
    expect(lex("my-pattern")).toEqual([id("my-pattern")]);
  });

  it("whitespace collapses run", () => {
    expect(lex("a   b")).toEqual([id("a"), ws(false), id("b")]);
  });

  // -------------------------------------------------------------------------
  // Comments
  // -------------------------------------------------------------------------

  it("lex comment followed by token", () => {
    expect(lex("# a comment\n'x'")).toEqual([
      comment(" a comment"),
      ws(false),
      sq("x"),
    ]);
  });

  it("lex comment at end of input", () => {
    expect(lex("# no newline")).toEqual([comment(" no newline")]);
  });

  it("inline comment is an error", () => {
    const result = lex("'x' # inline comment");
    expect(result).toEqual({ kind: "inlineComment" });
  });

  it("inline comment mid-expression is an error", () => {
    const result = lex("%Digit # not allowed here");
    expect(result).toEqual({ kind: "inlineComment" });
  });

  // -------------------------------------------------------------------------
  // Whitespace blank-line detection
  // -------------------------------------------------------------------------

  it("single newline has no blank line", () => {
    expect(lex("'a'\n'b'")).toEqual([sq("a"), ws(false), sq("b")]);
  });

  it("blank line sets hasBlankLine", () => {
    expect(lex("'a'\n\n'b'")).toEqual([sq("a"), ws(true), sq("b")]);
  });

  it("blank line with spaces sets hasBlankLine", () => {
    expect(lex("'a'\n   \n'b'")).toEqual([sq("a"), ws(true), sq("b")]);
  });

  it("comment at start of file", () => {
    expect(lex("# ptern doc\n'x'")).toEqual([
      comment(" ptern doc"),
      ws(false),
      sq("x"),
    ]);
  });

  it("comment after blank line at top", () => {
    expect(lex("# ptern doc\n\n'x'")).toEqual([
      comment(" ptern doc"),
      ws(true),
      sq("x"),
    ]);
  });

  // -------------------------------------------------------------------------
  // Repetition and misc tokens
  // -------------------------------------------------------------------------

  it("lex repetition expression", () => {
    expect(lex("%Digit * 4")).toEqual([
      cc("Digit"),
      ws(false),
      { kind: "asterisk" },
      ws(false),
      int(4),
    ]);
  });

  it("lex question mark", () => {
    expect(lex("?")).toEqual([{ kind: "questionMark" }]);
  });

  it("lex unbounded repetition", () => {
    expect(lex("%Digit * 1..?")).toEqual([
      cc("Digit"),
      ws(false),
      { kind: "asterisk" },
      ws(false),
      int(1),
      { kind: "rangeOperator" },
      { kind: "questionMark" },
    ]);
  });

  it("lex bounded repetition", () => {
    expect(lex("'*' * 3..10")).toEqual([
      sq("*"),
      ws(false),
      { kind: "asterisk" },
      ws(false),
      int(3),
      { kind: "rangeOperator" },
      int(10),
    ]);
  });

  it("lex definition", () => {
    expect(lex("yyyy = %Digit * 4;")).toEqual([
      id("yyyy"),
      ws(false),
      { kind: "equals" },
      ws(false),
      cc("Digit"),
      ws(false),
      { kind: "asterisk" },
      ws(false),
      int(4),
      { kind: "semicolon" },
    ]);
  });

  it("lex alternatives", () => {
    expect(lex("'a' | 'b'")).toEqual([
      sq("a"),
      ws(false),
      { kind: "alternativeOperator" },
      ws(false),
      sq("b"),
    ]);
  });

  it("lex bang", () => {
    expect(lex("!")).toEqual([{ kind: "bang" }]);
  });

  it("lex true keyword", () => {
    expect(lex("true")).toEqual([{ kind: "true" }]);
  });

  it("lex false keyword", () => {
    expect(lex("false")).toEqual([{ kind: "false" }]);
  });

  it("lex annotation", () => {
    expect(lex("!case-insensitive = true")).toEqual([
      { kind: "bang" },
      id("case-insensitive"),
      ws(false),
      { kind: "equals" },
      ws(false),
      { kind: "true" },
    ]);
  });

  it("lex excluding expression", () => {
    expect(lex("%Digit excluding '8'..'9'")).toEqual([
      cc("Digit"),
      ws(false),
      { kind: "excluding" },
      ws(false),
      sq("8"),
      { kind: "rangeOperator" },
      sq("9"),
    ]);
  });

  // -------------------------------------------------------------------------
  // Position assertions
  // -------------------------------------------------------------------------

  it("lex @word-start", () => {
    expect(lex("@word-start")).toEqual([pa("word-start")]);
  });

  it("lex @word-end", () => {
    expect(lex("@word-end")).toEqual([pa("word-end")]);
  });

  it("lex @line-start", () => {
    expect(lex("@line-start")).toEqual([pa("line-start")]);
  });

  it("lex @line-end", () => {
    expect(lex("@line-end")).toEqual([pa("line-end")]);
  });

  it("bare @ is an error", () => {
    const result = lex("@");
    expect(typeof result === "object" && "kind" in result && result.kind !== undefined &&
      !Array.isArray(result)).toBe(true);
  });

  it("position assertion in sequence", () => {
    expect(lex("@word-start %Alpha @word-end")).toEqual([
      pa("word-start"),
      ws(false),
      cc("Alpha"),
      ws(false),
      pa("word-end"),
    ]);
  });
});
