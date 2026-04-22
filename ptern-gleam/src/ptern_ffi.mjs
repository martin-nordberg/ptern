import { toList } from "../prelude.mjs";
import { None, Some } from "../gleam_stdlib/gleam/option.mjs";

export function make_regex(source, flags) {
  return new RegExp(source, flags);
}

export function test_regex(regex, input) {
  regex.lastIndex = 0;
  return regex.test(input);
}

function captures_list(m) {
  const groups = m.groups ?? {};
  return toList(
    Object.entries(groups)
      .filter(([, v]) => typeof v === "string")
      .map(([k, v]) => [k, v]),
  );
}

// Returns Some([index, length, captures]) or None.
export function exec_regex_rich(regex, input) {
  regex.lastIndex = 0;
  const m = regex.exec(input);
  if (m === null) return new None();
  return new Some([m.index, m[0].length, captures_list(m)]);
}

// Returns Some([index, length, captures]) or None, starting from startIndex.
// Requires the regex to have the 'g' flag.
export function exec_regex_from_rich(regex, input, startIndex) {
  regex.lastIndex = startIndex;
  const m = regex.exec(input);
  if (m === null) return new None();
  return new Some([m.index, m[0].length, captures_list(m)]);
}

// Returns a Gleam List of [index, length, captures] tuples for all matches.
// Requires the regex to have the 'g' flag.
export function exec_all_regex_rich(regex, input) {
  regex.lastIndex = 0;
  const results = [];
  let m;
  while ((m = regex.exec(input)) !== null) {
    results.push([m.index, m[0].length, captures_list(m)]);
    if (m[0].length === 0) regex.lastIndex++;
  }
  return toList(results);
}
