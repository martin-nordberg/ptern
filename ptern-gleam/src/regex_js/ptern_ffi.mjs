import { toList } from "../../prelude.mjs";
import { Ok, Error } from "../../prelude.mjs";
import { None, Some } from "../../gleam_stdlib/gleam/option.mjs";

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
      .filter(([k, v]) => !k.startsWith("__rep_") && typeof v === "string")
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

// ---------------------------------------------------------------------------
// Two-pass replacement helpers for array-valued captures
// ---------------------------------------------------------------------------

// Build patches for one regex match, handling both scalar and array replacements.
// Returns { result: string, mismatches: [[name, provided, actual], ...] }.
// scalarsArr: [[name, newVal], ...]
// arraysArr:  [[name, [val0, val1, ...]], ...]
// repInfoArr: [[groupName, subSource, [capName, ...]], ...]
// flags: string (flags for the main pattern, used to build sub-regexes)
function apply_capture_replacements_with_arrays(m, input, scalarsArr, arraysArr, repInfoArr, flags) {
  const matchStart = m.index;
  const groupIndices = m.indices?.groups ?? {};
  const patches = [];
  const mismatches = [];

  // Build rep-info maps (needed for scalar broadcast AND array two-pass).
  const repInfoByGroup = new Map();
  const repGroupForCapture = new Map();
  for (const [gn, sub, capsGleam] of repInfoArr) {
    const caps = gleam_list_to_array(capsGleam);
    repInfoByGroup.set(gn, { sub, caps });
    for (const cap of caps) repGroupForCapture.set(cap, gn);
  }

  // Sub-regex flags: strip 'g' and 'd' from main flags, then add both back.
  // (Main flags already contain 'd'; avoid duplicate-flag SyntaxError.)
  const subFlags = flags.replace(/[gd]/g, "") + "dg";

  // Helper: two-pass to collect per-iteration spans for a capture inside a rep group.
  // Returns { outerSpan: [start,end]|undefined, iterSpans: [[start,end], ...] }.
  function collectIterSpans(name, repGroupName) {
    const repSpan = groupIndices[repGroupName];
    if (repSpan === undefined) return { outerSpan: undefined, iterSpans: [] };

    // An outer occurrence exists when the named group falls BEFORE the rep span start
    // (the outer group is kept in the main regex; the inner one is suppressed).
    const outerSpan = groupIndices[name];
    const hasOuter = outerSpan !== undefined && outerSpan[0] < repSpan[0];

    const { sub } = repInfoByGroup.get(repGroupName);
    const subRe = new RegExp(sub, subFlags);
    subRe.lastIndex = repSpan[0];
    const iterSpans = [];
    let mi;
    while ((mi = subRe.exec(input)) !== null && mi.index < repSpan[1]) {
      const iterSpan = mi.indices?.groups?.[name];
      if (iterSpan !== undefined) iterSpans.push(iterSpan);
      if (mi[0].length === 0) subRe.lastIndex++;
    }

    return { outerSpan: hasOuter ? outerSpan : undefined, iterSpans };
  }

  // Scalar replacements: broadcast to all iterations when inside a rep group.
  for (const [name, newVal] of scalarsArr) {
    const repGroupName = repGroupForCapture.get(name);
    if (repGroupName) {
      const { outerSpan, iterSpans } = collectIterSpans(name, repGroupName);
      if (outerSpan !== undefined) {
        patches.push({ absStart: outerSpan[0], absEnd: outerSpan[1], newVal });
      }
      for (const span of iterSpans) {
        patches.push({ absStart: span[0], absEnd: span[1], newVal });
      }
    } else {
      const span = groupIndices[name];
      if (span !== undefined) {
        patches.push({ absStart: span[0], absEnd: span[1], newVal });
      }
    }
  }

  // Array replacements: two-pass per iteration, with length mismatch detection.
  for (const [name, valsGleam] of arraysArr) {
    const vals = gleam_list_to_array(valsGleam);
    const repGroupName = repGroupForCapture.get(name);
    if (!repGroupName) continue;

    const repSpan = groupIndices[repGroupName];
    if (repSpan === undefined) continue;

    const { outerSpan, iterSpans } = collectIterSpans(name, repGroupName);
    const arrayOffset = outerSpan !== undefined ? 1 : 0;
    if (outerSpan !== undefined) {
      patches.push({ absStart: outerSpan[0], absEnd: outerSpan[1], newVal: vals[0] });
    }

    const k = iterSpans.length;
    const provided = vals.length - arrayOffset;
    if (provided !== k) {
      mismatches.push([name, vals.length, k + arrayOffset]);
      continue;
    }

    for (let i = 0; i < k; i++) {
      patches.push({ absStart: iterSpans[i][0], absEnd: iterSpans[i][1], newVal: vals[arrayOffset + i] });
    }
  }

  // Apply patches right-to-left within the match text.
  patches.sort((a, b) => b.absStart - a.absStart);
  let matchText = m[0];
  for (const { absStart, absEnd, newVal } of patches) {
    const rel0 = absStart - matchStart;
    const rel1 = absEnd - matchStart;
    matchText = matchText.slice(0, rel0) + newVal + matchText.slice(rel1);
  }
  return { result: matchText, mismatches };
}

// Replace the first match, or return Ok(input) if no match.
// Returns Ok(String) or Error(List(#(String, Int, Int))) on array length mismatch.
export function replace_regex_rich_with_arrays(regex, input, scalarsGleam, arraysGleam, repInfoGleam, flags) {
  regex.lastIndex = 0;
  const m = regex.exec(input);
  if (m === null) return new Ok(input);
  const { result: newText, mismatches } = apply_capture_replacements_with_arrays(
    m, input,
    gleam_list_to_array(scalarsGleam),
    gleam_list_to_array(arraysGleam),
    gleam_list_to_array(repInfoGleam),
    flags,
  );
  if (mismatches.length > 0) return new Error(toList(mismatches));
  return new Ok(input.slice(0, m.index) + newText + input.slice(m.index + m[0].length));
}

// Replace the next match at or after startIndex, or return Ok(input) if no match.
export function replace_regex_from_rich_with_arrays(regex, input, startIndex, scalarsGleam, arraysGleam, repInfoGleam, flags) {
  regex.lastIndex = startIndex;
  const m = regex.exec(input);
  if (m === null) return new Ok(input);
  const { result: newText, mismatches } = apply_capture_replacements_with_arrays(
    m, input,
    gleam_list_to_array(scalarsGleam),
    gleam_list_to_array(arraysGleam),
    gleam_list_to_array(repInfoGleam),
    flags,
  );
  if (mismatches.length > 0) return new Error(toList(mismatches));
  return new Ok(input.slice(0, m.index) + newText + input.slice(m.index + m[0].length));
}

// Replace all matches. Requires the 'g' flag on the regex.
// Returns Ok(String) or Error(List(#(String, Int, Int))) on first array length mismatch.
export function replace_all_regex_rich_with_arrays(regex, input, scalarsGleam, arraysGleam, repInfoGleam, flags) {
  regex.lastIndex = 0;
  const scalarsArr = gleam_list_to_array(scalarsGleam);
  const arraysArr = gleam_list_to_array(arraysGleam);
  const repInfoArr = gleam_list_to_array(repInfoGleam);
  const parts = [];
  let lastEnd = 0;
  let m;
  while ((m = regex.exec(input)) !== null) {
    parts.push(input.slice(lastEnd, m.index));
    const { result: newText, mismatches } = apply_capture_replacements_with_arrays(m, input, scalarsArr, arraysArr, repInfoArr, flags);
    if (mismatches.length > 0) return new Error(toList(mismatches));
    parts.push(newText);
    lastEnd = m.index + m[0].length;
    if (m[0].length === 0) regex.lastIndex++;
  }
  parts.push(input.slice(lastEnd));
  return new Ok(parts.join(""));
}

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
