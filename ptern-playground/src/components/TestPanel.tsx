import TabBar from './TabBar'
import TabContent from './TabContent'

export default function TestPanel() {
  return (
    <div class="border-t border-stone-200 dark:border-zinc-700 2xl:border-t-0">
      <div class="px-3 pt-3">
        <TabBar />
      </div>
      <div class="border-t border-stone-200 dark:border-zinc-700">
        <TabContent />
      </div>
    </div>
  )
}
