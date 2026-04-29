import gleam/option.{type Option}

pub type Regex

@external(javascript, "./ptern_ffi.mjs", "make_regex")
pub fn make(source: String, flags: String) -> Regex

@external(javascript, "./ptern_ffi.mjs", "test_regex")
pub fn test_re(regex: Regex, input: String) -> Bool

@external(javascript, "./ptern_ffi.mjs", "exec_regex_rich")
pub fn exec_rich(
  regex: Regex,
  input: String,
) -> Option(#(Int, Int, List(#(String, String))))

@external(javascript, "./ptern_ffi.mjs", "exec_regex_from_rich")
pub fn exec_from_rich(
  regex: Regex,
  input: String,
  start_index: Int,
) -> Option(#(Int, Int, List(#(String, String))))

@external(javascript, "./ptern_ffi.mjs", "exec_all_regex_rich")
pub fn exec_all_rich(
  regex: Regex,
  input: String,
) -> List(#(Int, Int, List(#(String, String))))

@external(javascript, "./ptern_ffi.mjs", "replace_regex_rich")
pub fn replace_rich(
  regex: Regex,
  input: String,
  replacements: List(#(String, String)),
) -> String

@external(javascript, "./ptern_ffi.mjs", "replace_regex_from_rich")
pub fn replace_from_rich(
  regex: Regex,
  input: String,
  start_index: Int,
  replacements: List(#(String, String)),
) -> String

@external(javascript, "./ptern_ffi.mjs", "replace_all_regex_rich")
pub fn replace_all_rich(
  regex: Regex,
  input: String,
  replacements: List(#(String, String)),
) -> String

// Variants that accept both scalar and array replacements, plus repetition info
// for the two-pass per-iteration span extraction.
// Return Ok(String) or Error(List(#(String, Int, Int))) on array length mismatch.
@external(javascript, "./ptern_ffi.mjs", "replace_regex_rich_with_arrays")
pub fn replace_rich_with_arrays(
  regex: Regex,
  input: String,
  scalars: List(#(String, String)),
  arrays: List(#(String, List(String))),
  rep_info: List(#(String, String, List(String))),
  flags: String,
) -> Result(String, List(#(String, Int, Int)))

@external(javascript, "./ptern_ffi.mjs", "replace_regex_from_rich_with_arrays")
pub fn replace_from_rich_with_arrays(
  regex: Regex,
  input: String,
  start_index: Int,
  scalars: List(#(String, String)),
  arrays: List(#(String, List(String))),
  rep_info: List(#(String, String, List(String))),
  flags: String,
) -> Result(String, List(#(String, Int, Int)))

@external(javascript, "./ptern_ffi.mjs", "replace_all_regex_rich_with_arrays")
pub fn replace_all_rich_with_arrays(
  regex: Regex,
  input: String,
  scalars: List(#(String, String)),
  arrays: List(#(String, List(String))),
  rep_info: List(#(String, String, List(String))),
  flags: String,
) -> Result(String, List(#(String, Int, Int)))
