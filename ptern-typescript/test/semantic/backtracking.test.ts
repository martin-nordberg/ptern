import { describe, expect, it } from "bun:test";
import { compile, PternCompileError } from "../../src/index";
import type { SemanticError } from "../../src/semantic/error";

function hasSemanticError(
  result: ReturnType<typeof compile>,
  target: SemanticError,
): boolean {
  try {
    result;
    return false;
  } catch (e) {
    if (e instanceof PternCompileError && e.compileError.kind === "semanticErrors") {
      return e.compileError.errors.some(
        err => JSON.stringify(err) === JSON.stringify(target),
      );
    }
    return false;
  }
}

function compileExpectingError(src: string, target: SemanticError): boolean {
  try {
    compile(src);
    return false;
  } catch (e) {
    if (e instanceof PternCompileError && e.compileError.kind === "semanticErrors") {
      return e.compileError.errors.some(
        err => JSON.stringify(err) === JSON.stringify(target),
      );
    }
    return false;
  }
}

function compileOk(src: string): boolean {
  try {
    compile(src);
    return true;
  } catch {
    return false;
  }
}

// ---------------------------------------------------------------------------
// Check 1: AmbiguousRepetitionAdjacency — pairwise branches of a variable-count
// repetition whose last/first charsets overlap.
// ---------------------------------------------------------------------------

describe("Check 1: AmbiguousRepetitionAdjacency", () => {
  it("disjoint %Digit and %Alpha branches — no error", () => {
    expect(compileOk("(%Digit | %Alpha) * 1..?")).toBe(true);
  });

  it("overlapping literal branches 'a' and 'ab'", () => {
    expect(compileExpectingError(
      "('a' | 'ab') * 1..?",
      { kind: "ambiguousRepetitionAdjacency", branchA: "'a'", branchB: "'ab'" },
    )).toBe(true);
  });

  it("same class branches overlap", () => {
    expect(compileExpectingError(
      "(%Digit | %Digit) * 1..?",
      { kind: "ambiguousRepetitionAdjacency", branchA: "%Digit", branchB: "%Digit" },
    )).toBe(true);
  });

  it("exact count (* 3) does not trigger check", () => {
    expect(compileOk("('a' | 'b') * 3")).toBe(true);
  });

  it("%Upper and %Lower are disjoint", () => {
    expect(compileOk("(%Upper | %Lower) * 1..?")).toBe(true);
  });

  it("%Alpha and underscore are disjoint", () => {
    expect(compileOk("(%Alpha | '_') * 1..?")).toBe(true);
  });

  it("%L and %N are disjoint", () => {
    expect(compileOk("(%L | %N) * 1..?")).toBe(true);
  });

  it("multi-char literal last/first overlap 'xy' and 'yz'", () => {
    expect(compileExpectingError(
      "('xy' | 'yz') * 1..?",
      { kind: "ambiguousRepetitionAdjacency", branchA: "'xy'", branchB: "'yz'" },
    )).toBe(true);
  });

  it("multi-char literal no overlap 'ab' and 'cd'", () => {
    expect(compileOk("('ab' | 'cd') * 1..?")).toBe(true);
  });

  it("excl set covers excluded char — disjoint", () => {
    expect(compileOk("(%Alpha excluding 'a' | 'a') * 1..?")).toBe(true);
  });

  it("three branches — one overlapping pair still reported", () => {
    expect(compileExpectingError(
      "('a' | 'b' | 'ab') * 1..?",
      { kind: "ambiguousRepetitionAdjacency", branchA: "'a'", branchB: "'ab'" },
    )).toBe(true);
  });

  it("bounded variable range * 2..5 triggers check", () => {
    expect(compileExpectingError(
      "('a' | 'ab') * 2..5",
      { kind: "ambiguousRepetitionAdjacency", branchA: "'a'", branchB: "'ab'" },
    )).toBe(true);
  });
});

// ---------------------------------------------------------------------------
// Check 2: AmbiguousRepetitionBody — body is variable-length and last/first
// charsets of the body overlap across iterations.
// ---------------------------------------------------------------------------

describe("Check 2: AmbiguousRepetitionBody", () => {
  it("variable body with same class — error", () => {
    expect(compileExpectingError(
      "(%Alpha * 1..?) * 1..?",
      { kind: "ambiguousRepetitionBody" },
    )).toBe(true);
  });

  it("disjoint endpoints — no error", () => {
    expect(compileOk("('x' %Digit * 1..?) * 1..?")).toBe(true);
  });

  it("fixed-length body — no error", () => {
    expect(compileOk("(%Digit) * 1..?")).toBe(true);
  });

  it("variable-length alternation body — error", () => {
    expect(compileExpectingError(
      "((%L | %N | '_') * 1..?) * 1..?",
      { kind: "ambiguousRepetitionBody" },
    )).toBe(true);
  });

  it("excl body overlaps itself — error", () => {
    expect(compileExpectingError(
      "((%Any excluding ',') * 1..?) * 1..?",
      { kind: "ambiguousRepetitionBody" },
    )).toBe(true);
  });

  it("separator makes excl body safe — no error", () => {
    expect(compileOk("(',' (%Any excluding ',') * 1..?) * 1..?")).toBe(true);
  });

  it("nullable inner rep — error", () => {
    expect(compileExpectingError(
      "(%Digit * 0..?) * 1..?",
      { kind: "ambiguousRepetitionBody" },
    )).toBe(true);
  });
});

// ---------------------------------------------------------------------------
// Check 4: AmbiguousAdjacentRepetition — two consecutive unbounded repetitions
// whose last/first charsets overlap.
// ---------------------------------------------------------------------------

describe("Check 4: AmbiguousAdjacentRepetition", () => {
  it("adjacent same class — error", () => {
    expect(compileExpectingError(
      "%Digit * 1..? %Digit * 1..?",
      { kind: "ambiguousAdjacentRepetition" },
    )).toBe(true);
  });

  it("adjacent disjoint classes — no error", () => {
    expect(compileOk("%Upper * 1..? %Lower * 1..?")).toBe(true);
  });

  it("literal separator prevents adjacent error", () => {
    expect(compileOk("%Digit * 1..? '-' %Digit * 1..?")).toBe(true);
  });

  it("bounded (* 1..5) not adjacent unbounded — no error", () => {
    expect(compileOk("%Alpha * 1..5 %Alpha * 1..?")).toBe(true);
  });

  it("excl class makes adjacent reps disjoint", () => {
    expect(compileOk("%Digit * 1..? (%Any excluding %Digit) * 1..?")).toBe(true);
  });

  it("zero lower bound is still unbounded — error", () => {
    expect(compileExpectingError(
      "%Alpha * 0..? %Alpha * 1..?",
      { kind: "ambiguousAdjacentRepetition" },
    )).toBe(true);
  });
});

// ---------------------------------------------------------------------------
// !allow-backtracking = true — global opt-out
// ---------------------------------------------------------------------------

describe("!allow-backtracking opt-out", () => {
  it("allow-backtracking suppresses all checks", () => {
    expect(compileOk("!allow-backtracking = true\n(%Alpha * 1..?) * 1..? %Alpha * 1..?")).toBe(true);
  });

  it("allow-backtracking = false still checks", () => {
    expect(compileExpectingError(
      "!allow-backtracking = false\n(%Alpha * 1..?) * 1..?",
      { kind: "ambiguousRepetitionBody" },
    )).toBe(true);
  });
});

// ---------------------------------------------------------------------------
// Backreferences — charset and fixed-length modelling
// ---------------------------------------------------------------------------

describe("backreferences in backtracking checks", () => {
  it("backreference at top level — no error", () => {
    expect(compileOk("%Alpha * 1..? as word '-' {word}")).toBe(true);
  });

  it("fixed-length body with backreference — no Check 2", () => {
    expect(compileOk("(%Alpha as c {c}) * 1..?")).toBe(true);
  });

  it("backreference adjacent to disjoint class — no error", () => {
    expect(compileOk("%Alpha * 1..? as n ' ' {n}")).toBe(true);
  });

  it("backreference with same class in unbounded rep — error", () => {
    expect(compileExpectingError(
      "%Alpha * 1..? as w {w} * 1..?",
      { kind: "ambiguousAdjacentRepetition" },
    )).toBe(true);
  });
});
