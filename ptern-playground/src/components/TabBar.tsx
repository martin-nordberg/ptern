import { For, Show } from 'solid-js'
import { tabs, activeTab, setActiveTab, addTab, closeTab } from '../store'

export default function TabBar() {
  return (
    <div class="flex overflow-x-auto border-b-0" style="scrollbar-width: thin">
      <For each={tabs}>
        {(tab, i) => (
          <button
            type="button"
            onClick={() => setActiveTab(i())}
            class={[
              'relative flex items-center gap-1.5 px-3 py-1.5 border-l border-t border-r text-sm select-none whitespace-nowrap',
              'group',
              activeTab() === i()
                ? 'bg-stone-50 dark:bg-zinc-900 border-stone-300 dark:border-zinc-600 -mb-px z-10'
                : 'bg-stone-100 dark:bg-zinc-800 border-stone-200 dark:border-zinc-700 text-stone-500 dark:text-zinc-400 hover:bg-stone-50 dark:hover:bg-zinc-750',
            ].join(' ')}
          >
            <span>{tab.stale ? `${i() + 1}*` : String(i() + 1)}</span>
            <span
              role="button"
              aria-label="Close tab"
              onClick={e => { e.stopPropagation(); closeTab(i()) }}
              class={[
                'text-xs leading-none px-0.5',
                'opacity-0 group-hover:opacity-100 touch-action-auto',
                activeTab() === i() ? 'opacity-100' : '',
              ].join(' ')}
            >
              ×
            </span>
          </button>
        )}
      </For>
      <Show when={tabs.length < 20}>
        <button
          type="button"
          onClick={addTab}
          class="flex items-center px-3 py-1.5 border-l border-t border-r text-sm bg-stone-100 dark:bg-zinc-800 border-stone-200 dark:border-zinc-700 text-stone-500 dark:text-zinc-400 hover:bg-stone-50 dark:hover:bg-zinc-750 select-none whitespace-nowrap"
        >
          +
        </button>
      </Show>
    </div>
  )
}
