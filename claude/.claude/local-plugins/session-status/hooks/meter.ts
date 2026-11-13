// The subscription meter's figures: which windows to show, their colours, and how wide each form of
// the meter is. Adapted from sub-meter by Miguel Ángel Durán (https://github.com/midudev/better-claude), MIT licensed: see LICENSE.
import type { SessionRateLimit } from 'claude-code'

import type { Limit } from '../types'

const WINDOWS = ['five_hour', 'seven_day']
const LABELS: Record<string, string> = { five_hour: '5h', seven_day: 'week' }
const WINDOW_OF: Record<string, string> = { session: 'five_hour', week: 'seven_day' }
export const DISPLAYS = ['rotate', 'both', 'session', 'week']
export const CELLS = 10
export const BETWEEN = '  |  '

/** The subscription windows the meter shows, in order, from what the engine measured. */
export const windowsOf = (rateLimits: readonly SessionRateLimit[]): Limit[] =>
  WINDOWS.flatMap(kind => {
    const found = rateLimits.find(limit => limit.kind === kind)
    return found ? [{ kind, percentUsed: found.percentUsed, resetsAt: found.resetsAt }] : []
  })

/** The windows to draw: all of them, the one the rotation is on, or the one chosen. With fewer than two readings, whatever there is. */
export function visible (all: Limit[], display: string, index: number): Limit[] {
  if (display === 'both' || all.length < 2) return all
  if (display === 'rotate') return [all[index % all.length]!]
  return all.filter(limit => limit.kind === WINDOW_OF[display])
}

export const colorFor = (percent: number) => (percent >= 90 ? 'error' : percent >= 75 ? 'warning' : 'claude')

/** Columns a text takes: one per character, none for a variation selector. */
export const widthOf = (text: string) => [...text.replace(/[︎️]/g, '')].length

/** "42m", "3h 5m", "2d 4h": how long until the window resets. */
export function until (ms: number) {
  const minutes = Math.max(1, Math.round(ms / 60000))
  if (minutes < 60) return `${minutes}m`
  const hours = Math.floor(minutes / 60)
  if (hours < 24) return `${hours}h ${minutes % 60}m`
  return `${Math.floor(hours / 24)}d ${hours % 24}h`
}

export type MeterWindow = { kind: string; label: string; percent: number; filled: number; used: string; reset: string }
export type MeterForm = { hasBar: boolean; hasReset: boolean; width: number }

/** Each shown window as drawn at `now`: a window past its reset reads 0%. */
export function meterWindows (shown: Limit[], now: number): MeterWindow[] {
  return shown.map(limit => {
    const resetsIn = limit.resetsAt === undefined ? undefined : Date.parse(limit.resetsAt) - now
    const hasReset = resetsIn !== undefined && resetsIn <= 0
    const percent = hasReset ? 0 : limit.percentUsed
    const filled = Math.round((Math.min(Math.max(percent, 0), 100) / 100) * CELLS)
    const reset = resetsIn !== undefined && !hasReset ? ` ↻ ${until(resetsIn)}` : ''
    return { kind: limit.kind, label: LABELS[limit.kind] ?? limit.kind, percent, filled, used: ` ${Math.round(percent)}%`, reset }
  })
}

/** The meter's forms, widest first: with its bar and reset time, without the bar, without either. */
export function meterForms (windows: MeterWindow[]): MeterForm[] {
  const short = windows.reduce((sum, w) => sum + widthOf(w.label + w.used), (windows.length - 1) * BETWEEN.length)
  const bars = windows.length * (1 + CELLS)
  const resets = windows.reduce((sum, w) => sum + widthOf(w.reset), 0)
  return [
    { hasBar: true, hasReset: true, width: short + bars + resets },
    { hasBar: false, hasReset: true, width: short + resets },
    { hasBar: false, hasReset: false, width: short }
  ]
}
