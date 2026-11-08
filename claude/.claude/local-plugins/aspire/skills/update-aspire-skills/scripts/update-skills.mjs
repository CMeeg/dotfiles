// Refreshes Aspire's agent skills in `.claude/skills/` from the installed Aspire CLI, e.g. after `aspire update`.
// Run it from the project's root: `node <path to this file>`. `aspire agent init` also writes a hook into the user's global Claude Code settings,
// so it runs with its home folder pointed at a temporary one, and the skills are copied in from there. On Windows the
// CLI finds the real profile folder anyway, so the global settings file is also saved first and put back exactly as it
// was (or removed, if there wasn't one) afterwards, whether or not the install worked.
import { spawnSync } from 'node:child_process'
import { createHash } from 'node:crypto'
import { cpSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import { homedir, tmpdir } from 'node:os'
import { join } from 'node:path'

const SKILLS = ['aspire', 'aspire-orchestration', 'aspire-monitoring']
const SKILLS_DIR = join('.claude', 'skills')
const VERSION_FILE = join(SKILLS_DIR, 'ASPIRE_SKILLS_VERSION')
const GLOBAL_SETTINGS = join(homedir(), '.claude', 'settings.json')

class UpdateError extends Error {}

const quote = (arg) => `"${arg.replaceAll('"', '\\"')}"`

// The CLI is `aspire.exe` on Windows when installed by its script, but `aspire.cmd` when installed with npm, which Node
// can only start through a shell
const runAspire = (args, options = {}) => {
  const result = spawnSync('aspire', args, { encoding: 'utf8', ...options })

  if (result.error?.code === 'ENOENT' && process.platform === 'win32') {
    return spawnSync(['aspire', ...args.map(quote)].join(' '), { encoding: 'utf8', shell: true, ...options })
  }

  return result
}

const readSettings = () => (existsSync(GLOBAL_SETTINGS) ? readFileSync(GLOBAL_SETTINGS) : undefined)

const hash = (contents) => (contents ? createHash('sha256').update(contents).digest('hex') : undefined)

// Puts the global settings back as they were before `aspire agent init` ran, byte for byte; true if they'd changed
const restoreSettings = (original) => {
  if (hash(readSettings()) === hash(original)) {
    return false
  }

  if (original) {
    writeFileSync(GLOBAL_SETTINGS, original)
  } else {
    rmSync(GLOBAL_SETTINGS, { force: true })
  }

  return true
}

const cliVersion = () => {
  const result = runAspire(['--version'])

  if (result.error || result.status !== 0) {
    throw new UpdateError('The Aspire CLI isn\'t installed (or isn\'t on the PATH): see https://aspire.dev/get-started/install-cli/')
  }

  // The first line, without its commit hash (`13.6.4+c89352…`), in case the CLI adds a notice after it
  const version = result.stdout.trim().split(/\r?\n/)[0].split('+')[0]

  if (!/^\d+\.\d+\.\d+/.test(version)) {
    throw new UpdateError(`Couldn't read the Aspire CLI's version from "aspire --version": got "${version}".`)
  }

  return version
}

// Node exits straight away on Ctrl+C, skipping the `finally` that puts the global settings back; with a listener it
// carries on, the CLI (which gets the Ctrl+C too) stops, and the install fails and is cleaned up like any other failure
const ignoreInterrupt = () => {}

// Installs the skills into `workspace`, with the CLI's home folder pointed at `home`
const installSkills = (home, workspace) => {
  process.on('SIGINT', ignoreInterrupt)

  const init = runAspire(
    ['agent', 'init', '--workspace-root', workspace, '--skill-locations', 'claudecode', '--skills', SKILLS.join(','), '--mcp=false', '--non-interactive'],
    { stdio: 'inherit', env: { ...process.env, HOME: home, USERPROFILE: home } }
  )

  process.off('SIGINT', ignoreInterrupt)

  if (init.error || init.status !== 0) {
    throw new UpdateError('aspire agent init failed; the skills in .claude/skills/ are unchanged.')
  }

  const installed = join(workspace, '.claude', 'skills')
  const missing = SKILLS.filter((skill) => !existsSync(join(installed, skill, 'SKILL.md')))

  if (missing.length > 0) {
    throw new UpdateError(`aspire agent init didn't write ${missing.join(', ')}; the skills in .claude/skills/ are unchanged.`)
  }

  return installed
}

const update = () => {
  const version = cliVersion()
  // A TypeScript AppHost records its SDK version in aspire.config.json; a C# one doesn't have the file
  const sdkVersion = existsSync('aspire.config.json') ? JSON.parse(readFileSync('aspire.config.json', 'utf8')).sdk?.version : undefined

  if (sdkVersion && sdkVersion !== version) {
    console.warn(`Warning: the Aspire CLI is ${version} but aspire.config.json's SDK is ${sdkVersion}; the skills come from the CLI.`)
  }

  const settingsBefore = readSettings()
  const temp = mkdtempSync(join(tmpdir(), 'aspire-skills-'))

  try {
    const home = join(temp, 'home')
    const workspace = join(temp, 'workspace')
    mkdirSync(home)
    mkdirSync(workspace)

    console.log(`Installing the skills into a temporary folder. If aspire agent init adds its telemetry hook to ${GLOBAL_SETTINGS}, the file is put back as it was afterwards.`)
    const installed = installSkills(home, workspace)

    for (const skill of SKILLS) {
      rmSync(join(SKILLS_DIR, skill), { recursive: true, force: true })
      cpSync(join(installed, skill), join(SKILLS_DIR, skill), { recursive: true })
    }

    writeFileSync(VERSION_FILE, `${version}\n`)
  } finally {
    rmSync(temp, { recursive: true, force: true })

    if (restoreSettings(settingsBefore)) {
      console.log(`Put ${GLOBAL_SETTINGS} back as it was, without the hook aspire agent init added.`)
    }

    if (hash(readSettings()) !== hash(settingsBefore)) {
      // Thrown from `finally`, so it replaces any install error: the settings are the more urgent problem
      throw new UpdateError(`${GLOBAL_SETTINGS} couldn't be put back as it was: check it for an Aspire hook (track-telemetry) and remove it.`)
    }
  }

  console.log(`Updated ${SKILLS.join(', ')} in .claude/skills/ from Aspire ${version}. Review the diff before committing it.`)
}

try {
  update()
} catch (error) {
  if (!(error instanceof UpdateError)) {
    throw error
  }

  console.error(error.message)
  process.exitCode = 1
}
