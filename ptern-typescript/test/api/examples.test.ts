// Tests exercising the example pterns from the user guide / examples table.
import { describe, expect, it } from "bun:test";
import { compile } from "../../src/index";

function compileSrc(src: string) {
  return compile(src);
}

// ---------------------------------------------------------------------------
// ISO date YYYY-MM-DD
// ---------------------------------------------------------------------------

const isoDateSrc = `
  yyyy = %Digit * 4;
  mm = '0' '1'..'9' | '1' '0'..'2';
  dd = '0' '1'..'9' | '1'..'2' %Digit | '3' '0'..'1';
  {yyyy} as year '-' {mm} as month '-' {dd} as day
`;

describe("ISO date YYYY-MM-DD", () => {
  it("valid dates", () => {
    const p = compileSrc(isoDateSrc);
    expect(p.matchesAllOf("2026-07-04")).toBe(true);
    expect(p.matchesAllOf("2000-01-01")).toBe(true);
    expect(p.matchesAllOf("1999-12-31")).toBe(true);
  });

  it("invalid dates", () => {
    const p = compileSrc(isoDateSrc);
    expect(p.matchesAllOf("2026-7-4")).toBe(false);
    expect(p.matchesAllOf("2026-13-01")).toBe(false);
    expect(p.matchesAllOf("2026-00-15")).toBe(false);
    expect(p.matchesAllOf("2026-07-32")).toBe(false);
    expect(p.matchesAllOf("26-07-04")).toBe(false);
    expect(p.matchesAllOf("2026/07/04")).toBe(false);
  });

  it("captures year, month, day", () => {
    const p = compileSrc(isoDateSrc);
    const m = p.matchAllOf("2026-07-04");
    expect(m).not.toBeNull();
    expect(m!.captures["year"]).toBe("2026");
    expect(m!.captures["month"]).toBe("07");
    expect(m!.captures["day"]).toBe("04");
  });

  it("found in text with correct index", () => {
    const p = compileSrc(isoDateSrc);
    expect(p.matchesIn("Independence Day 2026-07-04 - the 250th")).toBe(true);
    const m = p.matchFirstIn("event on 2026-07-04 at noon");
    expect(m).not.toBeNull();
    expect(m!.index).toBe(9);
    expect(m!.length).toBe(10);
  });

  it("length bounds", () => {
    const p = compileSrc(isoDateSrc);
    expect(p.minLength()).toBe(10);
    expect(p.maxLength()).toBe(10);
  });
});

// ---------------------------------------------------------------------------
// US date MM/DD/YYYY
// ---------------------------------------------------------------------------

const usDateSrc = `
  mm = '0' '1'..'9' | '1' '0'..'2';
  dd = '0' '1'..'9' | '1'..'2' %Digit | '3' '0'..'1';
  {mm} '/' {dd} '/' %Digit * 4
`;

describe("US date MM/DD/YYYY", () => {
  it("valid dates", () => {
    const p = compileSrc(usDateSrc);
    expect(p.matchesAllOf("07/04/2026")).toBe(true);
    expect(p.matchesAllOf("01/01/2000")).toBe(true);
    expect(p.matchesAllOf("12/31/1999")).toBe(true);
  });

  it("invalid dates", () => {
    const p = compileSrc(usDateSrc);
    expect(p.matchesAllOf("7/4/2026")).toBe(false);
    expect(p.matchesAllOf("13/04/2026")).toBe(false);
    expect(p.matchesAllOf("07-04-2026")).toBe(false);
  });
});

// ---------------------------------------------------------------------------
// 24-hour time HH:MM[:SS]
// ---------------------------------------------------------------------------

const time24Src = `
  hr = '0'..'1' %Digit | '2' '0'..'3';
  ms = '0'..'5' %Digit;
  {hr} ':' {ms} (':' {ms}) * 0..1
`;

describe("24-hour time HH:MM[:SS]", () => {
  it("valid times", () => {
    const p = compileSrc(time24Src);
    expect(p.matchesAllOf("00:00")).toBe(true);
    expect(p.matchesAllOf("23:59")).toBe(true);
    expect(p.matchesAllOf("12:30")).toBe(true);
    expect(p.matchesAllOf("09:05:00")).toBe(true);
    expect(p.matchesAllOf("23:59:59")).toBe(true);
  });

  it("invalid times", () => {
    const p = compileSrc(time24Src);
    expect(p.matchesAllOf("24:00")).toBe(false);
    expect(p.matchesAllOf("12:60")).toBe(false);
    expect(p.matchesAllOf("9:00")).toBe(false);
    expect(p.matchesAllOf("12:30:60")).toBe(false);
  });
});

// ---------------------------------------------------------------------------
// 12-hour time with AM/PM
// ---------------------------------------------------------------------------

const time12Src = `
  hr = '1' '0'..'2' | ('0') * 0..1 '1'..'9';
  ms = '0'..'5' %Digit;
  {hr} ':' {ms} %Space * 0..1 ('A' | 'P') 'M'
`;

describe("12-hour time with AM/PM", () => {
  it("valid times", () => {
    const p = compileSrc(time12Src);
    expect(p.matchesAllOf("12:00AM")).toBe(true);
    expect(p.matchesAllOf("1:30PM")).toBe(true);
    expect(p.matchesAllOf("01:00AM")).toBe(true);
    expect(p.matchesAllOf("11:59 PM")).toBe(true);
  });

  it("invalid times", () => {
    const p = compileSrc(time12Src);
    expect(p.matchesAllOf("13:00PM")).toBe(false);
    expect(p.matchesAllOf("0:00AM")).toBe(false);
    expect(p.matchesAllOf("12:60AM")).toBe(false);
    expect(p.matchesAllOf("12:00XM")).toBe(false);
  });
});

// ---------------------------------------------------------------------------
// Floating-point number
// ---------------------------------------------------------------------------

const floatSrc = `
  !case-insensitive = true
  digits = %Digit * 1..20;
  exp = 'e' ('+' | '-') * 0..1 {digits} as exponent;
  ('+' | '-') * 0..1 {digits} as integer ('.' {digits}) * 0..1 {exp} * 0..1
`;

describe("floating-point number", () => {
  it("valid floats", () => {
    const p = compileSrc(floatSrc);
    expect(p.matchesAllOf("42")).toBe(true);
    expect(p.matchesAllOf("3.14")).toBe(true);
    expect(p.matchesAllOf("-2.5")).toBe(true);
    expect(p.matchesAllOf("+1.0")).toBe(true);
    expect(p.matchesAllOf("1e10")).toBe(true);
    expect(p.matchesAllOf("1.5E-3")).toBe(true);
    expect(p.matchesAllOf("2.998e+8")).toBe(true);
  });

  it("invalid floats", () => {
    const p = compileSrc(floatSrc);
    expect(p.matchesAllOf(".5")).toBe(false);
    expect(p.matchesAllOf("1.")).toBe(false);
    expect(p.matchesAllOf("1e")).toBe(false);
    expect(p.matchesAllOf("")).toBe(false);
  });

  it("captures integer", () => {
    const p = compileSrc(floatSrc);
    const m = p.matchAllOf("3.14");
    expect(m).not.toBeNull();
    expect(m!.captures["integer"]).toBe("3");
  });

  it("captures exponent", () => {
    const p = compileSrc(floatSrc);
    const m = p.matchAllOf("1e10");
    expect(m).not.toBeNull();
    expect(m!.captures["integer"]).toBe("1");
    expect(m!.captures["exponent"]).toBe("10");
  });
});

// ---------------------------------------------------------------------------
// Decimal, up to 2 decimal places
// ---------------------------------------------------------------------------

describe("decimal up to 2dp", () => {
  it("valid decimals", () => {
    const p = compileSrc("%Digit * 1..? ('.' %Digit * 1..2) * 0..1");
    expect(p.matchesAllOf("0")).toBe(true);
    expect(p.matchesAllOf("42")).toBe(true);
    expect(p.matchesAllOf("3.1")).toBe(true);
    expect(p.matchesAllOf("9.99")).toBe(true);
    expect(p.matchesAllOf("100")).toBe(true);
  });

  it("invalid decimals", () => {
    const p = compileSrc("%Digit * 1..? ('.' %Digit * 1..2) * 0..1");
    expect(p.matchesAllOf("3.141")).toBe(false);
    expect(p.matchesAllOf(".5")).toBe(false);
    expect(p.matchesAllOf("1.")).toBe(false);
    expect(p.matchesAllOf("abc")).toBe(false);
  });
});

// ---------------------------------------------------------------------------
// Hexadecimal integer literal
// ---------------------------------------------------------------------------

const hexSrc = `
  !case-insensitive = true
  '0x' %Xdigit * 1..16 as value
`;

describe("hexadecimal literal", () => {
  it("valid hex", () => {
    const p = compileSrc(hexSrc);
    expect(p.matchesAllOf("0x0")).toBe(true);
    expect(p.matchesAllOf("0xFF")).toBe(true);
    expect(p.matchesAllOf("0xDEADBEEF")).toBe(true);
    expect(p.matchesAllOf("0x1a2b3c4d")).toBe(true);
    expect(p.matchesAllOf("0XFF")).toBe(true);
  });

  it("invalid hex", () => {
    const p = compileSrc(hexSrc);
    expect(p.matchesAllOf("0x")).toBe(false);
    expect(p.matchesAllOf("FF")).toBe(false);
    expect(p.matchesAllOf("0xGG")).toBe(false);
    expect(p.matchesAllOf("0x" + "0123456789abcdef0")).toBe(false);
  });

  it("captures hex value", () => {
    const p = compileSrc(hexSrc);
    const m = p.matchAllOf("0xDEAD");
    expect(m).not.toBeNull();
    expect(m!.captures["value"]).toBe("DEAD");
  });
});

// ---------------------------------------------------------------------------
// Octal integer literal
// ---------------------------------------------------------------------------

describe("octal literal", () => {
  it("valid octal", () => {
    const p = compileSrc("'0' '0'..'7' * 1..?");
    expect(p.matchesAllOf("00")).toBe(true);
    expect(p.matchesAllOf("07")).toBe(true);
    expect(p.matchesAllOf("0755")).toBe(true);
    expect(p.matchesAllOf("01234567")).toBe(true);
  });

  it("invalid octal", () => {
    const p = compileSrc("'0' '0'..'7' * 1..?");
    expect(p.matchesAllOf("0")).toBe(false);
    expect(p.matchesAllOf("08")).toBe(false);
    expect(p.matchesAllOf("0x7")).toBe(false);
    expect(p.matchesAllOf("755")).toBe(false);
  });
});

// ---------------------------------------------------------------------------
// Binary integer literal
// ---------------------------------------------------------------------------

describe("binary literal", () => {
  it("valid binary", () => {
    const p = compileSrc("'0b' ('0' | '1') * 1..?");
    expect(p.matchesAllOf("0b0")).toBe(true);
    expect(p.matchesAllOf("0b1")).toBe(true);
    expect(p.matchesAllOf("0b1010")).toBe(true);
    expect(p.matchesAllOf("0b11111111")).toBe(true);
  });

  it("invalid binary", () => {
    const p = compileSrc("'0b' ('0' | '1') * 1..?");
    expect(p.matchesAllOf("0b")).toBe(false);
    expect(p.matchesAllOf("0b2")).toBe(false);
    expect(p.matchesAllOf("1010")).toBe(false);
    expect(p.matchesAllOf("0x1010")).toBe(false);
  });
});

// ---------------------------------------------------------------------------
// Semantic version
// ---------------------------------------------------------------------------

const semverSrc = `
  num = %Digit * 1..10;
  {num} as major '.' {num} as minor '.' {num} as patch
`;

describe("semantic version", () => {
  it("valid semver", () => {
    const p = compileSrc(semverSrc);
    expect(p.matchesAllOf("1.0.0")).toBe(true);
    expect(p.matchesAllOf("2.14.3")).toBe(true);
    expect(p.matchesAllOf("0.0.1")).toBe(true);
    expect(p.matchesAllOf("10.20.30")).toBe(true);
  });

  it("invalid semver", () => {
    const p = compileSrc(semverSrc);
    expect(p.matchesAllOf("1.0")).toBe(false);
    expect(p.matchesAllOf("1.0.0.0")).toBe(false);
    expect(p.matchesAllOf("v1.0.0")).toBe(false);
    expect(p.matchesAllOf("1.0.")).toBe(false);
  });

  it("captures major, minor, patch", () => {
    const p = compileSrc(semverSrc);
    const m = p.matchAllOf("2.14.3");
    expect(m).not.toBeNull();
    expect(m!.captures["major"]).toBe("2");
    expect(m!.captures["minor"]).toBe("14");
    expect(m!.captures["patch"]).toBe("3");
  });
});

// ---------------------------------------------------------------------------
// Unicode identifier, max 32 chars
// ---------------------------------------------------------------------------

describe("Unicode identifier max 32", () => {
  it("valid unicode idents", () => {
    const p = compileSrc("(%L | '_') (%L | %N | '_') * 0..31");
    expect(p.matchesAllOf("x")).toBe(true);
    expect(p.matchesAllOf("_foo")).toBe(true);
    expect(p.matchesAllOf("myVar123")).toBe(true);
  });

  it("invalid unicode idents", () => {
    const p = compileSrc("(%L | '_') (%L | %N | '_') * 0..31");
    expect(p.matchesAllOf("1abc")).toBe(false);
    expect(p.matchesAllOf("-name")).toBe(false);
    expect(p.matchesAllOf("")).toBe(false);
  });

  it("length boundary: 32 chars valid, 33 invalid", () => {
    const p = compileSrc("(%L | '_') (%L | %N | '_') * 0..31");
    const exactly32 = "a" + "b".repeat(31);
    const over32 = "a" + "b".repeat(32);
    expect(p.matchesAllOf(exactly32)).toBe(true);
    expect(p.matchesAllOf(over32)).toBe(false);
  });
});

// ---------------------------------------------------------------------------
// ASCII identifier
// ---------------------------------------------------------------------------

describe("ASCII identifier", () => {
  it("valid ASCII idents", () => {
    const p = compileSrc("%Alpha (%Alnum | '_') * 0..?");
    expect(p.matchesAllOf("x")).toBe(true);
    expect(p.matchesAllOf("foo_bar")).toBe(true);
    expect(p.matchesAllOf("CamelCase")).toBe(true);
    expect(p.matchesAllOf("a1b2c3")).toBe(true);
  });

  it("invalid ASCII idents", () => {
    const p = compileSrc("%Alpha (%Alnum | '_') * 0..?");
    expect(p.matchesAllOf("1abc")).toBe(false);
    expect(p.matchesAllOf("_foo")).toBe(false);
    expect(p.matchesAllOf("foo-bar")).toBe(false);
    expect(p.matchesAllOf("")).toBe(false);
  });
});

// ---------------------------------------------------------------------------
// Username
// ---------------------------------------------------------------------------

describe("username", () => {
  it("valid usernames", () => {
    const p = compileSrc("%Lower (%Lower | %Digit | '_' | '-') * 2..19");
    expect(p.matchesAllOf("abc")).toBe(true);
    expect(p.matchesAllOf("user_name")).toBe(true);
    expect(p.matchesAllOf("user-123")).toBe(true);
  });

  it("invalid usernames", () => {
    const p = compileSrc("%Lower (%Lower | %Digit | '_' | '-') * 2..19");
    expect(p.matchesAllOf("ab")).toBe(false);
    expect(p.matchesAllOf("ABC")).toBe(false);
    expect(p.matchesAllOf("1user")).toBe(false);
  });

  it("length boundaries", () => {
    const p = compileSrc("%Lower (%Lower | %Digit | '_' | '-') * 2..19");
    const exactly3 = "abc";
    const exactly20 = "a" + "b".repeat(19);
    const over20 = "a" + "b".repeat(20);
    expect(p.matchesAllOf(exactly3)).toBe(true);
    expect(p.matchesAllOf(exactly20)).toBe(true);
    expect(p.matchesAllOf(over20)).toBe(false);
  });
});

// ---------------------------------------------------------------------------
// PascalCase identifier
// ---------------------------------------------------------------------------

describe("PascalCase identifier", () => {
  it("valid PascalCase", () => {
    const p = compileSrc("%Upper %Lower * 1..? (%Upper %Lower * 1..?) * 0..?");
    expect(p.matchesAllOf("Foo")).toBe(true);
    expect(p.matchesAllOf("FooBar")).toBe(true);
    expect(p.matchesAllOf("MyClassName")).toBe(true);
  });

  it("invalid PascalCase", () => {
    const p = compileSrc("%Upper %Lower * 1..? (%Upper %Lower * 1..?) * 0..?");
    expect(p.matchesAllOf("foo")).toBe(false);
    expect(p.matchesAllOf("FOO")).toBe(false);
    expect(p.matchesAllOf("fooBar")).toBe(false);
    expect(p.matchesAllOf("F")).toBe(false);
  });
});

// ---------------------------------------------------------------------------
// camelCase identifier
// ---------------------------------------------------------------------------

describe("camelCase identifier", () => {
  it("valid camelCase", () => {
    const p = compileSrc("%Lower * 1..? (%Upper %Lower * 1..?) * 0..?");
    expect(p.matchesAllOf("foo")).toBe(true);
    expect(p.matchesAllOf("fooBar")).toBe(true);
    expect(p.matchesAllOf("myVariableName")).toBe(true);
  });

  it("invalid camelCase", () => {
    const p = compileSrc("%Lower * 1..? (%Upper %Lower * 1..?) * 0..?");
    expect(p.matchesAllOf("FooBar")).toBe(false);
    expect(p.matchesAllOf("FOO")).toBe(false);
    expect(p.matchesAllOf("foo_bar")).toBe(false);
  });
});

// ---------------------------------------------------------------------------
// snake_case identifier
// ---------------------------------------------------------------------------

describe("snake_case identifier", () => {
  it("valid snake_case", () => {
    const p = compileSrc("%Lower * 1..? ('_' %Lower * 1..?) * 0..?");
    expect(p.matchesAllOf("foo")).toBe(true);
    expect(p.matchesAllOf("foo_bar")).toBe(true);
    expect(p.matchesAllOf("my_var_name")).toBe(true);
  });

  it("invalid snake_case", () => {
    const p = compileSrc("%Lower * 1..? ('_' %Lower * 1..?) * 0..?");
    expect(p.matchesAllOf("FooBar")).toBe(false);
    expect(p.matchesAllOf("_foo")).toBe(false);
    expect(p.matchesAllOf("foo_")).toBe(false);
    expect(p.matchesAllOf("foo__bar")).toBe(false);
  });
});

// ---------------------------------------------------------------------------
// Boolean keyword
// ---------------------------------------------------------------------------

describe("boolean keyword", () => {
  it("valid booleans", () => {
    const p = compileSrc("'true' | 'false'");
    expect(p.matchesAllOf("true")).toBe(true);
    expect(p.matchesAllOf("false")).toBe(true);
  });

  it("invalid booleans", () => {
    const p = compileSrc("'true' | 'false'");
    expect(p.matchesAllOf("True")).toBe(false);
    expect(p.matchesAllOf("TRUE")).toBe(false);
    expect(p.matchesAllOf("yes")).toBe(false);
    expect(p.matchesAllOf("1")).toBe(false);
  });
});

// ---------------------------------------------------------------------------
// Null-like keyword
// ---------------------------------------------------------------------------

describe("null-like keyword", () => {
  it("valid null keywords", () => {
    const p = compileSrc("'null' | 'undefined' | 'nil' | 'None'");
    expect(p.matchesAllOf("null")).toBe(true);
    expect(p.matchesAllOf("undefined")).toBe(true);
    expect(p.matchesAllOf("nil")).toBe(true);
    expect(p.matchesAllOf("None")).toBe(true);
  });

  it("invalid null keywords", () => {
    const p = compileSrc("'null' | 'undefined' | 'nil' | 'None'");
    expect(p.matchesAllOf("Null")).toBe(false);
    expect(p.matchesAllOf("none")).toBe(false);
    expect(p.matchesAllOf("NULL")).toBe(false);
  });
});

// ---------------------------------------------------------------------------
// Email address
// ---------------------------------------------------------------------------

const emailSrc = `
  lc = %Alnum | '.' | '_' | '%' | '+' | '-';
  dc = %Alnum | '.' | '-';
  {lc} * 1..? '@' {dc} * 1..? '.' %Alpha * 2..?
`;

describe("email address", () => {
  it("valid emails", () => {
    const p = compileSrc(emailSrc);
    expect(p.matchesAllOf("user@example.com")).toBe(true);
    expect(p.matchesAllOf("first.last@sub.domain.org")).toBe(true);
    expect(p.matchesAllOf("user+tag@example.co.uk")).toBe(true);
    expect(p.matchesAllOf("a@b.io")).toBe(true);
  });

  it("invalid emails", () => {
    const p = compileSrc(emailSrc);
    expect(p.matchesAllOf("notanemail")).toBe(false);
    expect(p.matchesAllOf("@example.com")).toBe(false);
    expect(p.matchesAllOf("user@")).toBe(false);
    expect(p.matchesAllOf("user@example")).toBe(false);
  });
});

// ---------------------------------------------------------------------------
// IPv4 address (octets not range-checked)
// ---------------------------------------------------------------------------

const ipv4SimpleSrc = `
  oct = %Digit * 1..3;
  ({oct} '.') * 3 {oct}
`;

describe("IPv4 address (simple)", () => {
  it("valid IPv4", () => {
    const p = compileSrc(ipv4SimpleSrc);
    expect(p.matchesAllOf("192.168.1.1")).toBe(true);
    expect(p.matchesAllOf("0.0.0.0")).toBe(true);
    expect(p.matchesAllOf("255.255.255.255")).toBe(true);
    expect(p.matchesAllOf("10.0.0.1")).toBe(true);
  });

  it("invalid IPv4", () => {
    const p = compileSrc(ipv4SimpleSrc);
    expect(p.matchesAllOf("192.168.1")).toBe(false);
    expect(p.matchesAllOf("192.168.1.1.1")).toBe(false);
    expect(p.matchesAllOf("192.168.1.abc")).toBe(false);
    expect(p.matchesAllOf("1.2.3.4444")).toBe(false);
  });
});

// ---------------------------------------------------------------------------
// IPv4 address (strictly 0–255)
// ---------------------------------------------------------------------------

const ipv4StrictSrc = `
  octet = %Digit
        | '1'..'9' %Digit
        | '1' %Digit %Digit
        | '2' '0'..'4' %Digit
        | '2' '5' '0'..'5';
  {octet} as a '.' {octet} as b '.' {octet} as c '.' {octet} as d
`;

describe("IPv4 address (strict 0-255)", () => {
  it("valid strict IPv4", () => {
    const p = compileSrc(ipv4StrictSrc);
    expect(p.matchesAllOf("0.0.0.0")).toBe(true);
    expect(p.matchesAllOf("255.255.255.255")).toBe(true);
    expect(p.matchesAllOf("192.168.0.1")).toBe(true);
    expect(p.matchesAllOf("10.0.0.254")).toBe(true);
  });

  it("out-of-range octets rejected", () => {
    const p = compileSrc(ipv4StrictSrc);
    expect(p.matchesAllOf("256.0.0.1")).toBe(false);
    expect(p.matchesAllOf("192.168.0.300")).toBe(false);
    expect(p.matchesAllOf("999.999.999.999")).toBe(false);
  });

  it("captures a, b, c, d", () => {
    const p = compileSrc(ipv4StrictSrc);
    const m = p.matchAllOf("192.168.0.1");
    expect(m).not.toBeNull();
    expect(m!.captures["a"]).toBe("192");
    expect(m!.captures["b"]).toBe("168");
    expect(m!.captures["c"]).toBe("0");
    expect(m!.captures["d"]).toBe("1");
  });
});

// ---------------------------------------------------------------------------
// E.164 international phone
// ---------------------------------------------------------------------------

describe("E.164 phone number", () => {
  it("valid E.164", () => {
    const p = compileSrc("('+') * 0..1 '1'..'9' %Digit * 1..14");
    expect(p.matchesAllOf("12125551234")).toBe(true);
    expect(p.matchesAllOf("+12125551234")).toBe(true);
    expect(p.matchesAllOf("+442071838750")).toBe(true);
    expect(p.matchesAllOf("1")).toBe(false);
  });

  it("invalid E.164", () => {
    const p = compileSrc("('+') * 0..1 '1'..'9' %Digit * 1..14");
    expect(p.matchesAllOf("0123456789")).toBe(false);
    expect(p.matchesAllOf("+")).toBe(false);
    expect(p.matchesAllOf("++12125551234")).toBe(false);
  });
});

// ---------------------------------------------------------------------------
// US ZIP code (optional +4)
// ---------------------------------------------------------------------------

describe("US ZIP code", () => {
  it("valid ZIP codes", () => {
    const p = compileSrc("%Digit * 5 ('-' %Digit * 4) * 0..1");
    expect(p.matchesAllOf("90210")).toBe(true);
    expect(p.matchesAllOf("10001")).toBe(true);
    expect(p.matchesAllOf("90210-1234")).toBe(true);
  });

  it("invalid ZIP codes", () => {
    const p = compileSrc("%Digit * 5 ('-' %Digit * 4) * 0..1");
    expect(p.matchesAllOf("9021")).toBe(false);
    expect(p.matchesAllOf("902100")).toBe(false);
    expect(p.matchesAllOf("90210-123")).toBe(false);
    expect(p.matchesAllOf("90210-12345")).toBe(false);
  });

  it("length bounds", () => {
    const p = compileSrc("%Digit * 5 ('-' %Digit * 4) * 0..1");
    expect(p.minLength()).toBe(5);
    expect(p.maxLength()).toBe(10);
  });
});

// ---------------------------------------------------------------------------
// UK postcode
// ---------------------------------------------------------------------------

describe("UK postcode", () => {
  it("valid UK postcodes", () => {
    const p = compileSrc("%Upper * 1..2 %Digit (%Upper | %Digit) * 0..1 %Space * 0..1 %Digit %Upper * 2");
    expect(p.matchesAllOf("SW1A1AA")).toBe(true);
    expect(p.matchesAllOf("SW1A 1AA")).toBe(true);
    expect(p.matchesAllOf("M11AE")).toBe(true);
    expect(p.matchesAllOf("EC1A1BB")).toBe(true);
  });

  it("invalid UK postcodes", () => {
    const p = compileSrc("%Upper * 1..2 %Digit (%Upper | %Digit) * 0..1 %Space * 0..1 %Digit %Upper * 2");
    expect(p.matchesAllOf("12345")).toBe(false);
    expect(p.matchesAllOf("sw1a1aa")).toBe(false);
  });
});

// ---------------------------------------------------------------------------
// UUID / GUID
// ---------------------------------------------------------------------------

describe("UUID", () => {
  it("valid UUIDs", () => {
    const p = compileSrc("%Xdigit * 8 '-' (%Xdigit * 4 '-') * 3 %Xdigit * 12");
    expect(p.matchesAllOf("550e8400-e29b-41d4-a716-446655440000")).toBe(true);
    expect(p.matchesAllOf("00000000-0000-0000-0000-000000000000")).toBe(true);
    expect(p.matchesAllOf("ffffffff-ffff-ffff-ffff-ffffffffffff")).toBe(true);
  });

  it("invalid UUIDs", () => {
    const p = compileSrc("%Xdigit * 8 '-' (%Xdigit * 4 '-') * 3 %Xdigit * 12");
    expect(p.matchesAllOf("550e8400-e29b-41d4-a716-44665544000")).toBe(false);
    expect(p.matchesAllOf("550e8400e29b41d4a716446655440000")).toBe(false);
    expect(p.matchesAllOf("gggggggg-gggg-gggg-gggg-gggggggggggg")).toBe(false);
  });

  it("length bounds", () => {
    const p = compileSrc("%Xdigit * 8 '-' (%Xdigit * 4 '-') * 3 %Xdigit * 12");
    expect(p.minLength()).toBe(36);
    expect(p.maxLength()).toBe(36);
  });
});

// ---------------------------------------------------------------------------
// US Social Security Number
// ---------------------------------------------------------------------------

describe("US SSN", () => {
  it("valid SSNs", () => {
    const p = compileSrc("%Digit * 3 '-' %Digit * 2 '-' %Digit * 4");
    expect(p.matchesAllOf("123-45-6789")).toBe(true);
    expect(p.matchesAllOf("000-00-0000")).toBe(true);
  });

  it("invalid SSNs", () => {
    const p = compileSrc("%Digit * 3 '-' %Digit * 2 '-' %Digit * 4");
    expect(p.matchesAllOf("123456789")).toBe(false);
    expect(p.matchesAllOf("12-345-6789")).toBe(false);
    expect(p.matchesAllOf("abc-de-fghi")).toBe(false);
  });

  it("length bounds", () => {
    const p = compileSrc("%Digit * 3 '-' %Digit * 2 '-' %Digit * 4");
    expect(p.minLength()).toBe(11);
    expect(p.maxLength()).toBe(11);
  });
});

// ---------------------------------------------------------------------------
// Visa card number
// ---------------------------------------------------------------------------

describe("Visa card number", () => {
  it("valid Visa", () => {
    const p = compileSrc("'4' %Digit * 12 (%Digit * 3) * 0..1");
    expect(p.matchesAllOf("4111111111111")).toBe(true);
    expect(p.matchesAllOf("4111111111111111")).toBe(true);
  });

  it("invalid Visa", () => {
    const p = compileSrc("'4' %Digit * 12 (%Digit * 3) * 0..1");
    expect(p.matchesAllOf("5111111111111")).toBe(false);
    expect(p.matchesAllOf("411111111111")).toBe(false);
    expect(p.matchesAllOf("41111111111111")).toBe(false);
  });
});

// ---------------------------------------------------------------------------
// Mastercard number
// ---------------------------------------------------------------------------

describe("Mastercard number", () => {
  it("valid Mastercard", () => {
    const p = compileSrc("'5' '1'..'5' %Digit * 14");
    expect(p.matchesAllOf("5111111111111118")).toBe(true);
    expect(p.matchesAllOf("5500000000000004")).toBe(true);
  });

  it("invalid Mastercard", () => {
    const p = compileSrc("'5' '1'..'5' %Digit * 14");
    expect(p.matchesAllOf("5011111111111117")).toBe(false);
    expect(p.matchesAllOf("5611111111111117")).toBe(false);
    expect(p.matchesAllOf("4111111111111111")).toBe(false);
  });
});

// ---------------------------------------------------------------------------
// Credit card — four groups of four digits
// ---------------------------------------------------------------------------

const ccGroupsSrc = `
  group = %Digit * 4;
  {group} ' ' {group} ' ' {group} ' ' {group}
`;

describe("CC four groups", () => {
  it("valid CC groups", () => {
    const p = compileSrc(ccGroupsSrc);
    expect(p.matchesAllOf("4111 1111 1111 1111")).toBe(true);
    expect(p.matchesAllOf("0000 0000 0000 0000")).toBe(true);
  });

  it("invalid CC groups", () => {
    const p = compileSrc(ccGroupsSrc);
    expect(p.matchesAllOf("4111111111111111")).toBe(false);
    expect(p.matchesAllOf("4111 1111 1111 111")).toBe(false);
    expect(p.matchesAllOf("4111 1111 1111 11111")).toBe(false);
  });

  it("length bounds", () => {
    const p = compileSrc(ccGroupsSrc);
    expect(p.minLength()).toBe(19);
    expect(p.maxLength()).toBe(19);
  });
});

// ---------------------------------------------------------------------------
// SHA-1 / SHA-256 hashes
// ---------------------------------------------------------------------------

describe("SHA-1 hash", () => {
  it("valid SHA-1", () => {
    const p = compileSrc("%Xdigit * 40");
    expect(p.matchesAllOf("da39a3ee5e6b4b0d3255bfef95601890afd80709")).toBe(true);
    expect(p.matchesAllOf("0000000000000000000000000000000000000000")).toBe(true);
  });

  it("invalid SHA-1", () => {
    const p = compileSrc("%Xdigit * 40");
    expect(p.matchesAllOf("da39a3ee5e6b4b0d3255bfef95601890afd8070")).toBe(false);
    expect(p.matchesAllOf("da39a3ee5e6b4b0d3255bfef95601890afd807090")).toBe(false);
    expect(p.matchesAllOf("zz39a3ee5e6b4b0d3255bfef95601890afd80709")).toBe(false);
  });
});

describe("SHA-256 hash", () => {
  it("valid SHA-256", () => {
    const p = compileSrc("%Xdigit * 64");
    const hash = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855";
    expect(p.matchesAllOf(hash)).toBe(true);
  });

  it("invalid SHA-256 (too short)", () => {
    const p = compileSrc("%Xdigit * 64");
    const short = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b85";
    expect(p.matchesAllOf(short)).toBe(false);
  });
});

// ---------------------------------------------------------------------------
// CSS hex color (#RGB or #RRGGBB)
// ---------------------------------------------------------------------------

const cssHexSrc = "'#' (%Xdigit * 6 | %Xdigit * 3)";

describe("CSS hex color", () => {
  it("valid #RRGGBB", () => {
    const p = compileSrc(cssHexSrc);
    expect(p.matchesAllOf("#ff0000")).toBe(true);
    expect(p.matchesAllOf("#000000")).toBe(true);
    expect(p.matchesAllOf("#1a2b3c")).toBe(true);
    expect(p.matchesAllOf("#FFFFFF")).toBe(true);
  });

  it("valid #RGB", () => {
    const p = compileSrc(cssHexSrc);
    expect(p.matchesAllOf("#f00")).toBe(true);
    expect(p.matchesAllOf("#000")).toBe(true);
    expect(p.matchesAllOf("#abc")).toBe(true);
  });

  it("invalid hex colors", () => {
    const p = compileSrc(cssHexSrc);
    expect(p.matchesAllOf("ff0000")).toBe(false);
    expect(p.matchesAllOf("#ff000")).toBe(false);
    expect(p.matchesAllOf("#ff00000")).toBe(false);
    expect(p.matchesAllOf("#gg0000")).toBe(false);
  });

  it("length bounds", () => {
    const p = compileSrc(cssHexSrc);
    expect(p.minLength()).toBe(4);
    expect(p.maxLength()).toBe(7);
  });
});

// ---------------------------------------------------------------------------
// CSS rgb() color
// ---------------------------------------------------------------------------

const cssRgbSrc =
  "'rgb(' %Space * 0..? %Digit * 1..3 ',' %Space * 0..? %Digit * 1..3 ',' %Space * 0..? %Digit * 1..3 %Space * 0..? ')'";

describe("CSS rgb() color", () => {
  it("valid rgb()", () => {
    const p = compileSrc(cssRgbSrc);
    expect(p.matchesAllOf("rgb(255,0,0)")).toBe(true);
    expect(p.matchesAllOf("rgb(0, 128, 255)")).toBe(true);
    expect(p.matchesAllOf("rgb( 0, 0, 0 )")).toBe(true);
  });

  it("invalid rgb()", () => {
    const p = compileSrc(cssRgbSrc);
    expect(p.matchesAllOf("rgb(1000,0,0)")).toBe(false);
    expect(p.matchesAllOf("rgb(255,0)")).toBe(false);
    expect(p.matchesAllOf("255,0,0")).toBe(false);
  });
});

// ---------------------------------------------------------------------------
// CSS length value
// ---------------------------------------------------------------------------

const cssLengthSrc =
  "%Digit * 1..? ('.' %Digit * 1..?) * 0..1 ('px' | 'em' | 'rem' | '%' | 'vh' | 'vw')";

describe("CSS length value", () => {
  it("valid lengths", () => {
    const p = compileSrc(cssLengthSrc);
    expect(p.matchesAllOf("16px")).toBe(true);
    expect(p.matchesAllOf("1.5em")).toBe(true);
    expect(p.matchesAllOf("2rem")).toBe(true);
    expect(p.matchesAllOf("100%")).toBe(true);
    expect(p.matchesAllOf("50vh")).toBe(true);
    expect(p.matchesAllOf("25vw")).toBe(true);
  });

  it("invalid lengths", () => {
    const p = compileSrc(cssLengthSrc);
    expect(p.matchesAllOf("16")).toBe(false);
    expect(p.matchesAllOf("px")).toBe(false);
    expect(p.matchesAllOf("16pt")).toBe(false);
    expect(p.matchesAllOf(".5em")).toBe(false);
  });
});

// ---------------------------------------------------------------------------
// C-style line comment
// ---------------------------------------------------------------------------

describe("C-style line comment", () => {
  it("valid line comments", () => {
    const p = compileSrc("'//' (%Any excluding '\\n') * 0..?");
    expect(p.matchesAllOf("// comment")).toBe(true);
    expect(p.matchesAllOf("//")).toBe(true);
    expect(p.matchesAllOf("// TODO: fix this")).toBe(true);
  });

  it("invalid line comments", () => {
    const p = compileSrc("'//' (%Any excluding '\\n') * 0..?");
    expect(p.matchesAllOf("/ comment")).toBe(false);
    expect(p.matchesAllOf("# comment")).toBe(false);
  });

  it("no newline in single-line comment", () => {
    const p = compileSrc("'//' (%Any excluding '\\n') * 0..?");
    expect(p.matchesAllOf("// line one\n// line two")).toBe(false);
    expect(p.matchesStartOf("// line one\n// line two")).toBe(true);
  });
});

// ---------------------------------------------------------------------------
// C-style block comment
// ---------------------------------------------------------------------------

describe("C-style block comment", () => {
  it("valid block comments", () => {
    const p = compileSrc("'/*' %Any * 0..? '*/'");
    expect(p.matchesAllOf("/* comment */")).toBe(true);
    expect(p.matchesAllOf("/**/")).toBe(true);
    expect(p.matchesAllOf("/* multi\nline */")).toBe(true);
  });

  it("invalid block comments", () => {
    const p = compileSrc("'/*' %Any * 0..? '*/'");
    expect(p.matchesAllOf("// not a block comment")).toBe(false);
    expect(p.matchesAllOf("/* unterminated")).toBe(false);
  });
});

// ---------------------------------------------------------------------------
// HTML comment
// ---------------------------------------------------------------------------

describe("HTML comment", () => {
  it("valid HTML comments", () => {
    const p = compileSrc("'<!--' %Any * 0..? '-->'");
    expect(p.matchesAllOf("<!-- comment -->")).toBe(true);
    expect(p.matchesAllOf("<!---->")).toBe(true);
    expect(p.matchesAllOf("<!-- multi\nline -->")).toBe(true);
  });

  it("invalid HTML comments", () => {
    const p = compileSrc("'<!--' %Any * 0..? '-->'");
    expect(p.matchesAllOf("// not html")).toBe(false);
    expect(p.matchesAllOf("<!-- unterminated")).toBe(false);
    expect(p.matchesAllOf("<! comment -->")).toBe(false);
  });
});

// ---------------------------------------------------------------------------
// Blank / whitespace-only line
// ---------------------------------------------------------------------------

describe("blank line", () => {
  it("valid blank lines", () => {
    const p = compileSrc("%Space * 0..?");
    expect(p.matchesAllOf("")).toBe(true);
    expect(p.matchesAllOf(" ")).toBe(true);
    expect(p.matchesAllOf("   ")).toBe(true);
    expect(p.matchesAllOf("\t")).toBe(true);
    expect(p.matchesAllOf(" \t ")).toBe(true);
  });

  it("invalid blank lines", () => {
    const p = compileSrc("%Space * 0..?");
    expect(p.matchesAllOf("a")).toBe(false);
    expect(p.matchesAllOf(" x ")).toBe(false);
  });
});

// ---------------------------------------------------------------------------
// Double-quoted string literal
// ---------------------------------------------------------------------------

const dqStringSrc = `
  !allow-backtracking = true
  char = %Any excluding '"';
  '"' ({char} | '\\"') * 0..1000 '"'
`;

describe("double-quoted string literal", () => {
  it("valid double-quoted strings", () => {
    const p = compileSrc(dqStringSrc);
    expect(p.matchesAllOf('"hello"')).toBe(true);
    expect(p.matchesAllOf('""')).toBe(true);
    expect(p.matchesAllOf('"say \\"hello\\""')).toBe(true);
  });

  it("invalid double-quoted strings", () => {
    const p = compileSrc(dqStringSrc);
    expect(p.matchesAllOf("hello")).toBe(false);
    expect(p.matchesAllOf('"unterminated')).toBe(false);
  });
});
