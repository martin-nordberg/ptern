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
