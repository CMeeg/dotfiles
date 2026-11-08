// Prints what the user typed in a project's past Claude Code sessions, oldest session first, so the
// corrections in them can be read without the tool calls, tool output and injected context around them.
//
//   node user-messages.mjs [project folder] [--since YYYY-MM-DD] [--out file]
//
// The project folder is the one Claude Code keeps its transcripts in (~/.claude/projects/<cwd with each
// non-alphanumeric character replaced by "-">); by default, the one for the current directory.
import { createWriteStream, existsSync, readdirSync, readFileSync, statSync } from 'node:fs'
import { homedir } from 'node:os'
import { basename, join } from 'node:path'

const args = process.argv.slice(2)
const option = (name) => {
  const index = args.indexOf(name)
  return index === -1 ? undefined : args.splice(index, 2)[1]
}
const since = option('--since')
const out = option('--out')
const folder = args[0] ?? join(homedir(), '.claude', 'projects', process.cwd().replace(/[^A-Za-z0-9]/g, '-'))

if (!existsSync(folder)) {
  console.error(`No transcripts folder at ${folder}. Pass the project's folder from ~/.claude/projects/.`)
  process.exit(1)
}

// Text Claude Code adds to a user turn that the user didn't type.
const INJECTED = [/<system-reminder>[\s\S]*?<\/system-reminder>/g, /<local-command-[\w-]+>[\s\S]*?<\/local-command-[\w-]+>/g]
const NOT_TYPED = /^(<command-|<local-command-|Caveat: |\[Request interrupted)/

const typedText = (entry) => {
  if (entry.type !== 'user' || entry.isMeta || entry.isCompactSummary || entry.message?.role !== 'user') return ''
  const { content } = entry.message
  const parts = typeof content === 'string' ? [content] : (content ?? []).filter((part) => part.type === 'text').map((part) => part.text)
  return parts
    .map((text) => INJECTED.reduce((cleaned, pattern) => cleaned.replace(pattern, ''), text).trim())
    .filter((text) => text && !NOT_TYPED.test(text))
    .join('\n')
}

const sessions = readdirSync(folder)
  .filter((name) => name.endsWith('.jsonl'))
  .map((name) => {
    const messages = []
    for (const line of readFileSync(join(folder, name), 'utf8').split('\n')) {
      if (!line) continue
      let entry
      try {
        entry = JSON.parse(line)
      } catch {
        continue
      }
      const text = typedText(entry)
      if (text && (!since || (entry.timestamp ?? '') >= since)) messages.push({ at: entry.timestamp ?? '', text })
    }
    return { id: basename(name, '.jsonl'), messages, started: messages[0]?.at ?? statSync(join(folder, name)).mtime.toISOString() }
  })
  .filter((session) => session.messages.length > 0)
  .sort((a, b) => a.started.localeCompare(b.started))

const stream = out ? createWriteStream(out) : process.stdout
for (const session of sessions) {
  stream.write(`## Session ${session.id} (${session.started.slice(0, 16).replace('T', ' ')})\n\n`)
  for (const { at, text } of session.messages) stream.write(`- [${at.slice(0, 16).replace('T', ' ')}] ${text.replace(/\n/g, '\n  ')}\n`)
  stream.write('\n')
}
const total = sessions.reduce((sum, session) => sum + session.messages.length, 0)
console.error(`${total} messages from ${sessions.length} sessions${out ? `, written to ${out}` : ''}`)
if (out) stream.end()
