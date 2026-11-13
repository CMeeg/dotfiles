import { expect, test } from 'claude-code/testing'

import { cells, compactPoint, toReading } from '../hooks/context'
import { visible } from '../hooks/meter'
import { friendlyName } from '../hooks/model'

// /context's breakdown as the engine hands it over, for a 200k window.
const BREAKDOWN = {
  categories: [
    { name: 'System prompt', tokens: 3_400, color: 'promptBorder', kind: 'used' },
    { name: 'System tools', tokens: 12_000, color: 'inactive', kind: 'used' },
    { name: 'MCP tools (deferred)', tokens: 40_000, color: 'inactive', kind: 'deferred' },
    { name: 'Skills', tokens: 0, color: 'warning', kind: 'used' },
    { name: 'Memory files', tokens: 150, color: 'warning', kind: 'used' },
    { name: 'Messages', tokens: 60_000, color: 'purple', kind: 'used' },
    { name: 'Autocompact buffer', tokens: 33_000, color: 'inactive', kind: 'buffer' },
    { name: 'Free space', tokens: 91_450, color: 'promptBorder', kind: 'free' }
  ],
  totalTokens: 75_550,
  rawMaxTokens: 200_000,
  percentage: 38,
  autoCompactThreshold: 167_000,
  isAutoCompactEnabled: true
}

test('the context bar fills exactly its width, every used category at least one cell, deferred and empty ones left out', () => {
  const reading = toReading(BREAKDOWN)
  for (const width of [10, 23, 30]) {
    const runs = cells(reading, width)
    expect(runs.reduce((sum, run) => sum + [...run.text].length, 0)).toBe(width)
    expect(runs.length).toBe(6) // system prompt, tools, memory files, messages, free, buffer
  }
  // A window filled past its size still draws in its width, the free space gone
  const overfull = toReading({ ...BREAKDOWN, categories: [...BREAKDOWN.categories.slice(0, 5), { name: 'Messages', tokens: 260_000, color: 'purple', kind: 'used' }] })
  expect(cells(overfull, 20).reduce((sum, run) => sum + [...run.text].length, 0)).toBe(20)
})

test('compaction moves to the override percentage of the effective window only when it is lower and in range', () => {
  const cases: [number | undefined, number][] = [
    [undefined, 167_000],
    [50, 90_000], // (167k + 13k) * 50%
    [95, 167_000], // above the threshold: the threshold stands
    [0, 167_000],
    [150, 167_000]
  ]
  for (const [pct, expected] of cases) expect(compactPoint(167_000, pct)).toBe(expected)
})

test('the meter shows the window the display option asks for, or whatever there is', () => {
  const five = { kind: 'five_hour', percentUsed: 31 }
  const week = { kind: 'seven_day', percentUsed: 12 }
  const cases: [string, number, typeof five[], string[]][] = [
    ['rotate', 0, [five, week], ['five_hour']],
    ['rotate', 1, [five, week], ['seven_day']],
    ['rotate', 2, [five, week], ['five_hour']],
    ['both', 0, [five, week], ['five_hour', 'seven_day']],
    ['session', 0, [five, week], ['five_hour']],
    ['week', 0, [five, week], ['seven_day']],
    ['session', 0, [week], ['seven_day']]
  ]
  for (const [display, index, all, kinds] of cases) {
    expect(visible(all, display, index).map(limit => limit.kind)).toEqual(kinds)
  }
})

test('model ids read as family and version, anything else as given', () => {
  const cases: [string, string][] = [
    ['claude-opus-5-5', 'Opus 5.5'],
    ['claude-sonnet-4-20250514', 'Sonnet 4'],
    ['claude-3-5-sonnet-20241022', 'Sonnet 3.5'],
    ['claude-opus-5-5[1m]', 'Opus 5.5'],
    ['some-other-model', 'some-other-model']
  ]
  for (const [id, name] of cases) expect(friendlyName(id)).toBe(name)
})
