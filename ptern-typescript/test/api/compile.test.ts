import { describe, expect, it } from "bun:test";
import { compile, PternCompileError } from "../../src/index";

function compileOrThrow(source: string) {
  return compile(source);
}

describe("compile errors", () => {
  it("lex error throws PternCompileError", () => {
    expect(() => compile("@")).toThrow(PternCompileError);
  });

  it("lex error has kind lexError", () => {
    try {
      compile("@");
      expect(false).toBe(true);
    } catch (e) {
      expect(e instanceof PternCompileError).toBe(true);
      expect((e as PternCompileError).compileError.kind).toBe("lexError");
    }
  });

  it("parse error throws PternCompileError", () => {
    expect(() => compile("")).toThrow(PternCompileError);
  });

  it("parse error has kind parseError", () => {
    try {
      compile("");
      expect(false).toBe(true);
    } catch (e) {
      expect(e instanceof PternCompileError).toBe(true);
      expect((e as PternCompileError).compileError.kind).toBe("parseError");
    }
  });

  it("semantic error throws PternCompileError", () => {
    expect(() => compile("''")).toThrow(PternCompileError);
  });

  it("semantic error has kind semanticErrors", () => {
    try {
      compile("''");
      expect(false).toBe(true);
    } catch (e) {
      expect(e instanceof PternCompileError).toBe(true);
      expect((e as PternCompileError).compileError.kind).toBe("semanticErrors");
    }
  });

  it("unknown annotation throws", () => {
    expect(() => compile("!unknown = true\n'x'")).toThrow(PternCompileError);
  });
});

describe("compile success", () => {
  it("compiles a simple literal", () => {
    const p = compile("'hello'");
    expect(p).toBeDefined();
  });

  it("compiles character class", () => {
    const p = compile("%Digit * 4");
    expect(p).toBeDefined();
  });

  it("compiles with annotations", () => {
    const p = compile("!case-insensitive = true\n'hello'");
    expect(p).toBeDefined();
  });

  it("compiles with definitions", () => {
    const p = compile("d = %Digit;\n{d} * 4");
    expect(p).toBeDefined();
  });

  it("compiles iso date", () => {
    const p = compile(
      "yyyy = %Digit * 4;\n" +
      "mm = ('0' '1'..'9') | ('1' '0'..'2');\n" +
      "dd = ('0' '1'..'9') | ('1'..'2' %Digit) | ('3' '0'..'1');\n" +
      "{yyyy} as year '-' {mm} as month '-' {dd} as day",
    );
    expect(p).toBeDefined();
  });
});

describe("minLength / maxLength", () => {
  it("fixed literal has known bounds", () => {
    const p = compile("'hello'");
    expect(p.minLength()).toBe(5);
    expect(p.maxLength()).toBe(5);
  });

  it("unbounded repetition has null max", () => {
    const p = compile("%Digit * 1..?");
    expect(p.minLength()).toBe(1);
    expect(p.maxLength()).toBe(null);
  });

  it("bounded repetition", () => {
    const p = compile("%Digit * 2..5");
    expect(p.minLength()).toBe(2);
    expect(p.maxLength()).toBe(5);
  });

  it("optional group", () => {
    const p = compile("'a' ('b') * 0..1");
    expect(p.minLength()).toBe(1);
    expect(p.maxLength()).toBe(2);
  });
});
