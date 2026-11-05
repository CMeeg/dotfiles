import { atom, read, update } from 'claude-code'
import type { Register, RenderNode } from 'claude-code'

import type { ModelInfo } from '../types'

const info = atom({ plugin: 'model-effort-status', key: 'info' } as const, null as ModelInfo | null)

const capitalise = (word: string) => word.charAt(0).toUpperCase() + word.slice(1)

/** "claude-opus-5-5" → "Opus 5.5", "claude-3-5-sonnet-20241022" → "Sonnet 3.5"; anything else as given. */
export function friendlyName (model: string) {
  const id = model.replace(/\[.*\]$/, '')
  const familyFirst = id.match(/^claude-(?<family>[a-z]+)-(?<major>\d+)(?:-(?<minor>\d{1,2}))?(?:-\d{8})?$/)
  const versionFirst = id.match(/^claude-(?<major>\d+)(?:-(?<minor>\d{1,2}))?-(?<family>[a-z]+)(?:-\d{8})?$/)
  const parts = (familyFirst ?? versionFirst)?.groups
  if (!parts?.family || !parts.major) return model
  return `${capitalise(parts.family)} ${parts.major}${parts.minor ? `.${parts.minor}` : ''}`
}

/** Whether a drawing beneath shows nothing (the engine's own node is empty when no mode is on). */
function isBlank (node: RenderNode | undefined): boolean {
  if (node === undefined || node === null) return true
  if (typeof node === 'string') return node.trim() === ''
  return (node.type === 'Box' || node.type === 'Text') && (node.children ?? []).every(isBlank)
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    const result = await next(e)
    // Clears the status-line text the first version of this mod left behind
    $.ui.status(undefined)
    const model = await $.session.model()
    await update($, info, current => current ?? { model })
    return result
  })

  // Each main-loop model request carries the resolved model and effort
  on('turn.step', async function* ($, e, next) {
    if (e.agentId === undefined) {
      const latest = { model: e.model, effort: e.effort }
      await update($, info, () => latest)
    }
    return yield* next(e)
  })

  // Bottom right of the prompt footer, beside the mode labels and anything other mods draw there (e.g. sub-meter)
  on('ui.render', { component: 'SessionMode' }, async ($, e, next) => {
    const drawn = await next(e)
    const shown = await read($, info)
    if (shown === null) return drawn

    const beneath = isBlank(drawn) ? null : drawn

    const { Box, Text } = $.ui.resolve(e)
    return (
      <Box flexDirection="row">
        {beneath}
        {beneath ? <Text dimColor> · </Text> : null}
        <Text>{friendlyName(shown.model)}</Text>
        {shown.effort === undefined ? null : <Text dimColor> {shown.effort}</Text>}
      </Box>
    )
  })
}
