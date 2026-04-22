import { toList } from "../prelude.mjs";
import { None, Some } from "../gleam_stdlib/gleam/option.mjs";

export function make_regex(source, flags) {
  return new RegExp(source, flags);
}

export function test_regex(regex, input) {
  regex.lastIndex = 0;
  return regex.test(input);
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

function captures_list(m) {
  const groups = m.groups ?? {};
  return toList(
    Object.entries(groups)
      .filter(([, v]) => typeof v === "string")
      .map(([k, v]) => [k, v]),
  );
}

function gleam_list_to_array(list) {
  const arr = [];
  let node = list;
  while (node && node.head !== undefined) {
    arr.push(node.head);
    node = node.tail;
  }
  return arr;
}

// Build the replacement text for one match using per-capture indices (requires 'd' flag).
function apply_capture_replacements(m, replacementsArr) {
  const matchStart = m.index;
  const groupIndices = m.indices?.groups ?? {};
  let matchText = m[0];
  const patches = replacementsArr
    .filter(([name]) => groupIndices[name] !== undefined)
    .map(([name, newVal]) => ({
      relStart: groupIndices[name][0] - matchStart,
      relEnd: groupIndices[name][1] - matchStart,
      newVal,
    }))
    .sort((a, b) => b.relStart - a.relStart); // right-to-left so earlier offsets stay valid
  for (const { relStart, relEnd, newVal } of patches) {
    matchText = matchText.slice(0, relStart) + newVal + matchText.slice(relEnd);
  }
  return matchText;
}

// ---------------------------------------------------------------------------
// Exec (returns occurrence tuple)
// ---------------------------------------------------------------------------

// Returns Some([index, length, captures]) or None.
export function exec_regex_rich(regex, input) {
  regex.lastIndex = 0;
  const m = regex.exec(input);
  if (m === null) return new None();
  return new Some([m.index, m[0].length, captures_list(m)]);
}

// Returns Some([index, length, captures]) or None, starting from startIndex.
// Requires the 'g' flag on the regex.
export function exec_regex_from_rich(regex, input, startIndex) {
  regex.lastIndex = startIndex;
  const m = regex.exec(input);
  if (m === null) return new None();
  return new Some([m.index, m[0].length, captures_list(m)]);
}

// Returns a Gleam List of [index, length, captures] tuples for all matches.
// Requires the 'g' flag on the regex.
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

// ---------------------------------------------------------------------------
// Replace (requires 'd' flag on all regexes; 'g' flag additionally for from/all)
// ---------------------------------------------------------------------------

// Replace the first match, or return input unchanged if no match.
export function replace_regex_rich(regex, input, gleamReplacementsList) {
  regex.lastIndex = 0;
  const m = regex.exec(input);
  if (m === null) return input;
  const newText = apply_capture_replacements(m, gleam_list_to_array(gleamReplacementsList));
  return input.slice(0, m.index) + newText + input.slice(m.index + m[0].length);
}

// Replace the next match at or after startIndex, or return input unchanged.
// Requires the 'g' flag on the regex.
export function replace_regex_from_rich(regex, input, startIndex, gleamReplacementsList) {
  regex.lastIndex = startIndex;
  const m = regex.exec(input);
  if (m === null) return input;
  const newText = apply_capture_replacements(m, gleam_list_to_array(gleamReplacementsList));
  return input.slice(0, m.index) + newText + input.slice(m.index + m[0].length);
}

// Replace all matches with the same replacements.
// Requires the 'g' flag on the regex.
export function replace_all_regex_rich(regex, input, gleamReplacementsList) {
  regex.lastIndex = 0;
  const replacementsArr = gleam_list_to_array(gleamReplacementsList);
  const parts = [];
  let lastEnd = 0;
  let m;
  while ((m = regex.exec(input)) !== null) {
    parts.push(input.slice(lastEnd, m.index));
    parts.push(apply_capture_replacements(m, replacementsArr));
    lastEnd = m.index + m[0].length;
    if (m[0].length === 0) regex.lastIndex++;
  }
  parts.push(input.slice(lastEnd));
  return parts.join("");
}
