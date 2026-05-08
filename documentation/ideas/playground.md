# Feature: Ptern Playground

## Overview

A web-based interactive environment for testing Ptern patterns without writing outer code.

## Design Approach

* Deployment is client-side only, i.e. the playground runs entirely within the browser.
* The playground depends upon the transpiled JavaScript output from the Glean implementation
* Technologies:

  - SolidJS
  - TailwindCSS
  - Vite

## Screen Design

* Title area
* Text area to enter the Ptern pattern
* Copy button to easily copy the text area content to clipboard
* Output area to display compile errors or "OK"
* Format button to reformat the Ptern code
* "Format Options" button to set the format options in a modal dialog and save them in local storage
* Tabs for test cases with a "+" tab to add another
* Each tab:
  - Text area to enter the string to be matched
  - Labeled output results for all the matchesXyz methods (Yes/No)
  - Labeled output results for all the matchXyz methods for which matchesXyz is true (output in JSON format)
  - Text area to enter a JSON replacement value dictionary
  - Labeled output results for each replaceXyz variant for which matchesXyz is true
  - If the ptern is substitutable, an output area showing the substitution result