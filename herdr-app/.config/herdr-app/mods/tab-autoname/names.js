// Pure naming rules, ported from herdr-automatic-rename: task (folder ⎇ branch).
const BRANCH_ICON = "⎇";
const TRUNKS = ["main", "master", "develop", "trunk"];
const IGNORED_TITLES = ["claude", "claude code", "codex", "codex cli", "gemini cli", "opencode", "amp code", "cursor agent", "new session", "untitled"];

function cut(text, max) {
  if (text.length <= max) return text;
  const head = text.slice(0, max);
  const space = head.lastIndexOf(" ");
  return (space > max / 2 ? head.slice(0, space) : head).trimEnd() + "…";
}

// Paths may be Windows ones (C:\Users\me\src) or Unix ones, whichever machine the tab is on.
const SEPARATORS = /[\\/]+/;

// The app's home is only this computer's, so another machine's home is recognised by its usual shape.
function isHomeFolder(path, home) {
  return path === home || /^(\/home\/[^/]+|\/root|\/Users\/[^/]+|[a-z]:[\\/]users[\\/][^\\/]+)$/i.test(path);
}

export function folderLabel(cwd, home) {
  if (!cwd) return null;
  const path = cwd.replace(/[\\/]+$/, "") || cwd;
  if (isHomeFolder(path, home)) return "~";
  return cut(path.split(SEPARATORS).pop() || path, 16);
}

export function branchLabel(branch) {
  if (!branch || TRUNKS.includes(branch)) return null;
  if (branch.length <= 16) return branch;
  const ticket = branch.match(/[A-Za-z]+-\d+/);
  return ticket ? ticket[0].toUpperCase() : cut(branch.split("/").pop(), 16);
}

// An agent's title only counts when it describes work, not the agent or its folder.
export function taskLabel(title, cwd) {
  // Agents lead with a spinner glyph that changes constantly.
  const clean = (title ?? "").replace(/^[^\p{L}\p{N}~\/.]+/u, "").trim();
  const lower = clean.toLowerCase();
  const dir = cwd?.split(SEPARATORS).pop()?.toLowerCase();
  if (!clean || /^\d+$/.test(clean) || IGNORED_TITLES.includes(lower) || lower === dir) return null;
  if (!/\s/.test(clean) && SEPARATORS.test(clean)) return null;
  return cut(clean, 32);
}

// Which pane speaks for a tab: its agent, else a running program, else its first shell.
export function tabName(panes, home) {
  const terminals = panes.filter((p) => p.terminal);
  const pane = terminals.find((p) => p.program?.agent || p.status) ?? terminals.find((p) => !p.program?.shell) ?? terminals[0];
  if (!pane) return null;
  const isAgent = pane.program?.agent || pane.status;
  const activity = isAgent
    ? taskLabel(pane.title, pane.cwd) ?? pane.program?.name
    : pane.program?.shell ? null : pane.program?.name;
  const branch = branchLabel(pane.branch);
  const where = [folderLabel(pane.cwd, home), branch && `${BRANCH_ICON} ${branch}`].filter(Boolean).join(" ");
  if (!activity) return where || null;
  return where ? `${cut(activity, 32)} (${where})` : cut(activity, 32);
}
