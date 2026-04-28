# "Ptern"

Martin Nordberg - 2026-04-04

## What's With the Name?

"PT+ERN" is a "backandforthronym":

* _Backwards_ - *(NRET+P){2}* - *N*ormal *R*egular *E*xpressions *T*ranslate *T*o *T*wo *P*roblems:
*N*otoriously, *R*egular *E*xpressions are *T*hemselves *T*iresomely *T*erse *P*uzzles.[^joke]
* _Forwards_ - *PT+ERN* - *P*attern *T*ext *T*ranslated *T*o *E*asily *R*eadable *N*otation.

[^joke]: Classic computer science joke: "I had a problem. I solved it with a regular expression.
Now I have two problems."

Or, if you prefer a recursive acronym:

* *PT+ERN* - *P*tern's a *T*ext *T*ranslation *T*ool *T*hat *E*nables *R*eading *N*aturally

And note that "ptern" (we pronounce it "turn") could be an out-of-the-ordinary abbreviation
for the word "pattern".

Enough fluff! Show me...

## Ptern By Example

Here is an example Ptern string matching pattern (just a "ptern" from now on):

```
yyyy = %Digit * 4;
mm = '0' '1'..'9' | '1' '0'..'2';
dd = '0' '1'..'9' | '1'..'2' %Digit | '3' '0'..'1';
{yyyy} as year '-' {mm} as month '-' {dd} as day
```

It is way more verbose than the corresponding regular expression, but it is also far more readable.
We think that's true even if you haven't yet learned the Ptern grammar.

Here's how that example ptern can be put to use with the Gleam API:

```gleam
import gleam/dict
import ptern

let assert Ok(iso_date) = ptern.compile("
  yyyy = %Digit * 4;
  mm = '0' '1'..'9' | '1' '0'..'2';
  dd = '0' '1'..'9' | '1'..'2' %Digit | '3' '0'..'1';
  {yyyy} as year '-' {mm} as month '-' {dd} as day
")

ptern.matches_all_of(iso_date, "2026-07-04")                        // True
ptern.matches_start_of(iso_date, "2026-07-04T12:00")                // True
ptern.matches_end_of(iso_date, "Independence Day is 2026-07-04")    // True
ptern.matches_in(iso_date, "Independence Day 2026-07-04 - the 250th")  // True

ptern.match_all_of(iso_date, "2026-07-04")
// Some(MatchOccurrence(index: 0, length: 10, captures: ...))

ptern.match_first_in(iso_date, "Independence Day 2026-07-04 - the 250th")
// Some(MatchOccurrence(index: 17, length: 10, captures: ...))

ptern.match_all_in(iso_date, "2026-07-04 and 2026-12-25")
// [MatchOccurrence(index: 0, ...), MatchOccurrence(index: 15, ...)]

ptern.replace_first_in(iso_date, "Independence Day 2026-07-04 - the 250th",
  dict.from_list([#("year", ptern.ScalarReplacement("2027"))]))
// Ok("Independence Day 2027-07-04 - the 250th")

ptern.replace_all_in(iso_date, "2026-07-04 and 2026-12-25",
  dict.from_list([#("year", ptern.ScalarReplacement("2027"))]))
// Ok("2027-07-04 and 2027-12-25")
```

A ptern also offers metadata about the pattern itself:

```gleam
ptern.max_length(iso_date)   // Some(10)
ptern.min_length(iso_date)   // 10
```


## Language Support

Ptern is designed to be language-independent. The pattern language and its grammar are fully defined in this document; each language binding wraps the same compiled core.

### Gleam

```gleam
import ptern

let assert Ok(iso_date) = ptern.compile("
  yyyy = %Digit * 4;
  mm = '0' '1'..'9' | '1' '0'..'2';
  dd = '0' '1'..'9' | '1'..'2' %Digit | '3' '0'..'1';
  {yyyy} as year '-' {mm} as month '-' {dd} as day
")

ptern.matches_all_of(iso_date, "2026-07-04")   // True
ptern.match_all_of(iso_date, "2026-07-04")     // Some(MatchOccurrence(index: 0, length: 10, captures: ...))
ptern.max_length(iso_date)                     // Some(10)
```

See `ptern-gleam/doc/user-guide.md` for the full Gleam API reference.

*Additional language bindings are planned.*

