import { createSignal, onCleanup, onMount } from 'solid-js'
import type { FormatOptions } from '../ptern/api'

type Props = {
  options: FormatOptions
  onSave: (opts: FormatOptions) => void
  onClose: () => void
}

export default function FormatOptionsModal(props: Props) {
  const [aligned, setAligned] = createSignal(props.options.aligned)
  const [compact, setCompact] = createSignal(props.options.compact)
  const [lineWidth, setLineWidth] = createSignal(props.options.lineWidth)
  const [reordered, setReordered] = createSignal(props.options.reordered)

  function handleSave() {
    props.onSave({ aligned: aligned(), compact: compact(), lineWidth: lineWidth(), reordered: reordered() })
  }

  function handleKey(e: KeyboardEvent) {
    if (e.key === 'Escape') props.onClose()
  }

  onMount(() => document.addEventListener('keydown', handleKey))
  onCleanup(() => document.removeEventListener('keydown', handleKey))

  return (
    <div class="fixed inset-0 z-50 flex items-center justify-center">
      <div class="absolute inset-0 bg-black/30 dark:bg-black/50" />
      <div class="relative bg-stone-50 dark:bg-zinc-800 border border-stone-200 dark:border-zinc-600 rounded-md shadow-lg p-4 w-72">
        <h2 class="font-semibold mb-3 text-stone-900 dark:text-zinc-100">Format Options</h2>
        <div class="space-y-2">
          <label class="flex items-center gap-2 cursor-pointer">
            <input type="checkbox" checked={aligned()} onChange={e => setAligned(e.currentTarget.checked)} />
            <span>Aligned</span>
          </label>
          <label class="flex items-center gap-2 cursor-pointer">
            <input type="checkbox" checked={compact()} onChange={e => setCompact(e.currentTarget.checked)} />
            <span>Compact</span>
          </label>
          <label class="flex items-center gap-2 cursor-pointer">
            <input type="checkbox" checked={reordered()} onChange={e => setReordered(e.currentTarget.checked)} />
            <span>Reordered</span>
          </label>
          <label class="flex items-center gap-2">
            <span>Line width</span>
            <input
              type="number"
              min={40}
              value={lineWidth()}
              onInput={e => setLineWidth(Math.max(40, parseInt(e.currentTarget.value) || 40))}
              class="w-20 border border-stone-300 dark:border-zinc-600 rounded px-2 py-0.5 bg-white dark:bg-zinc-700 font-mono"
            />
          </label>
        </div>
        <div class="flex gap-2 mt-4 justify-end">
          <button
            type="button"
            onClick={props.onClose}
            class="px-3 py-1 rounded border border-stone-300 dark:border-zinc-600 hover:bg-stone-100 dark:hover:bg-zinc-700"
          >
            Cancel
          </button>
          <button
            type="button"
            onClick={handleSave}
            class="px-3 py-1 rounded bg-stone-700 dark:bg-zinc-300 text-stone-50 dark:text-zinc-900 hover:bg-stone-800 dark:hover:bg-zinc-200"
          >
            Save
          </button>
        </div>
      </div>
    </div>
  )
}
