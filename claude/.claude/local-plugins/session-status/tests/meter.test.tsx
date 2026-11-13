// The meter as the footer draws it, run against the engine itself.
import { expect, mock, test } from 'claude-code/testing'
import type { Engine } from 'claude-code/testing'
import type { On, SessionRateLimit } from 'claude-code'

const NOW = Date.parse('2026-11-13T10:00:00Z')
const at = (ms: number) => new Date(NOW + ms).toISOString()
const HOUR = 3_600_000
const LIMITS: SessionRateLimit[] = [
  { kind: 'five_hour', percentUsed: 58, resetsAt: at(2 * HOUR) },
  { kind: 'seven_day', percentUsed: 23, resetsAt: at(76 * HOUR) }
]

/** Everything beneath the mod: the clock, the shared store and the session's figures. */
function world (on: On, rateLimits: SessionRateLimit[] = LIMITS) {
  const clock = mock.clock(on, { now: NOW })
  const store: Record<string, unknown> = {}
  on('store.get', ($, e) => ({ value: store[e.key] }))
  on('store.set', ($, e) => {
    store[e.key] = JSON.parse(JSON.stringify(e.value))
    return { value: undefined }
  })
  on('session.start', ($, e) => ({ cwd: e.cwd }))
  on('session.end', ($, e) => ({ sessionId: e.sessionId }))
  on('session.model', () => ({ value: 'claude-opus-5-5' }))
  on('session.usage', () => ({ value: { startedAt: NOW, context: { window: 200_000 }, rateLimits } as never }))
  on('session.measure', ($, e) => ({ changed: e.changed }))
  return { clock, store }
}

const startSession = ($: Engine) => $.session.start({ cwd: '/project', surface: 'terminal', isInteractive: true })
const hint = ($: Engine) =>
  $.ui.mount({ plugin: 'session-status', surface: 'terminal', component: 'PromptHint', props: { isDraft: false, isWorking: false, hint: '' }, viewport: { columns: 160, rows: 30 } })
const shows = async ($: Engine, text: string) => (await (await hint($)).find({ type: 'Text', text })) !== undefined

test('the meter keeps taking turns after a /clear', async ($, on) => {
  const w = world(on)
  await startSession($)
  await $.session.end({ reason: 'clear', sessionId: 'first', resume: { id: 'first' } })
  await w.clock.advance(8000)
  expect(await shows($, 'week')).toBe(true)
  await w.clock.advance(8000)
  expect(await shows($, '5h')).toBe(true)
})

test('a session start shows the newest stored reading and leaves it as it was', async ($, on) => {
  const w = world(on)
  w.store.limits = [{ kind: 'five_hour', percentUsed: 70, resetsAt: at(HOUR) }]
  w.store.at = NOW - 1000
  await startSession($)
  expect(await shows($, ' 70%')).toBe(true)
  expect(w.store.at).toBe(NOW - 1000)
})

test('the row takes the hint line\'s place rather than drawing beside it', async ($, on) => {
  world(on)
  await startSession($)
  expect(await (await hint($)).keepsBeneath()).toBe(false)
})

test('the meter goes when the windows leave, and stays through a measurement without them', async ($, on) => {
  world(on)
  await startSession($)
  const context = { window: 200_000 }
  await $.session.measure({ context, rateLimits: [], changed: ['context'] })
  expect(await shows($, '5h')).toBe(true)
  await $.session.measure({ context, rateLimits: [], changed: ['rateLimits'] })
  expect(await shows($, '5h')).toBe(false)
  expect(await shows($, 'week')).toBe(false)
})
