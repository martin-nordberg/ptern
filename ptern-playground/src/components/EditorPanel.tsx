import { createSignal, Show } from 'solid-js'
import { formatPtern, getMinLength, getMaxLength, getRegexSource, getRegexFlags, isSubstitutable, type FormatOptions } from '../ptern/api'
import {
  source, setSource, compileResult, formatOptions, setFormatOptions, persistState,
} from '../store'
import FormatOptionsModal from './FormatOptionsModal'

export default function EditorPanel() {
  const [showFormatModal, setShowFormatModal] = createSignal(false)
  const [copyLabel, setCopyLabel] = createSignal('Copy')

  const cr = compileResult

  function handleFormat() {
    const result = formatPtern(source(), { ...formatOptions })
    if (result !== null) setSource(result)
  }

  function handleCopy() {
    navigator.clipboard.writeText(source()).then(() => {
      setCopyLabel('Copied!')
      setTimeout(() => setCopyLabel('Copy'), 1500)
    })
  }

  function handleSaveFormatOptions(opts: FormatOptions) {
    setFormatOptions(opts)
    persistState()
    setShowFormatModal(false)
    const result = formatPtern(source(), opts)
    if (result !== null) setSource(result)
  }

  const canFormat = () => {
    const r = cr()
    if (r === null) return true
    return r.ok || r.error.kind === 'semantic'
  }

  return (
    <div class="flex flex-col p-3 gap-3 2xl:h-[calc(100dvh-3rem)]">
      {/* Source editor */}
      <textarea
        value={source()}
        onInput={e => setSource(e.currentTarget.value)}
        placeholder="Enter a ptern pattern…"
        class="flex-1 min-h-[180px] 2xl:min-h-0 w-full font-mono resize-y 2xl:resize-none border border-stone-300 dark:border-zinc-600 rounded bg-white dark:bg-zinc-800 p-2 focus:outline-none focus:ring-1 focus:ring-stone-400 dark:focus:ring-zinc-500"
        spellcheck={false}
      />

      {/* Compile status */}
      <div class="min-h-[1.25rem]">
        {(() => {
          const r = cr()
          if (!r) return null
          if (r.ok) return <div class="text-green-600 dark:text-green-400">Successful Compilation</div>
          const err = r.error
          const msg = err.kind === 'semantic' ? err.messages.join('\n') : err.message
          return <div class="text-red-600 dark:text-red-400 whitespace-pre-wrap">{msg}</div>
        })()}
      </div>

      {/* Button row */}
      <div class="flex gap-2">
        <button
          type="button"
          onClick={handleFormat}
          disabled={!canFormat()}
          class="px-3 py-1 rounded border border-stone-300 dark:border-zinc-600 hover:bg-stone-100 dark:hover:bg-zinc-700 disabled:opacity-40 disabled:cursor-not-allowed"
        >
          Format
        </button>
        <button
          type="button"
          onClick={() => setShowFormatModal(true)}
          class="px-3 py-1 rounded border border-stone-300 dark:border-zinc-600 hover:bg-stone-100 dark:hover:bg-zinc-700"
        >
          Format Options
        </button>
        <button
          type="button"
          onClick={handleCopy}
          class="px-3 py-1 rounded border border-stone-300 dark:border-zinc-600 hover:bg-stone-100 dark:hover:bg-zinc-700"
        >
          {copyLabel()}
        </button>
      </div>

      {/* Pattern metadata */}
      {(() => {
        const r = cr()
        if (!r?.ok) return null
        const p = r.ptern
        const maxLen = getMaxLength(p)
        return (
          <div class="space-y-2">
            <table class="text-sm border-collapse">
              <tbody>
                <tr>
                  <td class="pr-4 text-stone-500 dark:text-zinc-400">Min length</td>
                  <td class="font-mono">{getMinLength(p)}</td>
                </tr>
                <tr>
                  <td class="pr-4 text-stone-500 dark:text-zinc-400">Max length</td>
                  <td class="font-mono">{maxLen === null ? 'unbounded' : String(maxLen)}</td>
                </tr>
                <Show when={isSubstitutable(p)}>
                  <tr>
                    <td class="pr-4 text-stone-500 dark:text-zinc-400">Substitutable</td>
                    <td class="font-mono">yes</td>
                  </tr>
                </Show>
              </tbody>
            </table>
            <details class="text-sm">
              <summary class="cursor-pointer text-stone-500 dark:text-zinc-400 hover:text-stone-700 dark:hover:text-zinc-200 select-none">
                Show regex
              </summary>
              <div class="mt-1 font-mono overflow-x-auto border border-stone-200 dark:border-zinc-700 rounded bg-stone-100 dark:bg-zinc-800 p-2 text-xs">
                {`/${getRegexSource(p)}/${getRegexFlags(p)}`}
              </div>
            </details>
          </div>
        )
      })()}

      <Show when={showFormatModal()}>
        <FormatOptionsModal
          options={{ ...formatOptions }}
          onSave={handleSaveFormatOptions}
          onClose={() => setShowFormatModal(false)}
        />
      </Show>
    </div>
  )
}
