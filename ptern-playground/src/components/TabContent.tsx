import { createSignal, For, Show } from 'solid-js'
import {
  matchesAllOf, matchesStartOf, matchesEndOf, matchesIn,
  matchAllOf, matchStartOf, matchEndOf, matchFirstIn, matchAllIn,
  replaceAllOf, replaceStartOf, replaceEndOf, replaceFirstIn, replaceAllIn,
  substitute, isSubstitutable,
  type Ptern, type MatchOccurrence, type ReplacementError, type SubstitutionError, type CaptureInput,
} from '../ptern/api'
import { tabs, activeTab, updateTabField, setTabMode, markTabTested, compileResult } from '../store'

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function parseCaptureValues(raw: string): { ok: true; values: CaptureInput } | { ok: false; error: string } {
  const trimmed = raw.trim()
  if (trimmed === '') return { ok: true, values: {} }
  try {
    const parsed = JSON.parse(trimmed)
    if (typeof parsed !== 'object' || parsed === null || Array.isArray(parsed)) {
      return { ok: false, error: 'Expected a JSON object' }
    }
    return { ok: true, values: parsed as CaptureInput }
  } catch (e) {
    return { ok: false, error: (e as Error).message }
  }
}

function formatReplacementError(err: ReplacementError): string {
  switch (err.kind) {
    case 'invalid': return `InvalidReplacementValue: '${err.captureName}' = ${JSON.stringify(err.value)}`
    case 'wrongType': return `WrongReplacementType: '${err.captureName}'`
    case 'lengthMismatch': return `ArrayLengthMismatch: '${err.captureName}' (provided ${err.provided}, need ${err.actual})`
    case 'duplicateRepetition': return `DuplicateRepetitionCapture: '${err.captureName}'`
  }
}

function formatSubstitutionError(err: SubstitutionError): string {
  switch (err.kind) {
    case 'notSubstitutable': return 'NotSubstitutable'
    case 'missing': return `Missing capture: ${err.name}`
    case 'mismatch': return `Value does not match pattern for: ${err.name}`
    case 'lengthError': return `Wrong array length for: ${err.name} (got ${err.length}, need ${err.min}–${err.max})`
    case 'noMatchingBranch': return 'No alternation branch matched'
  }
}

function occurrenceDisplay(occ: MatchOccurrence, input: string): string {
  const matched = JSON.stringify(input.slice(occ.index, occ.index + occ.length))
  const keys = Object.keys(occ.captures)
  if (keys.length === 0) return matched
  const caps = JSON.stringify(occ.captures)
  return `${matched}  ${caps}`
}

// ---------------------------------------------------------------------------
// Sub-components
// ---------------------------------------------------------------------------

function MatchBadges(props: { ptern: Ptern; input: string; stale: boolean }) {
  const results = () => ({
    all: matchesAllOf(props.ptern, props.input),
    start: matchesStartOf(props.ptern, props.input),
    end: matchesEndOf(props.ptern, props.input),
    inStr: matchesIn(props.ptern, props.input),
  })

  const muted = () => props.stale

  return (
    <div>
      <div class="flex flex-wrap gap-3 mb-3">
        <For each={[
          { label: 'Matches all', key: 'all' as const },
          { label: 'Matches start', key: 'start' as const },
          { label: 'Matches end', key: 'end' as const },
          { label: 'Matches in', key: 'inStr' as const },
        ]}>
          {(item) => {
            const val = () => results()[item.key]
            return (
              <div class={muted() ? 'text-stone-400 dark:text-zinc-500' : ''}>
                <div class="text-xs text-stone-500 dark:text-zinc-400 mb-0.5">{item.label}</div>
                <span class={[
                  'inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-xs font-medium border',
                  muted()
                    ? 'border-stone-200 dark:border-zinc-700'
                    : val()
                      ? 'border-green-200 dark:border-green-800 text-green-700 dark:text-green-400'
                      : 'border-red-200 dark:border-red-800 text-red-600 dark:text-red-400',
                ].join(' ')}>
                  {val() ? '✓ Yes' : '✗ No'}
                </span>
              </div>
            )
          }}
        </For>
      </div>

      {/* Occurrence results */}
      <div class="space-y-2">
        <For each={[
          { cond: () => results().all, label: 'Match (all)', fn: () => matchAllOf(props.ptern, props.input), single: true },
          { cond: () => results().start, label: 'Match (start)', fn: () => matchStartOf(props.ptern, props.input), single: true },
          { cond: () => results().end, label: 'Match (end)', fn: () => matchEndOf(props.ptern, props.input), single: true },
          { cond: () => results().inStr, label: 'First match', fn: () => matchFirstIn(props.ptern, props.input), single: true },
          { cond: () => results().inStr, label: 'All matches', fn: () => matchAllIn(props.ptern, props.input) as MatchOccurrence[], single: false },
        ]}>
          {(item) => (
            <Show when={item.cond()}>
              <div class={muted() ? 'opacity-50' : ''}>
                <div class="text-xs text-stone-500 dark:text-zinc-400 mb-0.5">{item.label}</div>
                <div class="font-mono text-xs bg-stone-100 dark:bg-zinc-800 border border-stone-200 dark:border-zinc-700 rounded px-2 py-1 overflow-x-auto whitespace-pre">
                  {item.single
                    ? (() => {
                        const occ = (item.fn as () => MatchOccurrence | null)()
                        return occ ? occurrenceDisplay(occ, props.input) : ''
                      })()
                    : (() => {
                        const occs = (item.fn as () => MatchOccurrence[])()
                        return occs.map(o => occurrenceDisplay(o, props.input)).join('\n')
                      })()
                  }
                </div>
              </div>
            </Show>
          )}
        </For>
      </div>
    </div>
  )
}

function ReplacementResults(props: { ptern: Ptern; input: string; captures: CaptureInput; stale: boolean }) {
  const results = () => ({
    all: matchesAllOf(props.ptern, props.input),
    start: matchesStartOf(props.ptern, props.input),
    end: matchesEndOf(props.ptern, props.input),
    inStr: matchesIn(props.ptern, props.input),
  })

  const muted = () => props.stale

  return (
    <div class="space-y-2">
      <For each={[
        { cond: () => results().all, label: 'Replace (all)', fn: () => replaceAllOf(props.ptern, props.input, props.captures) },
        { cond: () => results().start, label: 'Replace (start)', fn: () => replaceStartOf(props.ptern, props.input, props.captures) },
        { cond: () => results().end, label: 'Replace (end)', fn: () => replaceEndOf(props.ptern, props.input, props.captures) },
        { cond: () => results().inStr, label: 'Replace (first)', fn: () => replaceFirstIn(props.ptern, props.input, props.captures) },
        { cond: () => results().inStr, label: 'Replace (all in)', fn: () => replaceAllIn(props.ptern, props.input, props.captures) },
      ]}>
        {(item) => (
          <Show when={item.cond()}>
            <div class={muted() ? 'opacity-50' : ''}>
              <div class="text-xs text-stone-500 dark:text-zinc-400 mb-0.5">{item.label}</div>
              {(() => {
                const r = item.fn()
                return typeof r === 'string'
                  ? <div class="font-mono text-xs bg-stone-100 dark:bg-zinc-800 border border-stone-200 dark:border-zinc-700 rounded px-2 py-1 overflow-x-auto">{r}</div>
                  : <div class="text-red-600 dark:text-red-400 text-xs">{formatReplacementError(r)}</div>
              })()}
            </div>
          </Show>
        )}
      </For>
    </div>
  )
}

// ---------------------------------------------------------------------------
// Main TabContent
// ---------------------------------------------------------------------------

export default function TabContent() {
  const i = activeTab
  const tab = () => tabs[i()]
  const cr = compileResult

  const ptern = () => (cr()?.ok ? (cr() as { ok: true; ptern: Ptern }).ptern : null)
  const canTest = () => ptern() !== null
  const subAvailable = () => ptern() !== null && isSubstitutable(ptern()!)

  const capturesParsed = () => parseCaptureValues(tab().captureValues)

  function handleTest() {
    if (!canTest()) return
    markTabTested(i())
  }

  const [testedSnapshot, setTestedSnapshot] = createSignal<{
    input: string
    captures: CaptureInput
    ptern: Ptern
  } | null>(null)

  function doTest() {
    if (!ptern()) return
    setTestedSnapshot({ input: tab().input, captures: capturesParsed().ok ? (capturesParsed() as { ok: true; values: CaptureInput }).values : {}, ptern: ptern()! })
    handleTest()
  }

  return (
    <div class="p-3 space-y-3">
      {/* Mode toggle */}
      <div class="flex rounded-full border border-stone-300 dark:border-zinc-600 overflow-hidden w-fit text-xs">
        <button
          type="button"
          onClick={() => setTabMode(i(), 'match-replace')}
          class={[
            'px-3 py-1',
            tab().mode === 'match-replace'
              ? 'bg-stone-700 dark:bg-zinc-300 text-white dark:text-zinc-900'
              : 'hover:bg-stone-100 dark:hover:bg-zinc-700',
          ].join(' ')}
        >
          Match / Replace
        </button>
        <button
          type="button"
          onClick={() => subAvailable() && setTabMode(i(), 'substitution')}
          disabled={!subAvailable()}
          class={[
            'px-3 py-1',
            tab().mode === 'substitution'
              ? 'bg-stone-700 dark:bg-zinc-300 text-white dark:text-zinc-900'
              : 'hover:bg-stone-100 dark:hover:bg-zinc-700',
            !subAvailable() ? 'opacity-40 cursor-not-allowed' : '',
          ].join(' ')}
        >
          Substitution
        </button>
      </div>

      {/* Match/Replace mode */}
      <Show when={tab().mode === 'match-replace'}>
        <div class="space-y-2">
          <div>
            <label class="text-xs text-stone-500 dark:text-zinc-400 block mb-0.5">Input string</label>
            <textarea
              value={tab().input}
              onInput={e => updateTabField(i(), 'input', e.currentTarget.value)}
              class="w-full font-mono text-xs border border-stone-300 dark:border-zinc-600 rounded bg-white dark:bg-zinc-800 p-2 resize-y min-h-[60px] focus:outline-none focus:ring-1 focus:ring-stone-400 dark:focus:ring-zinc-500"
              spellcheck={false}
            />
          </div>
          <div>
            <label class="text-xs text-stone-500 dark:text-zinc-400 block mb-0.5">Capture values (JSON)</label>
            <textarea
              value={tab().captureValues}
              onInput={e => updateTabField(i(), 'captureValues', e.currentTarget.value)}
              class="w-full font-mono text-xs border border-stone-300 dark:border-zinc-600 rounded bg-white dark:bg-zinc-800 p-2 resize-y min-h-[60px] focus:outline-none focus:ring-1 focus:ring-stone-400 dark:focus:ring-zinc-500"
              spellcheck={false}
            />
            <Show when={!capturesParsed().ok && tab().captureValues.trim() !== ''}>
              <div class="text-red-600 dark:text-red-400 text-xs mt-0.5">
                JSON error: {!capturesParsed().ok && (capturesParsed() as { ok: false; error: string }).error}
              </div>
            </Show>
          </div>
          <button
            type="button"
            onClick={doTest}
            disabled={!canTest()}
            class="px-3 py-1 rounded border border-stone-300 dark:border-zinc-600 hover:bg-stone-100 dark:hover:bg-zinc-700 disabled:opacity-40 disabled:cursor-not-allowed text-sm"
          >
            Test
          </button>
        </div>

        {/* Results */}
        <Show
          when={testedSnapshot() !== null && tab().tested}
          fallback={
            <div class="text-stone-400 dark:text-zinc-500 text-xs italic">Click Test to see results.</div>
          }
        >
          <div class={tab().stale ? 'opacity-50' : ''}>
            <MatchBadges ptern={testedSnapshot()!.ptern} input={testedSnapshot()!.input} stale={false} />
            <Show when={capturesParsed().ok || testedSnapshot()!.captures !== null}>
              <div class="mt-3">
                <ReplacementResults
                  ptern={testedSnapshot()!.ptern}
                  input={testedSnapshot()!.input}
                  captures={testedSnapshot()!.captures}
                  stale={false}
                />
              </div>
            </Show>
          </div>
        </Show>
      </Show>

      {/* Substitution mode */}
      <Show when={tab().mode === 'substitution'}>
        <div class="space-y-2">
          <div>
            <label class="text-xs text-stone-500 dark:text-zinc-400 block mb-0.5">Capture values (JSON)</label>
            <textarea
              value={tab().captureValues}
              onInput={e => updateTabField(i(), 'captureValues', e.currentTarget.value)}
              class="w-full font-mono text-xs border border-stone-300 dark:border-zinc-600 rounded bg-white dark:bg-zinc-800 p-2 resize-y min-h-[80px] focus:outline-none focus:ring-1 focus:ring-stone-400 dark:focus:ring-zinc-500"
              spellcheck={false}
            />
            <Show when={!capturesParsed().ok && tab().captureValues.trim() !== ''}>
              <div class="text-red-600 dark:text-red-400 text-xs mt-0.5">
                JSON error: {!capturesParsed().ok && (capturesParsed() as { ok: false; error: string }).error}
              </div>
            </Show>
          </div>
          <button
            type="button"
            onClick={doTest}
            disabled={!canTest()}
            class="px-3 py-1 rounded border border-stone-300 dark:border-zinc-600 hover:bg-stone-100 dark:hover:bg-zinc-700 disabled:opacity-40 disabled:cursor-not-allowed text-sm"
          >
            Test
          </button>
        </div>

        <Show
          when={testedSnapshot() !== null && tab().tested}
          fallback={
            <div class="text-stone-400 dark:text-zinc-500 text-xs italic">Click Test to see results.</div>
          }
        >
          {(() => {
            const snap = testedSnapshot()!
            const result = substitute(snap.ptern, snap.captures)
            return (
              <div class={tab().stale ? 'opacity-50' : ''}>
                <div class="text-xs text-stone-500 dark:text-zinc-400 mb-0.5">Result</div>
                {typeof result === 'string'
                  ? <div class="font-mono text-xs bg-stone-100 dark:bg-zinc-800 border border-stone-200 dark:border-zinc-700 rounded px-2 py-1 overflow-x-auto">{result}</div>
                  : <div class="text-red-600 dark:text-red-400 text-xs">{formatSubstitutionError(result)}</div>
                }
              </div>
            )
          })()}
        </Show>
      </Show>
    </div>
  )
}
