export type WorkerRow = { name: string; color: string; state: string; since: number; detail: string }

// What bin/boss-rows prints: the time it ran (epoch seconds) and the rows, waiting first.
export type Snapshot = { now: number; rows: WorkerRow[] }

declare module 'claude-code' {
  interface PluginState {
    'boss-band': { snapshot: Snapshot | null }
  }
}
