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
