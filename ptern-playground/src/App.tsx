import { createEffect } from 'solid-js'
import EditorPanel from './components/EditorPanel'
import TestPanel from './components/TestPanel'
import { source, markAllTabsStale, theme, toggleTheme } from './store'

export default function App() {
  // Mark tabs stale whenever source changes (after initial mount)
  let firstRun = true
  createEffect(() => {
    source() // subscribe
    if (firstRun) { firstRun = false; return }
    markAllTabsStale()
  })

  return (
    <div class="min-h-screen font-sans text-sm bg-stone-50 text-stone-800 dark:bg-zinc-900 dark:text-zinc-200">
      <header class="flex items-center justify-between px-3 py-2 border-b border-stone-200 dark:border-zinc-700">
        <span class="font-semibold text-stone-900 dark:text-zinc-100">Ptern Playground</span>
        <button
          type="button"
          onClick={toggleTheme}
          class="text-lg leading-none px-2 py-1 rounded hover:bg-stone-100 dark:hover:bg-zinc-800 transition-colors"
          title={theme() === 'dark' ? 'Switch to light mode' : 'Switch to dark mode'}
        >
          {theme() === 'dark' ? '☀' : '☽'}
        </button>
      </header>

      <div class="2xl:flex 2xl:gap-3 2xl:p-3 2xl:items-start">
        {/* Left/top panel */}
        <div class="2xl:w-1/2 2xl:sticky 2xl:top-3">
          <EditorPanel />
        </div>
        {/* Right/bottom panel */}
        <div class="2xl:w-1/2">
          <TestPanel />
        </div>
      </div>
    </div>
  )
}
