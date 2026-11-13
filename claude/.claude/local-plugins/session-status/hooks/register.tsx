// Under the prompt, in place of the hint line: the context window as a bar at the left, the
// subscription meter and the model and effort at the right; the bar's key on the rows below, behind [+].
import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register, RenderViewport } from 'claude-code'

import type { Limit, ModelInfo, Reading } from '../types'
import { cells, keyLines, KEY_GAP, levelColor, share, tokens, toReading } from './context'
import { BETWEEN, CELLS, colorFor, DISPLAYS, meterForms, meterWindows, visible, widthOf, windowsOf } from './meter'
import { friendlyName } from './model'

const model = atom({ plugin: 'session-status', key: 'model' } as const, null as ModelInfo | null)
const limits = atom({ plugin: 'session-status', key: 'limits' } as const, [] as Limit[])
const meterView = atom({ plugin: 'session-status', key: 'meterView' } as const, 0) // which window the rotating meter shows
const meterTick = atom({ plugin: 'session-status', key: 'meterTick' } as const, 0) // redraws the countdown
const reading = atom({ plugin: 'session-status', key: 'reading' } as const, null as Reading | null)
const isKeyShown = atom({ plugin: 'session-status', key: 'isKeyShown' } as const, false)

const ROTATE_SECONDS = 8
const TICK_MS = 8000
// The terminal footer's row: two columns of padding at each end and, when a permission mode is on,
// its label at the left (`⏵⏵ accept edits on ·`, the longest but bypass's) before the hint column.
const FOOTER_PADDING = 4
const MODE_LABEL = 20
const BAR_MIN = 10
const BAR_MAX = 30
const GAP = 2
const BUTTON = '[+]'
const SEPARATOR = ' · '

let tickTimer: { cancel: () => void } | undefined
let rotateTimer: { cancel: () => void } | undefined
// When the meter reading this session shows was taken; the shared store carries the newest one of any session
let seenAt = 0
let windowCount = 0

/** Columns the hint column leaves for a row on the terminal; elsewhere, no limit. */
function roomOf (e: { surface: string; viewport?: RenderViewport }) {
  if (e.surface !== 'terminal' || e.viewport === undefined) return Infinity
  return e.viewport.columns - FOOTER_PADDING - MODE_LABEL
}

/** Keeps a reading a response just reported, for every session and the next one; an empty one clears the meter. */
async function remember ($: EngineInterface, found: Limit[]) {
  seenAt = await $.clock.now()
  windowCount = found.length
  await update($, limits, () => found)
  await $.store.set('limits', found)
  await $.store.set('at', seenAt) // after the limits, so a reader that sees the new time finds the new limits
}

/** Adopts the meter reading another session left in the shared store, when it is newer than ours. */
async function syncFromStore ($: EngineInterface) {
  const at = Number(await $.store.get('at')) || 0
  if (at <= seenAt) return
  const saved = await $.store.get('limits')
  if (!Array.isArray(saved)) return
  seenAt = at
  windowCount = saved.length
  await update($, limits, () => saved as Limit[])
}

/** Reads /context's breakdown, estimated locally (no token-count calls). */
async function refreshContext ($: EngineInterface) {
  const usage = await $.session.usage({ breakdown: 'summary' })
  const b = usage.context.breakdown
  if (!b || !(b.rawMaxTokens > 0)) return // no window to measure against
  const pct = await $.env.get('CLAUDE_AUTOCOMPACT_PCT_OVERRIDE').catch(() => undefined)
  await update($, reading, () => toReading(b, pct ? parseFloat(pct) : undefined))
}

function stopTimers () {
  tickTimer?.cancel()
  tickTimer = undefined
  rotateTimer?.cancel()
  rotateTimer = undefined
}

export const register: Register = (on, options) => {
  seenAt = 0
  windowCount = 0
  const rotateSeconds = Number(options.rotateSeconds)
  const rotateMs = (rotateSeconds > 0 ? rotateSeconds : ROTATE_SECONDS) * 1000
  const display = DISPLAYS.includes(String(options.display)) ? String(options.display) : 'rotate'

  on('session.start', async ($, e, next) => {
    stopTimers()
    const result = await next(e)

    const [saved, storedAt, usage, current, keyShown] = await Promise.all([
      $.store.get('limits'),
      $.store.get('at'),
      $.session.usage(),
      $.session.model(),
      $.store.get('isKeyShown')
    ])
    // The store holds the newest reading any session measured. This session's own may be hours old (a
    // reload, a resumed session), so it is shown only when nothing is stored, and never stored as new.
    const shown = Array.isArray(saved) ? (saved as Limit[]) : windowsOf(usage.rateLimits)
    seenAt = Array.isArray(saved) ? Number(storedAt) || 0 : 0
    windowCount = shown.length
    await update($, limits, () => shown)
    await update($, model, info => info ?? { model: current })
    await update($, isKeyShown, () => keyShown === true)
    void refreshContext($).catch(() => {})

    if (e.isInteractive) {
      // Another session's reading shows up within TICK_MS of being stored
      tickTimer = $.clock.every(TICK_MS, () => {
        void syncFromStore($).catch(() => {}) // a failed read keeps the reading on screen
        if (windowCount > 0) void update($, meterTick, n => n + 1)
      })
      if (display === 'rotate') {
        rotateTimer = $.clock.every(rotateMs, () => {
          if (windowCount >= 2) void update($, meterView, n => n + 1)
        })
      }
    }
    return result
  })

  // The timers keep running: after a /clear the process goes on with no session.start to restart them,
  // and when it exits they go with it.
  on('session.end', async ($, e, next) => {
    const result = await next(e)
    if (e.reason !== 'clear') return result
    // A /clear starts a new window with no turn yet: read it once the end step's time bound has passed
    await update($, reading, () => null)
    const left = next.budget.remainingMs
    try {
      $.clock.after(Number.isFinite(left) ? left : 0, () => void refreshContext($).catch(() => {}))
    } catch {
      // no clock: the next turn refreshes
    }
    return result
  })

  on('session.measure', async ($, e, next) => {
    const found = windowsOf(e.rateLimits)
    // An empty reading that changed means the windows left (off a subscription), not that none came yet
    if (found.length > 0 || e.changed.includes('rateLimits')) await remember($, found)
    return next(e)
  })

  // Each main-loop model request carries the resolved model and effort
  on('turn.step', async function * ($, e, next) {
    if (e.agentId === undefined) {
      const latest = { model: e.model, effort: e.effort }
      await update($, model, () => latest)
    }
    return yield * next(e)
  })

  on('turn.complete', async ($, e, next) => {
    const result = await next(e)
    if (!e.agentId) await refreshContext($).catch(() => {}) // a subagent's turn fills its own window, not this one
    return result
  })

  on('session.compact', async ($, e, next) => {
    const result = await next(e)
    if (!e.agentId && 'messages' in result) void refreshContext($).catch(() => {}) // a /compact empties the window without a turn ending
    return result
  })

  on('ui.render', { component: 'PromptHint' }, async ($, e, next) => {
    const [info, all, view, ctx, isShown, , now] = await Promise.all([
      read($, model),
      read($, limits),
      read($, meterView),
      read($, reading),
      read($, isKeyShown),
      read($, meterTick), // subscribes this drawing to the countdown
      $.clock.now()
    ])
    const { Box, Button, Text } = $.ui.resolve(e)
    const room = roomOf(e)

    const modelName = info ? friendlyName(info.model) : ''
    const effort = info?.effort === undefined ? '' : ` ${info.effort}`
    const modelWidth = info ? widthOf(modelName + effort) : 0

    // The meter takes its widest form that leaves the context bar its narrowest beside the model
    const windows = meterWindows(visible(all, display, display === 'rotate' ? view : 0), now)
    const percent = ctx ? ` ${ctx.percent}% ` : ''
    const contextMin = ctx ? BAR_MIN + widthOf(percent) + BUTTON.length : 0
    const form = windows.length === 0
      ? undefined
      : meterForms(windows).find(f => f.width + (info ? SEPARATOR.length : 0) + modelWidth + GAP + contextMin <= room)
    const rightWidth = (form ? form.width + (info ? SEPARATOR.length : 0) : 0) + modelWidth + GAP
    const barWidth = Math.max(BAR_MIN, Math.min(BAR_MAX, room - rightWidth - widthOf(percent) - BUTTON.length))

    const toggleKey = async () => {
      const shown = await update($, isKeyShown, s => !s)
      await $.store.set('isKeyShown', shown).catch(() => {})
    }

    return (
      <Box flexDirection="column" width="100%">
        <Box flexDirection="row" justifyContent="space-between">
          {ctx ? (
            <Box flexDirection="row">
              <Text>
                {cells(ctx, barWidth).map(c => <Text key={c.name} color={c.color}>{c.text}</Text>)}
                <Text color={levelColor(ctx)}>{percent}</Text>
              </Text>
              <Button key="key" plain onPress={toggleKey}><Text dimColor>{isShown ? '[-]' : BUTTON}</Text></Button>
            </Box>
          ) : <Text> </Text>}
          <Box flexDirection="row">
            {form ? windows.map((w, i) => (
              <Box flexDirection="row" key={w.kind}>
                {i > 0 ? <Text dimColor>{BETWEEN}</Text> : null}
                <Text dimColor>{w.label}</Text>
                {form.hasBar ? <Text color={colorFor(w.percent)}>{' ' + '━'.repeat(w.filled)}</Text> : null}
                {form.hasBar ? <Text dimColor>{'─'.repeat(CELLS - w.filled)}</Text> : null}
                <Text>{w.used}</Text>
                {form.hasReset && w.reset ? <Text dimColor>{w.reset}</Text> : null}
              </Box>
            )) : null}
            {form && info ? <Text dimColor>{SEPARATOR}</Text> : null}
            {info ? (
              <Text>
                <Text>{modelName}</Text>
                <Text dimColor>{effort}</Text>
              </Text>
            ) : null}
          </Box>
        </Box>
        {ctx && isShown ? (
          <Box flexDirection="column">
            <Text dimColor wrap="truncate-end">
              {`${tokens(ctx.total)} of ${tokens(ctx.window)}${ctx.compactsAt ? ` · compacts at ${tokens(ctx.compactsAt)}` : ''}`}
            </Text>
            {keyLines(ctx, Number.isFinite(room) ? room : 200).map(line => (
              <Text key={line[0]!.name} wrap="truncate-end">
                {line.map((s, i) => (
                  <Text key={s.name}>
                    {i > 0 ? <Text>{KEY_GAP}</Text> : null}
                    <Text color={s.color}>■ </Text>
                    <Text dimColor={s.kind !== 'used'}>{`${s.name} `}</Text>
                    <Text bold={s.kind === 'used'}>{tokens(s.tokens)}</Text>
                    {s.kind === 'used' ? <Text dimColor>{` ${share(s.tokens, ctx.window)}`}</Text> : null}
                  </Text>
                ))}
              </Text>
            ))}
          </Box>
        ) : null}
      </Box>
    )
  })
}
