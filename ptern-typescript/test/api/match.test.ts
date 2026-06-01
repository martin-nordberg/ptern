import { describe, expect, it } from "bun:test";
import { compile } from "../../src/index";

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
});

describe("matchesStartOf", () => {
  it("matches at start", () => {
    const p = compile("'foo'");
    expect(p.matchesStartOf("foobar")).toBe(true);
  });

  it("does not match at non-start", () => {
    const p = compile("'foo'");
    expect(p.matchesStartOf("barfoo")).toBe(false);
  });
});

describe("matchesEndOf", () => {
  it("matches at end", () => {
    const p = compile("'bar'");
    expect(p.matchesEndOf("foobar")).toBe(true);
  });

  it("does not match at non-end", () => {
    const p = compile("'bar'");
    expect(p.matchesEndOf("barbaz")).toBe(false);
  });
});

describe("matchesIn", () => {
  it("finds match anywhere", () => {
    const p = compile("%Digit * 1..?");
    expect(p.matchesIn("abc123def")).toBe(true);
  });

  it("returns false when not found", () => {
    const p = compile("%Digit * 1..?");
    expect(p.matchesIn("abcdef")).toBe(false);
  });
});

describe("matchAllOf", () => {
  it("returns occurrence for full match", () => {
    const p = compile("%Digit * 4 as year");
    const m = p.matchAllOf("2024");
    expect(m).not.toBeNull();
    expect(m!.index).toBe(0);
    expect(m!.length).toBe(4);
    expect(m!.captures["year"]).toBe("2024");
  });

  it("returns null for no match", () => {
    const p = compile("%Digit * 4");
    expect(p.matchAllOf("abc")).toBeNull();
  });
});

describe("matchStartOf", () => {
  it("returns occurrence for start match", () => {
    const p = compile("%Digit * 1..? as num");
    const m = p.matchStartOf("123abc");
    expect(m).not.toBeNull();
    expect(m!.index).toBe(0);
    expect(m!.captures["num"]).toBe("123");
  });
});

describe("matchFirstIn", () => {
  it("returns first match", () => {
    const p = compile("%Digit * 1..? as n");
    const m = p.matchFirstIn("abc 42 def 99");
    expect(m).not.toBeNull();
    expect(m!.captures["n"]).toBe("42");
  });

  it("returns null when no match", () => {
    const p = compile("%Digit * 1..?");
    expect(p.matchFirstIn("abcdef")).toBeNull();
  });
});

describe("matchNextIn", () => {
  it("starts from given index", () => {
    const p = compile("%Digit * 1..? as n");
    const m = p.matchNextIn("abc 42 def 99", 7);
    expect(m).not.toBeNull();
    expect(m!.captures["n"]).toBe("99");
  });
});

describe("matchAllIn", () => {
  it("returns all matches", () => {
    const p = compile("%Digit * 1..? as n");
    const matches = p.matchAllIn("a1 b22 c333");
    expect(matches).toHaveLength(3);
    expect(matches[0]!.captures["n"]).toBe("1");
    expect(matches[1]!.captures["n"]).toBe("22");
    expect(matches[2]!.captures["n"]).toBe("333");
  });

  it("returns empty array for no match", () => {
    const p = compile("%Digit * 1..?");
    expect(p.matchAllIn("abcdef")).toHaveLength(0);
  });
});

describe("named captures", () => {
  it("iso date captures", () => {
    const p = compile(
      "yyyy = %Digit * 4;\n" +
      "mm = ('0' '1'..'9') | ('1' '0'..'2');\n" +
      "dd = ('0' '1'..'9') | ('1'..'2' %Digit) | ('3' '0'..'1');\n" +
      "{yyyy} as year '-' {mm} as month '-' {dd} as day",
    );
    const m = p.matchAllOf("2024-03-15");
    expect(m).not.toBeNull();
    expect(m!.captures["year"]).toBe("2024");
    expect(m!.captures["month"]).toBe("03");
    expect(m!.captures["day"]).toBe("15");
  });

  it("captures object has no __rep_ groups", () => {
    const p = compile("%Digit * 1..? as n");
    const m = p.matchFirstIn("123");
    expect(m).not.toBeNull();
    const keys = Object.keys(m!.captures);
    expect(keys.every(k => !k.startsWith("__rep_"))).toBe(true);
  });
});
