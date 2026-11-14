// The context window as a bar of categories, with the key that names them.
// Adapted from context-bar by Hamza Zafar (https://github.com/hamzafer/claude-code-mods), MIT licensed: see LICENSE.
import type { Reading, Slice } from '../types'

// Dracula's accents, one per used category in /context's order; messages, the category that grows, in orange.
const PALETTE = ['#bd93f9', '#8be9fd', '#ff79c6', '#50fa7b', '#f1fa8c', '#ff5555']
const MESSAGES = '#ffb86c'
const FREE = '#44475a'
const BUFFER = '#6272a4'
// Half height and centred on the line, so the bar lines up with the text beside it
export const GLYPH = '▬'
export const KEY_GAP = '   '

type Breakdown = {
  categories: { name: string; tokens: number; color: string; kind: string }[]
  totalTokens: number
  rawMaxTokens: number
  percentage: number
  autoCompactThreshold?: number
  isAutoCompactEnabled: boolean
}

// Auto-compaction applies CLAUDE_AUTOCOMPACT_PCT_OVERRIDE as min(threshold, effective window * pct / 100)
// when 0 < pct <= 100; the breakdown's threshold leaves it out and sits a fixed 13k below that window.
const AUTOCOMPACT_BUFFER = 13_000
export function compactPoint (threshold: number, pctOverride?: number) {
  if (!(pctOverride !== undefined && pctOverride > 0 && pctOverride <= 100)) return threshold
  return Math.min(threshold, Math.floor((threshold + AUTOCOMPACT_BUFFER) * (pctOverride / 100)))
}

/** The breakdown as slices, used ones first in /context's order, each with its colour. */
export function toReading (b: Breakdown, pctOverride?: number): Reading {
  const order = { used: 0, free: 1, buffer: 2 }
  const slices: Slice[] = b.categories
    .filter(c => c.kind !== 'deferred' && c.tokens > 0)
    .map(c => ({ name: c.name.toLowerCase(), tokens: c.tokens, color: '', kind: c.kind as Slice['kind'] }))
    .sort((x, y) => order[x.kind] - order[y.kind])
  let next = 0
  for (const s of slices) {
    s.color = s.kind === 'free' ? FREE : s.kind === 'buffer' ? BUFFER : s.name === 'messages' ? MESSAGES : PALETTE[next++ % PALETTE.length]!
  }
  return {
    slices,
    total: b.totalTokens,
    window: b.rawMaxTokens,
    percent: b.percentage,
    compactsAt: b.isAutoCompactEnabled && b.autoCompactThreshold !== undefined ? compactPoint(b.autoCompactThreshold, pctOverride) : undefined
  }
}

/**
 * The bar as runs of cells. The used slices share the cells for the used part of the window, a used slice at least one
 * cell, and the free space and buffer share the rest, so the coloured part of the bar matches the percentage beside it.
 */
export function cells (r: Reading, width: number) {
  const used = r.slices.filter(s => s.kind === 'used')
  const unused = r.slices.filter(s => s.kind !== 'used')
  const usedTokens = used.reduce((a, s) => a + s.tokens, 0)
  const usedCells = Math.min(width, Math.max(used.length, Math.round((usedTokens / r.window) * width)))
  const sizes = [...apportion(used.map(s => s.tokens), usedCells, 1), ...apportion(unused.map(s => s.tokens), width - usedCells, 0)]
  return [...used, ...unused].map((s, i) => ({ name: s.name, color: s.color, text: GLYPH.repeat(sizes[i]!) })).filter(c => c.text !== '')
}

/** `count` cells split in proportion to `weights`, each at least `min`; the largest take the rounding difference. */
function apportion (weights: number[], count: number, min: number) {
  const sum = weights.reduce((a, n) => a + n, 0)
  const sizes = weights.map(w => Math.max(min, sum > 0 ? Math.round((w / sum) * count) : 0))
  let diff = count - sizes.reduce((a, n) => a + n, 0)
  const order = sizes.map((_, i) => i).sort((a, b) => sizes[b]! - sizes[a]!)
  for (const i of order) {
    if (diff === 0) break
    const size = Math.max(min, sizes[i]! + diff)
    diff -= size - sizes[i]!
    sizes[i] = size
  }
  return sizes
}

/** How full the window is towards compaction (or the window, with compaction off), as a theme colour. */
export function levelColor (r: Reading) {
  const level = r.compactsAt ? r.total / r.compactsAt : r.total / r.window
  return level >= 0.9 ? 'error' : level >= 0.7 ? 'warning' : undefined
}

/** The key's entries packed into lines no wider than `width`. */
export function keyLines (r: Reading, width: number) {
  const lines: Slice[][] = [[]]
  let used = 0
  for (const s of r.slices) {
    const size = 2 + s.name.length + 1 + tokens(s.tokens).length + (s.kind === 'used' ? 1 + share(s.tokens, r.window).length : 0)
    const line = lines.at(-1)!
    if (line.length > 0 && used + KEY_GAP.length + size > width) {
      lines.push([s])
      used = size
    } else {
      used += (line.length > 0 ? KEY_GAP.length : 0) + size
      line.push(s)
    }
  }
  return lines.filter(l => l.length > 0)
}

export function tokens (n: number) {
  if (n >= 1_000_000) return `${+(n / 1_000_000).toFixed(n % 1_000_000 === 0 ? 0 : 1)}M`
  if (n >= 10_000) return `${Math.round(n / 1000)}k`
  if (n >= 1000) return `${+(n / 1000).toFixed(1)}k`
  return String(n)
}

export function share (n: number, window: number) {
  const p = (n / window) * 100
  if (p > 0 && p < 0.1) return '<0.1%'
  return `${p >= 10 ? Math.round(p) : +p.toFixed(1)}%`
}
