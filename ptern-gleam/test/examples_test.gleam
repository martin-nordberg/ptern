// Tests exercising the example pterns from the README Examples table.
// Each section covers one pattern: valid inputs, invalid inputs, and where
// applicable captures and boundary cases.

import gleam/dict
import gleam/option.{None, Some}
import gleeunit/should
import ptern

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn compile(src: String) -> ptern.Ptern {
  let assert Ok(p) = ptern.compile(src)
  p
}

fn matches(src: String, input: String) -> Bool {
  ptern.matches_all_of(compile(src), input)
}

// ---------------------------------------------------------------------------
// ISO date YYYY-MM-DD
// ---------------------------------------------------------------------------

const iso_date_src = "
  yyyy = %Digit * 4;
  mm = '0' '1'..'9' | '1' '0'..'2';
  dd = '0' '1'..'9' | '1'..'2' %Digit | '3' '0'..'1';
  {yyyy} as year '-' {mm} as month '-' {dd} as day
"

pub fn iso_date_valid_test() {
  let p = compile(iso_date_src)
  ptern.matches_all_of(p, "2026-07-04") |> should.be_true
  ptern.matches_all_of(p, "2000-01-01") |> should.be_true
  ptern.matches_all_of(p, "1999-12-31") |> should.be_true
}

pub fn iso_date_invalid_test() {
  let p = compile(iso_date_src)
  ptern.matches_all_of(p, "2026-7-4") |> should.be_false
  ptern.matches_all_of(p, "2026-13-01") |> should.be_false
  ptern.matches_all_of(p, "2026-00-15") |> should.be_false
  ptern.matches_all_of(p, "2026-07-32") |> should.be_false
  ptern.matches_all_of(p, "26-07-04") |> should.be_false
  ptern.matches_all_of(p, "2026/07/04") |> should.be_false
}

pub fn iso_date_captures_test() {
  let p = compile(iso_date_src)
  let assert Some(occ) = ptern.match_all_of(p, "2026-07-04")
  dict.get(occ.captures, "year") |> should.equal(Ok("2026"))
  dict.get(occ.captures, "month") |> should.equal(Ok("07"))
  dict.get(occ.captures, "day") |> should.equal(Ok("04"))
}

pub fn iso_date_found_in_text_test() {
  let p = compile(iso_date_src)
  ptern.matches_in(p, "Independence Day 2026-07-04 - the 250th") |> should.be_true
  let assert Some(occ) = ptern.match_first_in(p, "event on 2026-07-04 at noon")
  occ.index |> should.equal(9)
  occ.length |> should.equal(10)
}

pub fn iso_date_length_test() {
  let p = compile(iso_date_src)
  ptern.min_length(p) |> should.equal(10)
  ptern.max_length(p) |> should.equal(Some(10))
}

// ---------------------------------------------------------------------------
// US date MM/DD/YYYY
// ---------------------------------------------------------------------------

const us_date_src = "
  mm = '0' '1'..'9' | '1' '0'..'2';
  dd = '0' '1'..'9' | '1'..'2' %Digit | '3' '0'..'1';
  {mm} '/' {dd} '/' %Digit * 4
"

pub fn us_date_valid_test() {
  let p = compile(us_date_src)
  ptern.matches_all_of(p, "07/04/2026") |> should.be_true
  ptern.matches_all_of(p, "01/01/2000") |> should.be_true
  ptern.matches_all_of(p, "12/31/1999") |> should.be_true
}

pub fn us_date_invalid_test() {
  let p = compile(us_date_src)
  ptern.matches_all_of(p, "7/4/2026") |> should.be_false
  ptern.matches_all_of(p, "13/04/2026") |> should.be_false
  ptern.matches_all_of(p, "07-04-2026") |> should.be_false
}

// ---------------------------------------------------------------------------
// 24-hour time HH:MM[:SS]
// ---------------------------------------------------------------------------

const time24_src = "
  hr = '0'..'1' %Digit | '2' '0'..'3';
  ms = '0'..'5' %Digit;
  {hr} ':' {ms} (':' {ms}) * 0..1
"

pub fn time24_valid_test() {
  let p = compile(time24_src)
  ptern.matches_all_of(p, "00:00") |> should.be_true
  ptern.matches_all_of(p, "23:59") |> should.be_true
  ptern.matches_all_of(p, "12:30") |> should.be_true
  ptern.matches_all_of(p, "09:05:00") |> should.be_true
  ptern.matches_all_of(p, "23:59:59") |> should.be_true
}

pub fn time24_invalid_test() {
  let p = compile(time24_src)
  ptern.matches_all_of(p, "24:00") |> should.be_false
  ptern.matches_all_of(p, "12:60") |> should.be_false
  ptern.matches_all_of(p, "9:00") |> should.be_false
  ptern.matches_all_of(p, "12:30:60") |> should.be_false
}

// ---------------------------------------------------------------------------
// 12-hour time with AM/PM
// ---------------------------------------------------------------------------

const time12_src = "
  hr = '1' '0'..'2' | ('0') * 0..1 '1'..'9';
  ms = '0'..'5' %Digit;
  {hr} ':' {ms} %Space * 0..1 ('A' | 'P') 'M'
"

pub fn time12_valid_test() {
  let p = compile(time12_src)
  ptern.matches_all_of(p, "12:00AM") |> should.be_true
  ptern.matches_all_of(p, "1:30PM") |> should.be_true
  ptern.matches_all_of(p, "01:00AM") |> should.be_true
  ptern.matches_all_of(p, "11:59 PM") |> should.be_true
}

pub fn time12_invalid_test() {
  let p = compile(time12_src)
  ptern.matches_all_of(p, "13:00PM") |> should.be_false
  ptern.matches_all_of(p, "0:00AM") |> should.be_false
  ptern.matches_all_of(p, "12:60AM") |> should.be_false
  ptern.matches_all_of(p, "12:00XM") |> should.be_false
}

// ---------------------------------------------------------------------------
// Floating-point number
// ---------------------------------------------------------------------------

const float_src = "
  @case-insensitive = true
  digits = %Digit * 1..20;
  exp = 'e' ('+' | '-') * 0..1 {digits} as exponent;
  ('+' | '-') * 0..1 {digits} as integer ('.' {digits}) * 0..1 {exp} * 0..1
"

pub fn float_valid_test() {
  let p = compile(float_src)
  ptern.matches_all_of(p, "42") |> should.be_true
  ptern.matches_all_of(p, "3.14") |> should.be_true
  ptern.matches_all_of(p, "-2.5") |> should.be_true
  ptern.matches_all_of(p, "+1.0") |> should.be_true
  ptern.matches_all_of(p, "1e10") |> should.be_true
  ptern.matches_all_of(p, "1.5E-3") |> should.be_true
  ptern.matches_all_of(p, "2.998e+8") |> should.be_true
}

pub fn float_invalid_test() {
  let p = compile(float_src)
  ptern.matches_all_of(p, ".5") |> should.be_false
  ptern.matches_all_of(p, "1.") |> should.be_false
  ptern.matches_all_of(p, "1e") |> should.be_false
  ptern.matches_all_of(p, "") |> should.be_false
}

pub fn float_captures_test() {
  let p = compile(float_src)
  let assert Some(occ) = ptern.match_all_of(p, "3.14")
  dict.get(occ.captures, "integer") |> should.equal(Ok("3"))
}

pub fn float_exponent_captures_test() {
  let p = compile(float_src)
  let assert Some(occ) = ptern.match_all_of(p, "1e10")
  dict.get(occ.captures, "integer") |> should.equal(Ok("1"))
  dict.get(occ.captures, "exponent") |> should.equal(Ok("10"))
}

// ---------------------------------------------------------------------------
// Decimal, up to 2 decimal places
// ---------------------------------------------------------------------------

pub fn decimal_2dp_valid_test() {
  let p = compile("%Digit * 1..? ('.' %Digit * 1..2) * 0..1")
  ptern.matches_all_of(p, "0") |> should.be_true
  ptern.matches_all_of(p, "42") |> should.be_true
  ptern.matches_all_of(p, "3.1") |> should.be_true
  ptern.matches_all_of(p, "9.99") |> should.be_true
  ptern.matches_all_of(p, "100") |> should.be_true
}

pub fn decimal_2dp_invalid_test() {
  let p = compile("%Digit * 1..? ('.' %Digit * 1..2) * 0..1")
  ptern.matches_all_of(p, "3.141") |> should.be_false
  ptern.matches_all_of(p, ".5") |> should.be_false
  ptern.matches_all_of(p, "1.") |> should.be_false
  ptern.matches_all_of(p, "abc") |> should.be_false
}

// ---------------------------------------------------------------------------
// Hexadecimal integer literal
// ---------------------------------------------------------------------------

const hex_src = "
  @case-insensitive = true
  '0x' %Xdigit * 1..16 as value
"

pub fn hex_valid_test() {
  let p = compile(hex_src)
  ptern.matches_all_of(p, "0x0") |> should.be_true
  ptern.matches_all_of(p, "0xFF") |> should.be_true
  ptern.matches_all_of(p, "0xDEADBEEF") |> should.be_true
  ptern.matches_all_of(p, "0x1a2b3c4d") |> should.be_true
  ptern.matches_all_of(p, "0XFF") |> should.be_true
}

pub fn hex_invalid_test() {
  let p = compile(hex_src)
  ptern.matches_all_of(p, "0x") |> should.be_false
  ptern.matches_all_of(p, "FF") |> should.be_false
  ptern.matches_all_of(p, "0xGG") |> should.be_false
  ptern.matches_all_of(p, "0x" <> "0123456789abcdef0") |> should.be_false
}

pub fn hex_capture_test() {
  let p = compile(hex_src)
  let assert Some(occ) = ptern.match_all_of(p, "0xDEAD")
  dict.get(occ.captures, "value") |> should.equal(Ok("DEAD"))
}

// ---------------------------------------------------------------------------
// Octal integer literal
// ---------------------------------------------------------------------------

pub fn octal_valid_test() {
  let p = compile("'0' '0'..'7' * 1..?")
  ptern.matches_all_of(p, "00") |> should.be_true
  ptern.matches_all_of(p, "07") |> should.be_true
  ptern.matches_all_of(p, "0755") |> should.be_true
  ptern.matches_all_of(p, "01234567") |> should.be_true
}

pub fn octal_invalid_test() {
  let p = compile("'0' '0'..'7' * 1..?")
  ptern.matches_all_of(p, "0") |> should.be_false
  ptern.matches_all_of(p, "08") |> should.be_false
  ptern.matches_all_of(p, "0x7") |> should.be_false
  ptern.matches_all_of(p, "755") |> should.be_false
}

// ---------------------------------------------------------------------------
// Binary integer literal
// ---------------------------------------------------------------------------

pub fn binary_valid_test() {
  let p = compile("'0b' ('0' | '1') * 1..?")
  ptern.matches_all_of(p, "0b0") |> should.be_true
  ptern.matches_all_of(p, "0b1") |> should.be_true
  ptern.matches_all_of(p, "0b1010") |> should.be_true
  ptern.matches_all_of(p, "0b11111111") |> should.be_true
}

pub fn binary_invalid_test() {
  let p = compile("'0b' ('0' | '1') * 1..?")
  ptern.matches_all_of(p, "0b") |> should.be_false
  ptern.matches_all_of(p, "0b2") |> should.be_false
  ptern.matches_all_of(p, "1010") |> should.be_false
  ptern.matches_all_of(p, "0x1010") |> should.be_false
}

// ---------------------------------------------------------------------------
// Semantic version
// ---------------------------------------------------------------------------

const semver_src = "
  num = %Digit * 1..10;
  {num} as major '.' {num} as minor '.' {num} as patch
"

pub fn semver_valid_test() {
  let p = compile(semver_src)
  ptern.matches_all_of(p, "1.0.0") |> should.be_true
  ptern.matches_all_of(p, "2.14.3") |> should.be_true
  ptern.matches_all_of(p, "0.0.1") |> should.be_true
  ptern.matches_all_of(p, "10.20.30") |> should.be_true
}

pub fn semver_invalid_test() {
  let p = compile(semver_src)
  ptern.matches_all_of(p, "1.0") |> should.be_false
  ptern.matches_all_of(p, "1.0.0.0") |> should.be_false
  ptern.matches_all_of(p, "v1.0.0") |> should.be_false
  ptern.matches_all_of(p, "1.0.") |> should.be_false
}

pub fn semver_captures_test() {
  let p = compile(semver_src)
  let assert Some(occ) = ptern.match_all_of(p, "2.14.3")
  dict.get(occ.captures, "major") |> should.equal(Ok("2"))
  dict.get(occ.captures, "minor") |> should.equal(Ok("14"))
  dict.get(occ.captures, "patch") |> should.equal(Ok("3"))
}

// ---------------------------------------------------------------------------
// Unicode identifier, max 32 chars
// ---------------------------------------------------------------------------

pub fn unicode_ident_valid_test() {
  let p = compile("(%L | '_') (%L | %N | '_') * 0..31")
  ptern.matches_all_of(p, "x") |> should.be_true
  ptern.matches_all_of(p, "_foo") |> should.be_true
  ptern.matches_all_of(p, "myVar123") |> should.be_true
  ptern.matches_all_of(p, "a" <> "_b" <> "c") |> should.be_true
}

pub fn unicode_ident_invalid_test() {
  let p = compile("(%L | '_') (%L | %N | '_') * 0..31")
  ptern.matches_all_of(p, "1abc") |> should.be_false
  ptern.matches_all_of(p, "-name") |> should.be_false
  ptern.matches_all_of(p, "") |> should.be_false
}

pub fn unicode_ident_max_length_boundary_test() {
  let p = compile("(%L | '_') (%L | %N | '_') * 0..31")
  let exactly_32 = "a" <> "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
  let over_32 = "a" <> "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
  ptern.matches_all_of(p, exactly_32) |> should.be_true
  ptern.matches_all_of(p, over_32) |> should.be_false
}

// ---------------------------------------------------------------------------
// ASCII identifier
// ---------------------------------------------------------------------------

pub fn ascii_ident_valid_test() {
  let p = compile("%Alpha (%Alnum | '_') * 0..?")
  ptern.matches_all_of(p, "x") |> should.be_true
  ptern.matches_all_of(p, "foo_bar") |> should.be_true
  ptern.matches_all_of(p, "CamelCase") |> should.be_true
  ptern.matches_all_of(p, "a1b2c3") |> should.be_true
}

pub fn ascii_ident_invalid_test() {
  let p = compile("%Alpha (%Alnum | '_') * 0..?")
  ptern.matches_all_of(p, "1abc") |> should.be_false
  ptern.matches_all_of(p, "_foo") |> should.be_false
  ptern.matches_all_of(p, "foo-bar") |> should.be_false
  ptern.matches_all_of(p, "") |> should.be_false
}

// ---------------------------------------------------------------------------
// Username
// ---------------------------------------------------------------------------

pub fn username_valid_test() {
  let p = compile("%Lower (%Lower | %Digit | '_' | '-') * 2..19")
  ptern.matches_all_of(p, "abc") |> should.be_true
  ptern.matches_all_of(p, "user_name") |> should.be_true
  ptern.matches_all_of(p, "user-123") |> should.be_true
}

pub fn username_invalid_test() {
  let p = compile("%Lower (%Lower | %Digit | '_' | '-') * 2..19")
  ptern.matches_all_of(p, "ab") |> should.be_false
  ptern.matches_all_of(p, "ABC") |> should.be_false
  ptern.matches_all_of(p, "1user") |> should.be_false
}

pub fn username_length_boundary_test() {
  let p = compile("%Lower (%Lower | %Digit | '_' | '-') * 2..19")
  let exactly_3 = "abc"
  let exactly_20 = "abbbbbbbbbbbbbbbbbbb"
  let over_20 = "abbbbbbbbbbbbbbbbbbbb"
  ptern.matches_all_of(p, exactly_3) |> should.be_true
  ptern.matches_all_of(p, exactly_20) |> should.be_true
  ptern.matches_all_of(p, over_20) |> should.be_false
}

// ---------------------------------------------------------------------------
// PascalCase identifier
// ---------------------------------------------------------------------------

pub fn pascal_case_valid_test() {
  let p = compile("%Upper %Lower * 1..? (%Upper %Lower * 1..?) * 0..?")
  ptern.matches_all_of(p, "Foo") |> should.be_true
  ptern.matches_all_of(p, "FooBar") |> should.be_true
  ptern.matches_all_of(p, "MyClassName") |> should.be_true
}

pub fn pascal_case_invalid_test() {
  let p = compile("%Upper %Lower * 1..? (%Upper %Lower * 1..?) * 0..?")
  ptern.matches_all_of(p, "foo") |> should.be_false
  ptern.matches_all_of(p, "FOO") |> should.be_false
  ptern.matches_all_of(p, "fooBar") |> should.be_false
  ptern.matches_all_of(p, "F") |> should.be_false
}

// ---------------------------------------------------------------------------
// camelCase identifier
// ---------------------------------------------------------------------------

pub fn camel_case_valid_test() {
  let p = compile("%Lower * 1..? (%Upper %Lower * 1..?) * 0..?")
  ptern.matches_all_of(p, "foo") |> should.be_true
  ptern.matches_all_of(p, "fooBar") |> should.be_true
  ptern.matches_all_of(p, "myVariableName") |> should.be_true
}

pub fn camel_case_invalid_test() {
  let p = compile("%Lower * 1..? (%Upper %Lower * 1..?) * 0..?")
  ptern.matches_all_of(p, "FooBar") |> should.be_false
  ptern.matches_all_of(p, "FOO") |> should.be_false
  ptern.matches_all_of(p, "foo_bar") |> should.be_false
}

// ---------------------------------------------------------------------------
// snake_case identifier
// ---------------------------------------------------------------------------

pub fn snake_case_valid_test() {
  let p = compile("%Lower * 1..? ('_' %Lower * 1..?) * 0..?")
  ptern.matches_all_of(p, "foo") |> should.be_true
  ptern.matches_all_of(p, "foo_bar") |> should.be_true
  ptern.matches_all_of(p, "my_var_name") |> should.be_true
}

pub fn snake_case_invalid_test() {
  let p = compile("%Lower * 1..? ('_' %Lower * 1..?) * 0..?")
  ptern.matches_all_of(p, "FooBar") |> should.be_false
  ptern.matches_all_of(p, "_foo") |> should.be_false
  ptern.matches_all_of(p, "foo_") |> should.be_false
  ptern.matches_all_of(p, "foo__bar") |> should.be_false
}

// ---------------------------------------------------------------------------
// Boolean keyword
// ---------------------------------------------------------------------------

pub fn boolean_keyword_valid_test() {
  matches("'true' | 'false'", "true") |> should.be_true
  matches("'true' | 'false'", "false") |> should.be_true
}

pub fn boolean_keyword_invalid_test() {
  matches("'true' | 'false'", "True") |> should.be_false
  matches("'true' | 'false'", "TRUE") |> should.be_false
  matches("'true' | 'false'", "yes") |> should.be_false
  matches("'true' | 'false'", "1") |> should.be_false
}

// ---------------------------------------------------------------------------
// Null-like keyword
// ---------------------------------------------------------------------------

pub fn null_keyword_valid_test() {
  let p = compile("'null' | 'undefined' | 'nil' | 'None'")
  ptern.matches_all_of(p, "null") |> should.be_true
  ptern.matches_all_of(p, "undefined") |> should.be_true
  ptern.matches_all_of(p, "nil") |> should.be_true
  ptern.matches_all_of(p, "None") |> should.be_true
}

pub fn null_keyword_invalid_test() {
  let p = compile("'null' | 'undefined' | 'nil' | 'None'")
  ptern.matches_all_of(p, "Null") |> should.be_false
  ptern.matches_all_of(p, "none") |> should.be_false
  ptern.matches_all_of(p, "NULL") |> should.be_false
}

// ---------------------------------------------------------------------------
// Email address
// ---------------------------------------------------------------------------

const email_src = "
  lc = %Alnum | '.' | '_' | '%' | '+' | '-';
  dc = %Alnum | '.' | '-';
  {lc} * 1..? '@' {dc} * 1..? '.' %Alpha * 2..?
"

pub fn email_valid_test() {
  let p = compile(email_src)
  ptern.matches_all_of(p, "user@example.com") |> should.be_true
  ptern.matches_all_of(p, "first.last@sub.domain.org") |> should.be_true
  ptern.matches_all_of(p, "user+tag@example.co.uk") |> should.be_true
  ptern.matches_all_of(p, "a@b.io") |> should.be_true
}

pub fn email_invalid_test() {
  let p = compile(email_src)
  ptern.matches_all_of(p, "notanemail") |> should.be_false
  ptern.matches_all_of(p, "@example.com") |> should.be_false
  ptern.matches_all_of(p, "user@") |> should.be_false
  ptern.matches_all_of(p, "user@example") |> should.be_false
}

// ---------------------------------------------------------------------------
// IPv4 address (octets not range-checked)
// ---------------------------------------------------------------------------

const ipv4_simple_src = "
  oct = %Digit * 1..3;
  ({oct} '.') * 3 {oct}
"

pub fn ipv4_simple_valid_test() {
  let p = compile(ipv4_simple_src)
  ptern.matches_all_of(p, "192.168.1.1") |> should.be_true
  ptern.matches_all_of(p, "0.0.0.0") |> should.be_true
  ptern.matches_all_of(p, "255.255.255.255") |> should.be_true
  ptern.matches_all_of(p, "10.0.0.1") |> should.be_true
}

pub fn ipv4_simple_invalid_test() {
  let p = compile(ipv4_simple_src)
  ptern.matches_all_of(p, "192.168.1") |> should.be_false
  ptern.matches_all_of(p, "192.168.1.1.1") |> should.be_false
  ptern.matches_all_of(p, "192.168.1.abc") |> should.be_false
  ptern.matches_all_of(p, "1.2.3.4444") |> should.be_false
}

// ---------------------------------------------------------------------------
// IPv4 address (strictly 0–255)
// ---------------------------------------------------------------------------

const ipv4_strict_src = "
  octet = %Digit
        | '1'..'9' %Digit
        | '1' %Digit %Digit
        | '2' '0'..'4' %Digit
        | '2' '5' '0'..'5';
  {octet} as a '.' {octet} as b '.' {octet} as c '.' {octet} as d
"

pub fn ipv4_strict_valid_test() {
  let p = compile(ipv4_strict_src)
  ptern.matches_all_of(p, "0.0.0.0") |> should.be_true
  ptern.matches_all_of(p, "255.255.255.255") |> should.be_true
  ptern.matches_all_of(p, "192.168.0.1") |> should.be_true
  ptern.matches_all_of(p, "10.0.0.254") |> should.be_true
}

pub fn ipv4_strict_out_of_range_test() {
  let p = compile(ipv4_strict_src)
  ptern.matches_all_of(p, "256.0.0.1") |> should.be_false
  ptern.matches_all_of(p, "192.168.0.300") |> should.be_false
  ptern.matches_all_of(p, "999.999.999.999") |> should.be_false
}

pub fn ipv4_strict_captures_test() {
  let p = compile(ipv4_strict_src)
  let assert Some(occ) = ptern.match_all_of(p, "192.168.0.1")
  dict.get(occ.captures, "a") |> should.equal(Ok("192"))
  dict.get(occ.captures, "b") |> should.equal(Ok("168"))
  dict.get(occ.captures, "c") |> should.equal(Ok("0"))
  dict.get(occ.captures, "d") |> should.equal(Ok("1"))
}

// ---------------------------------------------------------------------------
// E.164 international phone
// ---------------------------------------------------------------------------

pub fn e164_valid_test() {
  let p = compile("('+') * 0..1 '1'..'9' %Digit * 1..14")
  ptern.matches_all_of(p, "12125551234") |> should.be_true
  ptern.matches_all_of(p, "+12125551234") |> should.be_true
  ptern.matches_all_of(p, "+442071838750") |> should.be_true
  ptern.matches_all_of(p, "1") |> should.be_false
}

pub fn e164_invalid_test() {
  let p = compile("('+') * 0..1 '1'..'9' %Digit * 1..14")
  ptern.matches_all_of(p, "0123456789") |> should.be_false
  ptern.matches_all_of(p, "+") |> should.be_false
  ptern.matches_all_of(p, "++12125551234") |> should.be_false
}

// ---------------------------------------------------------------------------
// US ZIP code (optional +4)
// ---------------------------------------------------------------------------

pub fn zip_valid_test() {
  let p = compile("%Digit * 5 ('-' %Digit * 4) * 0..1")
  ptern.matches_all_of(p, "90210") |> should.be_true
  ptern.matches_all_of(p, "10001") |> should.be_true
  ptern.matches_all_of(p, "90210-1234") |> should.be_true
}

pub fn zip_invalid_test() {
  let p = compile("%Digit * 5 ('-' %Digit * 4) * 0..1")
  ptern.matches_all_of(p, "9021") |> should.be_false
  ptern.matches_all_of(p, "902100") |> should.be_false
  ptern.matches_all_of(p, "90210-123") |> should.be_false
  ptern.matches_all_of(p, "90210-12345") |> should.be_false
}

pub fn zip_length_test() {
  let p = compile("%Digit * 5 ('-' %Digit * 4) * 0..1")
  ptern.min_length(p) |> should.equal(5)
  ptern.max_length(p) |> should.equal(Some(10))
}

// ---------------------------------------------------------------------------
// UK postcode
// ---------------------------------------------------------------------------

pub fn uk_postcode_valid_test() {
  let p = compile(
    "%Upper * 1..2 %Digit (%Upper | %Digit) * 0..1 %Space * 0..1 %Digit %Upper * 2",
  )
  ptern.matches_all_of(p, "SW1A1AA") |> should.be_true
  ptern.matches_all_of(p, "SW1A 1AA") |> should.be_true
  ptern.matches_all_of(p, "M11AE") |> should.be_true
  ptern.matches_all_of(p, "EC1A1BB") |> should.be_true
}

pub fn uk_postcode_invalid_test() {
  let p = compile(
    "%Upper * 1..2 %Digit (%Upper | %Digit) * 0..1 %Space * 0..1 %Digit %Upper * 2",
  )
  ptern.matches_all_of(p, "12345") |> should.be_false
  ptern.matches_all_of(p, "sw1a1aa") |> should.be_false
}

// ---------------------------------------------------------------------------
// UUID / GUID
// ---------------------------------------------------------------------------

pub fn uuid_valid_test() {
  let p = compile("%Xdigit * 8 '-' (%Xdigit * 4 '-') * 3 %Xdigit * 12")
  ptern.matches_all_of(p, "550e8400-e29b-41d4-a716-446655440000") |> should.be_true
  ptern.matches_all_of(p, "00000000-0000-0000-0000-000000000000") |> should.be_true
  ptern.matches_all_of(p, "ffffffff-ffff-ffff-ffff-ffffffffffff") |> should.be_true
}

pub fn uuid_invalid_test() {
  let p = compile("%Xdigit * 8 '-' (%Xdigit * 4 '-') * 3 %Xdigit * 12")
  ptern.matches_all_of(p, "550e8400-e29b-41d4-a716-44665544000") |> should.be_false
  ptern.matches_all_of(p, "550e8400e29b41d4a716446655440000") |> should.be_false
  ptern.matches_all_of(p, "gggggggg-gggg-gggg-gggg-gggggggggggg") |> should.be_false
}

pub fn uuid_length_test() {
  let p = compile("%Xdigit * 8 '-' (%Xdigit * 4 '-') * 3 %Xdigit * 12")
  ptern.min_length(p) |> should.equal(36)
  ptern.max_length(p) |> should.equal(Some(36))
}

// ---------------------------------------------------------------------------
// US Social Security Number
// ---------------------------------------------------------------------------

pub fn ssn_valid_test() {
  let p = compile("%Digit * 3 '-' %Digit * 2 '-' %Digit * 4")
  ptern.matches_all_of(p, "123-45-6789") |> should.be_true
  ptern.matches_all_of(p, "000-00-0000") |> should.be_true
}

pub fn ssn_invalid_test() {
  let p = compile("%Digit * 3 '-' %Digit * 2 '-' %Digit * 4")
  ptern.matches_all_of(p, "123456789") |> should.be_false
  ptern.matches_all_of(p, "12-345-6789") |> should.be_false
  ptern.matches_all_of(p, "abc-de-fghi") |> should.be_false
}

pub fn ssn_length_test() {
  let p = compile("%Digit * 3 '-' %Digit * 2 '-' %Digit * 4")
  ptern.min_length(p) |> should.equal(11)
  ptern.max_length(p) |> should.equal(Some(11))
}

// ---------------------------------------------------------------------------
// Visa card number
// ---------------------------------------------------------------------------

pub fn visa_valid_test() {
  let p = compile("'4' %Digit * 12 (%Digit * 3) * 0..1")
  ptern.matches_all_of(p, "4111111111111") |> should.be_true
  ptern.matches_all_of(p, "4111111111111111") |> should.be_true
}

pub fn visa_invalid_test() {
  let p = compile("'4' %Digit * 12 (%Digit * 3) * 0..1")
  ptern.matches_all_of(p, "5111111111111") |> should.be_false
  ptern.matches_all_of(p, "411111111111") |> should.be_false
  ptern.matches_all_of(p, "41111111111111") |> should.be_false
}

// ---------------------------------------------------------------------------
// Mastercard number
// ---------------------------------------------------------------------------

pub fn mastercard_valid_test() {
  let p = compile("'5' '1'..'5' %Digit * 14")
  ptern.matches_all_of(p, "5111111111111118") |> should.be_true
  ptern.matches_all_of(p, "5500000000000004") |> should.be_true
}

pub fn mastercard_invalid_test() {
  let p = compile("'5' '1'..'5' %Digit * 14")
  ptern.matches_all_of(p, "5011111111111117") |> should.be_false
  ptern.matches_all_of(p, "5611111111111117") |> should.be_false
  ptern.matches_all_of(p, "4111111111111111") |> should.be_false
}

// ---------------------------------------------------------------------------
// Credit card — four groups of four digits
// ---------------------------------------------------------------------------

const cc_groups_src = "
  group = %Digit * 4;
  {group} ' ' {group} ' ' {group} ' ' {group}
"

pub fn cc_groups_valid_test() {
  let p = compile(cc_groups_src)
  ptern.matches_all_of(p, "4111 1111 1111 1111") |> should.be_true
  ptern.matches_all_of(p, "0000 0000 0000 0000") |> should.be_true
}

pub fn cc_groups_invalid_test() {
  let p = compile(cc_groups_src)
  ptern.matches_all_of(p, "4111111111111111") |> should.be_false
  ptern.matches_all_of(p, "4111 1111 1111 111") |> should.be_false
  ptern.matches_all_of(p, "4111 1111 1111 11111") |> should.be_false
}

pub fn cc_groups_length_test() {
  let p = compile(cc_groups_src)
  ptern.min_length(p) |> should.equal(19)
  ptern.max_length(p) |> should.equal(Some(19))
}

// ---------------------------------------------------------------------------
// SHA-1 / SHA-256 hashes
// ---------------------------------------------------------------------------

pub fn sha1_valid_test() {
  let p = compile("%Xdigit * 40")
  ptern.matches_all_of(p, "da39a3ee5e6b4b0d3255bfef95601890afd80709") |> should.be_true
  ptern.matches_all_of(p, "0000000000000000000000000000000000000000") |> should.be_true
}

pub fn sha1_invalid_test() {
  let p = compile("%Xdigit * 40")
  ptern.matches_all_of(p, "da39a3ee5e6b4b0d3255bfef95601890afd8070") |> should.be_false
  ptern.matches_all_of(p, "da39a3ee5e6b4b0d3255bfef95601890afd807090") |> should.be_false
  ptern.matches_all_of(p, "zz39a3ee5e6b4b0d3255bfef95601890afd80709") |> should.be_false
}

pub fn sha256_valid_test() {
  let p = compile("%Xdigit * 64")
  let hash = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
  ptern.matches_all_of(p, hash) |> should.be_true
}

pub fn sha256_invalid_test() {
  let p = compile("%Xdigit * 64")
  let short = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b85"
  ptern.matches_all_of(p, short) |> should.be_false
}

// ---------------------------------------------------------------------------
// CSS hex color (#RGB or #RRGGBB with captures)
// ---------------------------------------------------------------------------

// Captures can't span alternation branches (duplicate capture names), so
// this pattern validates format only. Per-branch capture versions would need
// two separate compiled pterns.
const css_hex_src = "'#' (%Xdigit * 6 | %Xdigit * 3)"

pub fn css_hex_rrggbb_valid_test() {
  let p = compile(css_hex_src)
  ptern.matches_all_of(p, "#ff0000") |> should.be_true
  ptern.matches_all_of(p, "#000000") |> should.be_true
  ptern.matches_all_of(p, "#1a2b3c") |> should.be_true
  ptern.matches_all_of(p, "#FFFFFF") |> should.be_true
}

pub fn css_hex_rgb_valid_test() {
  let p = compile(css_hex_src)
  ptern.matches_all_of(p, "#f00") |> should.be_true
  ptern.matches_all_of(p, "#000") |> should.be_true
  ptern.matches_all_of(p, "#abc") |> should.be_true
}

pub fn css_hex_invalid_test() {
  let p = compile(css_hex_src)
  ptern.matches_all_of(p, "ff0000") |> should.be_false
  ptern.matches_all_of(p, "#ff000") |> should.be_false
  ptern.matches_all_of(p, "#ff00000") |> should.be_false
  ptern.matches_all_of(p, "#gg0000") |> should.be_false
}

pub fn css_hex_length_test() {
  let p = compile(css_hex_src)
  ptern.min_length(p) |> should.equal(4)
  ptern.max_length(p) |> should.equal(Some(7))
}

// ---------------------------------------------------------------------------
// CSS rgb() color
// ---------------------------------------------------------------------------

const css_rgb_src =
  "'rgb(' %Space * 0..? %Digit * 1..3 ',' %Space * 0..? %Digit * 1..3 ',' %Space * 0..? %Digit * 1..3 %Space * 0..? ')'"

pub fn css_rgb_valid_test() {
  let p = compile(css_rgb_src)
  ptern.matches_all_of(p, "rgb(255,0,0)") |> should.be_true
  ptern.matches_all_of(p, "rgb(0, 128, 255)") |> should.be_true
  ptern.matches_all_of(p, "rgb( 0, 0, 0 )") |> should.be_true
}

pub fn css_rgb_invalid_test() {
  let p = compile(css_rgb_src)
  ptern.matches_all_of(p, "rgb(1000,0,0)") |> should.be_false
  ptern.matches_all_of(p, "rgb(255,0)") |> should.be_false
  ptern.matches_all_of(p, "255,0,0") |> should.be_false
}

// ---------------------------------------------------------------------------
// CSS length value
// ---------------------------------------------------------------------------

const css_length_src =
  "%Digit * 1..? ('.' %Digit * 1..?) * 0..1 ('px' | 'em' | 'rem' | '%' | 'vh' | 'vw')"

pub fn css_length_valid_test() {
  let p = compile(css_length_src)
  ptern.matches_all_of(p, "16px") |> should.be_true
  ptern.matches_all_of(p, "1.5em") |> should.be_true
  ptern.matches_all_of(p, "2rem") |> should.be_true
  ptern.matches_all_of(p, "100%") |> should.be_true
  ptern.matches_all_of(p, "50vh") |> should.be_true
  ptern.matches_all_of(p, "25vw") |> should.be_true
}

pub fn css_length_invalid_test() {
  let p = compile(css_length_src)
  ptern.matches_all_of(p, "16") |> should.be_false
  ptern.matches_all_of(p, "px") |> should.be_false
  ptern.matches_all_of(p, "16pt") |> should.be_false
  ptern.matches_all_of(p, ".5em") |> should.be_false
}

// ---------------------------------------------------------------------------
// C-style line comment
// ---------------------------------------------------------------------------

pub fn c_line_comment_valid_test() {
  let p = compile("'//' (%Any excluding '\\n') * 0..?")
  ptern.matches_all_of(p, "// comment") |> should.be_true
  ptern.matches_all_of(p, "//") |> should.be_true
  ptern.matches_all_of(p, "// TODO: fix this") |> should.be_true
}

pub fn c_line_comment_invalid_test() {
  let p = compile("'//' (%Any excluding '\\n') * 0..?")
  ptern.matches_all_of(p, "/ comment") |> should.be_false
  ptern.matches_all_of(p, "# comment") |> should.be_false
}

pub fn c_line_comment_no_newline_test() {
  let p = compile("'//' (%Any excluding '\\n') * 0..?")
  ptern.matches_all_of(p, "// line one\n// line two") |> should.be_false
  ptern.matches_start_of(p, "// line one\n// line two") |> should.be_true
}

// ---------------------------------------------------------------------------
// C-style block comment
// ---------------------------------------------------------------------------

pub fn c_block_comment_valid_test() {
  let p = compile("'/*' %Any * 0..? '*/'")
  ptern.matches_all_of(p, "/* comment */") |> should.be_true
  ptern.matches_all_of(p, "/**/") |> should.be_true
  ptern.matches_all_of(p, "/* multi\nline */") |> should.be_true
}

pub fn c_block_comment_invalid_test() {
  let p = compile("'/*' %Any * 0..? '*/'")
  ptern.matches_all_of(p, "// not a block comment") |> should.be_false
  ptern.matches_all_of(p, "/* unterminated") |> should.be_false
}

// ---------------------------------------------------------------------------
// HTML comment
// ---------------------------------------------------------------------------

pub fn html_comment_valid_test() {
  let p = compile("'<!--' %Any * 0..? '-->'")
  ptern.matches_all_of(p, "<!-- comment -->") |> should.be_true
  ptern.matches_all_of(p, "<!---->") |> should.be_true
  ptern.matches_all_of(p, "<!-- multi\nline -->") |> should.be_true
}

pub fn html_comment_invalid_test() {
  let p = compile("'<!--' %Any * 0..? '-->'")
  ptern.matches_all_of(p, "// not html") |> should.be_false
  ptern.matches_all_of(p, "<!-- unterminated") |> should.be_false
  ptern.matches_all_of(p, "<! comment -->") |> should.be_false
}

// ---------------------------------------------------------------------------
// Blank / whitespace-only line
// ---------------------------------------------------------------------------

pub fn blank_line_valid_test() {
  let p = compile("%Space * 0..?")
  ptern.matches_all_of(p, "") |> should.be_true
  ptern.matches_all_of(p, " ") |> should.be_true
  ptern.matches_all_of(p, "   ") |> should.be_true
  ptern.matches_all_of(p, "\t") |> should.be_true
  ptern.matches_all_of(p, " \t ") |> should.be_true
}

pub fn blank_line_invalid_test() {
  let p = compile("%Space * 0..?")
  ptern.matches_all_of(p, "a") |> should.be_false
  ptern.matches_all_of(p, " x ") |> should.be_false
}

// ---------------------------------------------------------------------------
// Double-quoted string literal (allows embedded newlines)
// ---------------------------------------------------------------------------

const dq_string_src = "
  char = %Any excluding '\"';
  '\"' ({char} | '\\\"') * 0..1000 '\"'
"

pub fn dq_string_valid_test() {
  let p = compile(dq_string_src)
  ptern.matches_all_of(p, "\"hello\"") |> should.be_true
  ptern.matches_all_of(p, "\"\"") |> should.be_true
  ptern.matches_all_of(p, "\"say \\\"hello\\\"\"") |> should.be_true
}

pub fn dq_string_invalid_test() {
  let p = compile(dq_string_src)
  ptern.matches_all_of(p, "hello") |> should.be_false
  ptern.matches_all_of(p, "\"unterminated") |> should.be_false
}
