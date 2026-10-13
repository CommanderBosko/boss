import { describe, expect, mock, test } from 'claude-code/testing'
import type { On } from 'claude-code'

import type { Snapshot } from '../types'

const BOSS = '/home/bosko/projects/boss'
const SNAP: Snapshot = {
  now: 10_000,
  rows: [
    { name: 'NixOS', color: '#e6194b', state: 'waiting', since: 9_988, detail: 'How should we\nhandle swayidle?' },
    { name: 'blueprint-smith', color: '#61afef', state: 'working', since: 9_820, detail: 'close out the session' },
    { name: 'Legions', color: '#a6e22e', state: 'idle', since: 7_000, detail: 'x'.repeat(300) },
  ],
}
const BAND = (bodyColumns: number) =>
  ({
    component: 'AbovePrompt',
    props: { hasSurvey: false, isWorking: false, maxRows: 20, bodyColumns, scroll: { offset: 0, bodyRows: 19 }, view: {} },
  }) as const

const result = (snap: Snapshot | null) =>
  snap === null
    ? { exitCode: 1, stdout: '', stderr: 'boom', isStdoutTruncated: false, isStderrTruncated: false }
    : { exitCode: 0, stdout: JSON.stringify(snap), stderr: '', isStdoutTruncated: false, isStderrTruncated: false }

// Answers the band's bin/boss-rows call beneath the plugin, recording what it ran.
const rowsScript = (on: On, snap: Snapshot | null, ran: string[][] = []) =>
  on('process.run', async (_$, e) => {
    ran.push([...e.argv])
    return { value: result(snap) }
  })

// Starts the session with the engine's part stood in by the test.
const start = (on: On, cwd = BOSS) => {
  on('session.start', (_$, e) => ({ cwd: e.cwd }))
  // The engine's own band, drawn whenever the plugin passes.
  on('ui.render', ($, e) => {
    const { Box } = $.ui.resolve(e)
    return <Box key="engine" />
  })
  return { cwd, surface: 'terminal', isInteractive: true } as const
}

describe('boss-band', () => {
  test('draws one row per worker in the order boss-rows gives, waiting in red', async ($, on) => {
    mock.clock(on, { now: 0 })
    const ran: string[][] = []
    rowsScript(on, SNAP, ran)
    await $.session.start(start(on))
    expect(ran[0]).toEqual([`${BOSS}/bin/boss-rows`])

    for (const surface of ['terminal', 'desktop'] as const) {
      const ui = await $.ui.mount({ plugin: 'boss-band', surface, ...BAND(100) })
      const names = await ui.findAll({ type: 'Text', text: /^■ / })
      expect(names.map(n => n.text?.trim())).toEqual(['■ NixOS', '■ blueprint-smith', '■ Legions'])
      expect(names[0]?.props.color).toBe('#e6194b')

      const waiting = await ui.find({ type: 'Text', text: /waiting/ })
      expect(waiting?.props.color).toBe('error')
      expect(await ui.find({ type: 'Text', text: /12s/ })).toBeDefined()
      expect(await ui.find({ type: 'Text', text: /3m/ })).toBeDefined()
      expect(await ui.find({ type: 'Text', text: 'How should we handle swayidle?' })).toBeDefined()

      // The 300-char task is cut to fit the band, ending in an ellipsis.
      const long = await ui.find({ type: 'Text', text: /^x+…$/ })
      expect(long).toBeDefined()
      expect((long?.text ?? '').length).toBeLessThanOrEqual(100)
      await ui.unmount()
    }
  })

  test('re-polls on its timer and picks up changes', async ($, on) => {
    const clock = mock.clock(on, { now: 0 })
    const snaps: Snapshot[] = [SNAP, { now: 10_002, rows: [] }]
    let calls = 0
    on('process.run', async () => {
      return { value: result(snaps[Math.min(calls++, snaps.length - 1)] ?? null) }
    })
    await $.session.start(start(on))
    const ui = await $.ui.mount({ plugin: 'boss-band', surface: 'terminal', ...BAND(100) })
    expect(await ui.find({ type: 'Text', text: /NixOS/ })).toBeDefined()

    await clock.advance(2000)
    expect(calls).toBe(2)
    expect(await ui.find({ type: 'Text', text: /NixOS/ })).toBeUndefined()
    expect(await ui.find({ key: 'engine' })).toBeDefined()
    await ui.unmount()
  })

  test('shows nothing when there are no workers or the script fails', async ($, on) => {
    mock.clock(on, { now: 0 })
    rowsScript(on, null)
    await $.session.start(start(on, '/somewhere/else'))
    const ui = await $.ui.mount({ plugin: 'boss-band', surface: 'terminal', ...BAND(100) })
    expect(await ui.find({ type: 'Text', text: /■/ })).toBeUndefined()
    expect(await ui.find({ key: 'engine' })).toBeDefined()
    await ui.unmount()
  })
})
