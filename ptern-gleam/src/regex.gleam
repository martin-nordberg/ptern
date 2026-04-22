import gleam/option.{type Option}

pub type Regex

@external(javascript, "./ptern_ffi.mjs", "make_regex")
pub fn make(source: String, flags: String) -> Regex

@external(javascript, "./ptern_ffi.mjs", "test_regex")
pub fn test_re(regex: Regex, input: String) -> Bool

@external(javascript, "./ptern_ffi.mjs", "exec_regex")
pub fn exec(regex: Regex, input: String) -> Option(List(#(String, String)))
