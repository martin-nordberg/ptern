import { describe, expect, it } from "bun:test";
import { lex } from "../../src/lexer/lexer";
import { parse } from "../../src/parser/parser";
import { validate } from "../../src/semantic/validator";
import type { ParsedPtern } from "../../src/parser/ast";
import type { SemanticError } from "../../src/semantic/error";

function validateInput(input: string): SemanticError[] {
  const tokens = lex(input);
  if (!Array.isArray(tokens)) throw new Error("lex failed: " + JSON.stringify(tokens));
  const ast = parse(tokens);
  if ("kind" in ast) throw new Error("parse failed: " + JSON.stringify(ast));
  return validate(ast as ParsedPtern);
}

function hasError(errs: SemanticError[], target: SemanticError): boolean {
  return errs.some(e => JSON.stringify(e) === JSON.stringify(target));
}

// ---------------------------------------------------------------------------
// Empty literal errors
// ---------------------------------------------------------------------------

describe("emptyLiteral", () => {
  it("single-quoted empty literal", () => {
    expect(validateInput("''")).toEqual([{ kind: "emptyLiteral" }]);
  });

  it("double-quoted empty literal", () => {
    expect(validateInput('""')).toEqual([{ kind: "emptyLiteral" }]);
  });

  it("empty literal in sequence", () => {
    const errs = validateInput("'a' '' 'b'");
    expect(hasError(errs, { kind: "emptyLiteral" })).toBe(true);
  });
});

// ---------------------------------------------------------------------------
// No errors
// ---------------------------------------------------------------------------

describe("valid patterns", () => {
  it("valid literal", () => {
    expect(validateInput("'hello'")).toEqual([]);
  });

  it("valid char class", () => {
    expect(validateInput("%Digit")).toEqual([]);
  });

  it("valid range", () => {
    expect(validateInput("'a'..'z'")).toEqual([]);
  });

  it("valid exact repetition", () => {
    expect(validateInput("%Digit * 4")).toEqual([]);
  });

  it("valid bounded repetition", () => {
    expect(validateInput("%Digit * 1..10")).toEqual([]);
  });

  it("valid unbounded repetition", () => {
    expect(validateInput("%Digit * 1..?")).toEqual([]);
  });

  it("valid exclusion", () => {
    expect(validateInput("%Digit excluding '8'..'9'")).toEqual([]);
  });

  it("valid capture", () => {
    expect(validateInput("%Digit * 4 as year")).toEqual([]);
  });

  it("valid annotation", () => {
    expect(validateInput("!case-insensitive = true\n'x'")).toEqual([]);
  });

  it("valid escape sequences", () => {
    expect(validateInput("'\\n\\t\\r\\'\\\\'")).toEqual([]);
  });

  it("valid unicode escape", () => {
    expect(validateInput("'\\u0041'")).toEqual([]);
  });
});

// ---------------------------------------------------------------------------
// Escape sequence errors
// ---------------------------------------------------------------------------

describe("invalidEscapeSequence", () => {
  it("unknown escape \\z", () => {
    expect(validateInput("'\\z'")).toEqual([{ kind: "invalidEscapeSequence", seq: "\\z" }]);
  });

  it("multiple invalid escapes", () => {
    const errs = validateInput("'\\q\\p'");
    expect(hasError(errs, { kind: "invalidEscapeSequence", seq: "\\q" })).toBe(true);
    expect(hasError(errs, { kind: "invalidEscapeSequence", seq: "\\p" })).toBe(true);
  });
});

// ---------------------------------------------------------------------------
// Range endpoint errors
// ---------------------------------------------------------------------------

describe("invalidRangeEndpoint / invertedRange", () => {
  it("multi-char left endpoint", () => {
    const errs = validateInput("'ab'..'z'");
    expect(hasError(errs, { kind: "invalidRangeEndpoint", content: "ab" })).toBe(true);
  });

  it("non-literal range endpoint", () => {
    const errs = validateInput("'a'..%Digit");
    expect(errs).not.toEqual([]);
  });

  it("inverted range z..a", () => {
    expect(validateInput("'z'..'a'")).toEqual([{ kind: "invertedRange", from: "z", to: "a" }]);
  });

  it("equal range is valid", () => {
    expect(validateInput("'a'..'a'")).toEqual([]);
  });
});

// ---------------------------------------------------------------------------
// Repetition bound errors
// ---------------------------------------------------------------------------

describe("invertedRepetitionBounds", () => {
  it("inverted bounds 10..3", () => {
    expect(validateInput("%Digit * 10..3")).toEqual([{ kind: "invertedRepetitionBounds", min: 10, max: 3 }]);
  });

  it("equal bounds 3..3 is valid", () => {
    expect(validateInput("%Digit * 3..3")).toEqual([]);
  });
});

// ---------------------------------------------------------------------------
// Exclusion operand errors
// ---------------------------------------------------------------------------

describe("emptyCharacterSet / invalidExclusionOperand", () => {
  it("charclass excluding same charclass → emptyCharacterSet", () => {
    expect(validateInput("%Digit excluding %Digit")).toEqual([{ kind: "emptyCharacterSet" }]);
  });

  it("single char excluding same char → emptyCharacterSet", () => {
    expect(validateInput("'x' excluding 'x'")).toEqual([{ kind: "emptyCharacterSet" }]);
  });

  it("range excluding same range → emptyCharacterSet", () => {
    expect(validateInput("'a'..'z' excluding 'a'..'z'")).toEqual([{ kind: "emptyCharacterSet" }]);
  });

  it("non-empty exclusion with different operands", () => {
    expect(validateInput("%Digit excluding '0'")).toEqual([]);
  });

  it("valid exclusion group with literals", () => {
    expect(validateInput("%Digit excluding ('1'|'3'|'5'|'7'|'9')")).toEqual([]);
  });

  it("valid exclusion group single alt", () => {
    expect(validateInput("'a'..'z' excluding ('a')")).toEqual([]);
  });

  it("valid exclusion group with range", () => {
    expect(validateInput("%Alpha excluding ('a'..'e' | 'x')")).toEqual([]);
  });

  it("valid exclusion group with charclass", () => {
    expect(validateInput("%Any excluding (%Digit | 'x')")).toEqual([]);
  });

  it("valid exclusion interpolation", () => {
    expect(validateInput("oddDigit = ('1'|'3'|'5'|'7'|'9');\n%Digit excluding {oddDigit}")).toEqual([]);
  });

  it("valid exclusion interpolation flat body", () => {
    expect(validateInput("odds = '1'|'3'|'5';\n%Digit excluding {odds}")).toEqual([]);
  });

  it("invalid exclusion interpolation non-charset", () => {
    const errs = validateInput("greeting = 'hello';\n%Alpha excluding {greeting}");
    expect(hasError(errs, { kind: "invalidExclusionOperand" })).toBe(true);
  });

  it("invalid exclusion group with multi-item sequence", () => {
    const errs = validateInput("'a'..'z' excluding ('a' 'b')");
    expect(hasError(errs, { kind: "invalidExclusionOperand" })).toBe(true);
  });

  it("invalid exclusion group with named capture", () => {
    const errs = validateInput("%Digit excluding ('1' as d)");
    expect(hasError(errs, { kind: "invalidExclusionOperand" })).toBe(true);
  });

  it("invalid exclusion group with repetition", () => {
    const errs = validateInput("%Digit excluding ('1' * 2)");
    expect(hasError(errs, { kind: "invalidExclusionOperand" })).toBe(true);
  });

  it("invalid exclusion nested group", () => {
    const errs = validateInput("%Digit excluding (('1'))");
    expect(hasError(errs, { kind: "invalidExclusionOperand" })).toBe(true);
  });

  it("invalid exclusion interpolation operand multi-item sequence", () => {
    const errs = validateInput("d = 'a' 'b'; %Alpha excluding {d}");
    expect(hasError(errs, { kind: "invalidExclusionOperand" })).toBe(true);
  });

  it("invalid exclusion group with interpolation", () => {
    const errs = validateInput("d = '1'; %Digit excluding ({d})");
    expect(hasError(errs, { kind: "invalidExclusionOperand" })).toBe(true);
  });
});

// ---------------------------------------------------------------------------
// Annotation errors
// ---------------------------------------------------------------------------

describe("unknownAnnotation / duplicateAnnotation", () => {
  it("unknown annotation typo", () => {
    expect(validateInput("!typo = true\n'x'")).toEqual([{ kind: "unknownAnnotation", name: "typo" }]);
  });

  it("replacements-ignore-matching annotation accepted", () => {
    expect(validateInput("!replacements-ignore-matching = true\n'x'")).toEqual([]);
  });

  it("duplicate annotation", () => {
    expect(validateInput("!case-insensitive = true\n!case-insensitive = false\n'x'")).toEqual([
      { kind: "duplicateAnnotation", name: "case-insensitive" },
    ]);
  });
});

// ---------------------------------------------------------------------------
// Capture inside repetition
// ---------------------------------------------------------------------------

describe("capture in repetition (always allowed)", () => {
  it("capture inside repetition is valid", () => {
    expect(validateInput("(%Digit as d) * 3")).toEqual([]);
  });

  it("capture outside repetition is valid", () => {
    expect(validateInput("%Digit * 3 as d")).toEqual([]);
  });

  it("nested capture inside repetition", () => {
    expect(validateInput("(('a' as inner) * 2) * 3")).toEqual([]);
  });
});

// ---------------------------------------------------------------------------
// Position assertions
// ---------------------------------------------------------------------------

describe("position assertions", () => {
  it("valid @word-start", () => {
    expect(validateInput("@word-start %Alpha * 1..?")).toEqual([]);
  });

  it("valid @word-end", () => {
    expect(validateInput("%Alpha * 1..? @word-end")).toEqual([]);
  });

  it("valid @line-start", () => {
    expect(validateInput("@line-start %Digit * 1..?")).toEqual([]);
  });

  it("valid @line-end", () => {
    expect(validateInput("%Digit * 1..? @line-end")).toEqual([]);
  });

  it("unknown position assertion", () => {
    const errs = validateInput("@start-of-line 'x'");
    expect(hasError(errs, { kind: "unknownPositionAssertion", name: "start-of-line" })).toBe(true);
  });

  it("position assertion in repetition", () => {
    const errs = validateInput("@word-start * 3");
    expect(hasError(errs, { kind: "positionAssertionInRepetition", name: "word-start" })).toBe(true);
  });

  it("position assertion with exact count 1", () => {
    const errs = validateInput("@line-end * 1");
    expect(hasError(errs, { kind: "positionAssertionInRepetition", name: "line-end" })).toBe(true);
  });

  it("multiline annotation valid", () => {
    expect(validateInput("!multiline = true\n'x'")).toEqual([]);
  });
});

// ---------------------------------------------------------------------------
// !substitutable
// ---------------------------------------------------------------------------

describe("!substitutable", () => {
  it("substitutable with literal is valid", () => {
    expect(validateInput("!substitutable = true\n'hello'")).toEqual([]);
  });

  it("substitutable with named capture of class is valid", () => {
    expect(validateInput("!substitutable = true\n%Digit * 4 as year")).toEqual([]);
  });

  it("substitutable bare charclass is invalid", () => {
    const errs = validateInput("!substitutable = true\n%Digit");
    expect(hasError(errs, { kind: "notSubstitutableBody" })).toBe(true);
  });

  it("substitutable bare char range is invalid", () => {
    const errs = validateInput("!substitutable = true\n'a'..'z'");
    expect(hasError(errs, { kind: "notSubstitutableBody" })).toBe(true);
  });

  it("substitutable group of literal is valid", () => {
    expect(validateInput("!substitutable = true\n('hello')")).toEqual([]);
  });

  it("substitutable alternation all literals is valid", () => {
    expect(validateInput("!substitutable = true\n'foo' | 'bar'")).toEqual([]);
  });

  it("substitutable alternation mixed is invalid", () => {
    const errs = validateInput("!substitutable = true\n'foo' | %Digit");
    expect(hasError(errs, { kind: "notSubstitutableBody" })).toBe(true);
  });

  it("substitutable sequence all literals is valid", () => {
    expect(validateInput("!substitutable = true\n'hello' ' ' 'world'")).toEqual([]);
  });

  it("substitutable sequence mixed is invalid", () => {
    const errs = validateInput("!substitutable = true\n'hello' %Digit");
    expect(hasError(errs, { kind: "notSubstitutableBody" })).toBe(true);
  });

  it("substitutable fixed rep of literal is valid", () => {
    expect(validateInput("!substitutable = true\n'x' * 3")).toEqual([]);
  });

  it("substitutable bounded rep with capture is valid", () => {
    expect(validateInput("!substitutable = true\n%Digit * 1..4 as d")).toEqual([]);
  });

  it("substitutable bounded rep without capture is invalid", () => {
    const errs = validateInput("!substitutable = true\n%Digit * 1..4");
    expect(hasError(errs, { kind: "boundedRepetitionNeedsCapture" })).toBe(true);
  });

  it("substitutable bounded rep in group with capture is valid", () => {
    expect(validateInput("!substitutable = true\n(',' %Digit * 1..4 as d) * 0..10")).toEqual([]);
  });

  it("substitutable capture in repetition allowed", () => {
    expect(validateInput("!substitutable = true\n%Digit * 4 as n")).toEqual([]);
  });

  it("substitutable interpolation of literal def is valid", () => {
    expect(validateInput("!substitutable = true\nword = 'hello';\n{word}")).toEqual([]);
  });

  it("substitutable interpolation of class def is invalid", () => {
    const errs = validateInput("!substitutable = true\ndigits = %Digit * 4;\n{digits}");
    expect(hasError(errs, { kind: "notSubstitutableBody" })).toBe(true);
  });

  it("substitutable interpolation with outer capture is valid", () => {
    expect(validateInput("!substitutable = true\ndigits = %Digit * 4;\n{digits} as year")).toEqual([]);
  });
});

// ---------------------------------------------------------------------------
// !substitutions-ignore-matching
// ---------------------------------------------------------------------------

describe("substitutionsIgnoreMatchingWithoutSubstitutable", () => {
  it("substitutions-ignore-matching without substitutable is error", () => {
    const errs = validateInput("!substitutions-ignore-matching = true\n'hello'");
    expect(hasError(errs, { kind: "substitutionsIgnoreMatchingWithoutSubstitutable" })).toBe(true);
  });

  it("substitutions-ignore-matching with substitutable is valid", () => {
    expect(validateInput("!substitutable = true\n!substitutions-ignore-matching = true\n'hello'")).toEqual([]);
  });

  it("substitutions-ignore-matching false without substitutable is valid", () => {
    expect(validateInput("!substitutions-ignore-matching = false\n'hello'")).toEqual([]);
  });

  it("capture in repetition allowed without substitutable", () => {
    expect(validateInput("(%Digit as d) * 3")).toEqual([]);
  });
});

// ---------------------------------------------------------------------------
// Fewest on exact-count repetition
// ---------------------------------------------------------------------------

describe("fewestOnExactRepetition", () => {
  it("fewest on exact count 3 is error", () => {
    expect(validateInput("%Any * 3 fewest")).toEqual([{ kind: "fewestOnExactRepetition" }]);
  });

  it("fewest on exact count 1 is error", () => {
    expect(validateInput("'x' * 1 fewest")).toEqual([{ kind: "fewestOnExactRepetition" }]);
  });

  it("fewest on unbounded is valid", () => {
    expect(validateInput("%Any * 1..? fewest")).toEqual([]);
  });

  it("fewest on zero-unbounded is valid", () => {
    expect(validateInput("%Any * 0..? fewest")).toEqual([]);
  });

  it("fewest on bounded range is valid", () => {
    expect(validateInput("%Any * 3..10 fewest")).toEqual([]);
  });

  it("fewest on optional is valid", () => {
    expect(validateInput("%Any * 0..1 fewest")).toEqual([]);
  });
});
