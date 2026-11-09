import { View, div } from "gpui-kit";
import { home, machines, panes, run, setShared, shared, spaces } from "herdr";
import { tabName } from "./names.js";

// Our own renames also set tab.named, so remember what we wrote: a named tab whose
// name differs from this was named by the person, and is left alone.
const STORE = "tab-autoname";

function sync() {
  const written = shared(STORE) ?? {};
  // A machine that isn't ready hides its tabs: forgetting them would make them look hand-named.
  const next = machines().every((m) => m.layout === "ready") ? {} : { ...written };
  const allPanes = panes();
  for (const space of spaces()) {
    for (const tab of space.tabs) {
      if (tab.named && tab.name !== written[tab.id]) {
        delete next[tab.id];
        continue;
      }
      const name = tabName(allPanes.filter((p) => p.tab === tab.id), home()) ?? written[tab.id];
      if (!name) continue;
      if (name !== tab.name) {
        try {
          run("tab.rename", { id: tab.id, name });
        } catch (e) {
          console.log(`tab-autoname: ${e}`);
          if (written[tab.id]) next[tab.id] = written[tab.id];
          continue;
        }
      }
      next[tab.id] = name;
    }
  }
  if (JSON.stringify(next) !== JSON.stringify(written)) setShared(STORE, next);
}

export default class TabAutoname extends View {
  init(_props, cx) {
    // Sampling rather than reacting: names settle, and a quick `ls` never flashes across the tab.
    cx.timer.every(2000, () => sync());
  }

  render() {
    return div();
  }
}
