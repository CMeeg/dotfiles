// Checks that text moved out of an instructions file landed somewhere, once: each paragraph, list item,
// table row and heading of the old copy should appear exactly once across the new files.
//
//   node check-moved-text.mjs <old copy> <new file>...
//
// e.g. git show HEAD:AGENTS.md > /tmp/old-AGENTS.md
//      node check-moved-text.mjs /tmp/old-AGENTS.md AGENTS.md components/AGENTS.md .claude/skills/*/SKILL.md
//
// Matching ignores whitespace, so rewrapping is fine. Anything reworded on purpose (a pointer in place
// of moved text, a sentence adapted to its new home) is listed as not found, for a person to confirm.
import { readFileSync } from 'node:fs'

const [oldPath, ...newPaths] = process.argv.slice(2)
if (!oldPath || newPaths.length === 0) {
  console.error('Usage: node check-moved-text.mjs <old copy> <new file>...')
  process.exit(2)
}

const normalise = (text) => text.replace(/\s+/g, ' ').trim()

// Paragraphs, list items (with their continuation lines), table rows, headings and code blocks.
const units = (text) => {
  const found = []
  let current = []
  let fence = false
  const flush = () => {
    if (current.length) found.push(current.join('\n'))
    current = []
  }
  for (const line of text.split(/\r?\n/)) {
    if (/^\s*```/.test(line)) {
      if (fence) {
        current.push(line)
        flush()
      } else {
        flush()
        current.push(line)
      }
      fence = !fence
      continue
    }
    if (fence) {
      current.push(line)
      continue
    }
    if (!line.trim()) flush()
    else if (/^#{1,6}\s/.test(line) || /^\s*\|/.test(line)) {
      flush()
      found.push(line)
    } else if (/^\s*([-*+]|\d+\.)\s/.test(line)) {
      flush()
      current.push(line)
    } else current.push(line)
  }
  flush()
  return found.map((unit) => ({ raw: unit, key: normalise(unit.replace(/^\s*([-*+]|\d+\.)\s+/, '')) })).filter((unit) => unit.key)
}

const newFiles = newPaths.map((path) => ({ path, text: readFileSync(path, 'utf8') }))
const haystack = normalise(newFiles.map((file) => file.text).join('\n'))

// For text not found verbatim: the paragraph in the new files sharing most of its words, to check by eye.
const words = (text) => new Set(text.toLowerCase().match(/[\p{L}\p{N}_.-]{3,}/gu) ?? [])
const newUnits = newFiles.flatMap((file) => units(file.text).map((unit) => ({ path: file.path, key: unit.key, words: words(unit.key) })))
const closest = (key) => {
  const own = words(key)
  let best = { share: 0 }
  for (const candidate of newUnits) {
    let shared = 0
    for (const word of own) if (candidate.words.has(word)) shared++
    const share = own.size ? shared / own.size : 0
    if (share > best.share) best = { share, path: candidate.path }
  }
  return best.share ? ` [closest: ${Math.round(best.share * 100)}% of its words, in ${best.path}]` : ''
}
const count = (needle) => {
  let n = 0
  for (let at = haystack.indexOf(needle); at !== -1; at = haystack.indexOf(needle, at + needle.length)) n++
  return n
}

const results = units(readFileSync(oldPath, 'utf8')).map((unit) => ({ ...unit, n: count(unit.key) }))
const missing = results.filter((r) => r.n === 0)
const repeated = results.filter((r) => r.n > 1 && !/^\|?[\s|:-]*$/.test(r.key)) // table separators repeat harmlessly
const preview = (text) => (text.length > 160 ? `${text.slice(0, 157)}...` : text)

console.log(`${results.length} units in ${oldPath}: ${results.length - missing.length - repeated.length} found once, ${missing.length} not found, ${repeated.length} found more than once.`)
if (missing.length) {
  console.log('\nNot found verbatim (lost, or reworded on purpose: confirm each):')
  for (const r of missing) {
    console.log(`- ${preview(r.key)}${closest(r.key)}`)
    // A paragraph split across files is fine if each sentence landed; list only those that didn't.
    const sentences = r.key.split(/(?<=[.!?)])\s+(?=[A-Z`"(0-9])/).filter((s) => s.length > 20)
    const lost = sentences.filter((s) => count(s) === 0)
    if (sentences.length > 1) console.log(lost.length ? lost.map((s) => `    sentence not found: ${preview(s)}`).join('\n') : '    (every sentence found: it was split, not lost)')
  }
}
if (repeated.length) {
  console.log('\nFound more than once (duplicated, or a short line that also occurs elsewhere: confirm each):')
  for (const r of repeated) console.log(`- (${r.n}x) ${preview(r.key)}`)
}
process.exit(missing.length || repeated.length ? 1 : 0)
