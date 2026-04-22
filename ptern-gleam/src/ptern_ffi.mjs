import { toList } from "../prelude.mjs";
import { None, Some } from "../gleam_stdlib/gleam/option.mjs";

export function make_regex(source, flags) {
  return new RegExp(source, flags);
}

export function test_regex(regex, input) {
  regex.lastIndex = 0;
  return regex.test(input);
}

// Returns Some(List(#(String, String))) with named captures, or None on no match.
export function exec_regex(regex, input) {
  regex.lastIndex = 0;
  const m = regex.exec(input);
  if (m === null) return new None();
  const groups = m.groups ?? {};
  const pairs = Object.entries(groups)
    .filter(([, v]) => typeof v === "string")
    .map(([k, v]) => [k, v]);  // Gleam tuples are JS arrays
  return new Some(toList(pairs));
}
