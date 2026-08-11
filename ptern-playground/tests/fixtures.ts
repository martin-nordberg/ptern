// Small helper for pulling real patterns and expected results out of the
// shared cross-language corpus at ../../test-fixtures/ instead of
// hand-inventing new ones. Keeps the E2E suite's expectations anchored to
// the same source of truth ptern-typescript's own 700+ engine tests use,
// rather than letting UI-level expectations drift independently.
//
// Only a subset of fixture shapes is modeled here — just enough for what
// these tests actually read. See test-fixtures/api/api.json and
// test-fixtures/api/compile.json for the full fixture format.

import { readFileSync } from 'node:fs'
import { join } from 'node:path'

const fixturesDir = join(import.meta.dirname, '../../test-fixtures')

export type ApiCase = {
  op: string
  input?: string
  startIndex?: number
  captures?: Record<string, unknown>
  replacements?: Record<string, unknown>
  expect: unknown
}

export type ApiFixture = {
  id: string
  pattern: string
  cases: ApiCase[]
}

export type CompileFixture = {
  id: string
  pattern: string
  expect: { error: 'lexError' | 'parseError' | 'semanticErrors' }
}

function load<T>(relPath: string): T[] {
  return JSON.parse(readFileSync(join(fixturesDir, relPath), 'utf-8')) as T[]
}

let apiFixtures: ApiFixture[] | null = null
let compileFixtures: CompileFixture[] | null = null

export function apiFixture(id: string): ApiFixture {
  apiFixtures ??= load<ApiFixture>('api/api.json')
  const found = apiFixtures.find(f => f.id === id)
  if (!found) throw new Error(`api fixture not found: ${id}`)
  return found
}

export function apiCase(fixtureId: string, op: string): ApiCase {
  const cases = apiFixture(fixtureId).cases.filter(c => c.op === op)
  const found = cases[0]
  if (!found) throw new Error(`no case with op '${op}' in fixture '${fixtureId}'`)
  return found
}

export function compileFixture(id: string): CompileFixture {
  compileFixtures ??= load<CompileFixture>('api/compile.json')
  const found = compileFixtures.find(f => f.id === id)
  if (!found) throw new Error(`compile fixture not found: ${id}`)
  return found
}
