---
id: toggle-flow
app: fr.neimad.pry.demoapp
executable_path: /Users/Dom/Projects/NeimadWorks/pry/Fixtures/DemoApp/.build/debug/DemoApp
description: "Toggle the verbose switch and observe the Bool flip."
tags: [smoke]
timeout: 15s
---

# Toggle flow

```pry
launch
wait_for: { role: Window, title_matches: "DemoApp" }
assert_state: { viewmodel: DocumentListVM, path: "verbose", equals: false }
click: { id: "verbose_toggle" }
sleep: 150ms
assert_state: { viewmodel: DocumentListVM, path: "verbose", equals: true }
click: { id: "verbose_toggle" }
sleep: 150ms
assert_state: { viewmodel: DocumentListVM, path: "verbose", equals: false }
terminate
```
