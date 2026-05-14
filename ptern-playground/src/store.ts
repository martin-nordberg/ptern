import { createMemo, createSignal } from 'solid-js'
import { createStore, produce } from 'solid-js/store'
import {
  compilePtern, getDefaultFormatOptions,
  type Ptern, type CompileError, type FormatOptions,
} from './ptern/api'

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export type TabMode = 'match-replace' | 'substitution'

export type TestTab = {
  mode: TabMode
  input: string
  captureValues: string
  tested: boolean
  stale: boolean
}

type StorageState = {
  version: number
  source: string
  formatOptions: FormatOptions
  tabs: Array<{ mode: TabMode; input: string; captureValues: string }>
}

// ---------------------------------------------------------------------------
// Default values
// ---------------------------------------------------------------------------

const DEFAULT_SOURCE = "%Digit * 4 as year '-' %Digit * 2 as month '-' %Digit * 2 as day"

const DEFAULT_TAB: TestTab = { mode: 'match-replace', input: '', captureValues: '', tested: false, stale: false }

function freshTab(): TestTab { return { ...DEFAULT_TAB } }

const STORAGE_KEY = 'ptern-playground-state'
const THEME_KEY = 'ptern-playground-v1-theme'
const SCHEMA_VERSION = 1

// ---------------------------------------------------------------------------
// Load / save localStorage
// ---------------------------------------------------------------------------

function loadStoredState(): StorageState | null {
  try {
    const raw = localStorage.getItem(STORAGE_KEY)
    if (!raw) return null
    const parsed = JSON.parse(raw) as StorageState
    if (parsed.version !== SCHEMA_VERSION) return null
    return parsed
  } catch {
    return null
  }
}

function saveState(source: string, formatOptions: FormatOptions, tabs: TestTab[]): void {
  try {
    const payload: StorageState = {
      version: SCHEMA_VERSION,
      source,
      formatOptions,
      tabs: tabs.map(t => ({ mode: t.mode, input: t.input, captureValues: t.captureValues })),
    }
    localStorage.setItem(STORAGE_KEY, JSON.stringify(payload))
  } catch {
    // localStorage unavailable — silent
  }
}

function loadTheme(): 'light' | 'dark' {
  try {
    const v = localStorage.getItem(THEME_KEY)
    if (v === 'dark' || v === 'light') return v
  } catch { /* ignored */ }
  return 'light'
}

function saveTheme(theme: 'light' | 'dark'): void {
  try { localStorage.setItem(THEME_KEY, theme) } catch { /* ignored */ }
}

// ---------------------------------------------------------------------------
// Store
// ---------------------------------------------------------------------------

const stored = loadStoredState()

const initialSource = stored?.source ?? DEFAULT_SOURCE
const initialFormatOptions = stored?.formatOptions ?? getDefaultFormatOptions()
const initialTabs: TestTab[] = stored?.tabs.map(t => ({ ...t, tested: false, stale: false })) ?? [freshTab()]

export const [source, setSource] = createSignal(initialSource)
export const [formatOptions, setFormatOptions] = createStore<FormatOptions>(initialFormatOptions)
export const [tabs, setTabs] = createStore<TestTab[]>(initialTabs)
export const [activeTab, setActiveTab] = createSignal(0)
export const [theme, setTheme] = createSignal<'light' | 'dark'>(loadTheme())

export const compileResult = createMemo<{ ok: true; ptern: Ptern } | { ok: false; error: CompileError } | null>(() => {
  const s = source()
  if (!s.trim()) return null
  return compilePtern(s)
})

// Persist on every change
export function persistState(): void {
  saveState(source(), { ...formatOptions }, [...tabs])
}

// ---------------------------------------------------------------------------
// Tab actions
// ---------------------------------------------------------------------------

export function addTab(): void {
  if (tabs.length >= 20) return
  setTabs(produce((t: TestTab[]) => { t.push(freshTab()) }))
  setActiveTab(tabs.length - 1)
  persistState()
}

export function closeTab(index: number): void {
  if (tabs.length === 1) {
    setTabs(0, freshTab())
    setActiveTab(0)
  } else {
    setTabs(produce((t: TestTab[]) => { t.splice(index, 1) }))
    setActiveTab(prev => Math.min(prev, tabs.length - 1))
  }
  persistState()
}

export function updateTabField<K extends keyof TestTab>(index: number, key: K, value: TestTab[K]): void {
  setTabs(index, key, value)
  if (key === 'input' || key === 'captureValues') {
    if (tabs[index].tested) setTabs(index, 'stale', true)
  }
  persistState()
}

export function setTabMode(index: number, mode: TabMode): void {
  setTabs(index, 'mode', mode)
  setTabs(index, 'tested', false)
  setTabs(index, 'stale', false)
  persistState()
}

export function markTabTested(index: number): void {
  setTabs(index, 'tested', true)
  setTabs(index, 'stale', false)
}

// Mark all tabs stale when source changes
export function markAllTabsStale(): void {
  for (let i = 0; i < tabs.length; i++) {
    if (tabs[i].tested) setTabs(i, 'stale', true)
  }
}

// ---------------------------------------------------------------------------
// Theme actions
// ---------------------------------------------------------------------------

export function toggleTheme(): void {
  const next = theme() === 'light' ? 'dark' : 'light'
  setTheme(next)
  saveTheme(next)
  document.documentElement.classList.toggle('dark', next === 'dark')
}

// Apply saved theme on load
document.documentElement.classList.toggle('dark', loadTheme() === 'dark')
