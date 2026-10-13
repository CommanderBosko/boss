import { atom, read, update } from 'claude-code'
import type { Register } from 'claude-code'

import type { Snapshot } from '../types'

// Polls the boss's bin/boss-rows and draws one row per worker above the prompt. The script
// prints no rows unless this session is the live boss, so the band hides everywhere else.
const POLL_MS = 2000
const snapshot = atom({ plugin: 'boss-band', key: 'snapshot' } as const, null)

// Same buckets as bin/boss-status.
const ago = (s: number) =>
  s < 90 ? `${s}s` : s < 5400 ? `${Math.floor(s / 60)}m` : `${Math.floor(s / 3600)}h`

const clip = (text: string, width: number) =>
  text.length <= width ? text : width <= 1 ? '' : `${text.slice(0, width - 1)}…`

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    const started = await next(e)
    const script = `${e.cwd}/bin/boss-rows`
    const poll = async () => {
      try {
        const { exitCode, stdout } = await $.process.run([script], { timeoutMs: 5000 })
        const snap: Snapshot | null = exitCode === 0 ? JSON.parse(stdout) : null
        await update($, snapshot, () => snap)
      } catch {
        await update($, snapshot, () => null)
      }
    }
    await poll()
    $.clock.every(POLL_MS, () => void poll())

    return started
  })

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    const snap = await read($, snapshot)
    if (e.props.hasSurvey || snap === null || snap.rows.length === 0) {
      return next(e)
    }

    const { Box, Text } = $.ui.resolve(e)
    const nameWidth = Math.max(...snap.rows.map(row => row.name.length))
    // "■ " + name, " " + state(7), " " + age(3), "  ": what is left goes to the detail.
    const detailWidth = Math.max(0, e.props.bodyColumns - (2 + nameWidth + 1 + 7 + 1 + 3 + 2))

    return (
      <Box flexDirection="column">
        {snap.rows.map(row => {
          const isWaiting = row.state === 'waiting'
          const detail = row.detail.replace(/\s+/g, ' ').trim()

          return (
            <Box flexDirection="row">
              <Text color={row.color} bold>
                ■ {row.name.padEnd(nameWidth)}
              </Text>
              <Text color={isWaiting ? 'error' : undefined} bold={isWaiting} dimColor={row.state === 'idle'}>
                {' '}
                {row.state.padEnd(7)}
              </Text>
              <Text dimColor> {ago(Math.max(0, snap.now - row.since)).padStart(3)}  </Text>
              <Text dimColor={!isWaiting} wrap="truncate-end">
                {clip(detail, detailWidth)}
              </Text>
            </Box>
          )
        })}
      </Box>
    )
  })
}
