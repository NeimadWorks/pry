---
id: expect-change-flow
app: fr.neimad.pry.demoapp
executable_path: /Users/Dom/Projects/NeimadWorks/pry/Fixtures/DemoApp/.build/debug/DemoApp
description: "Atomic do-then-observe shortcut against documents.count."
tags: [smoke]
timeout: 15s
---

# expect_change flow

```pry
launch
wait_for: { role: Window, title_matches: "DemoApp" }
expect_change:
  action: { click: { id: "new_doc_button" } }
  in: { viewmodel: DocumentListVM, path: "documents.count" }
  to: 1
  timeout: 1s
expect_change:
  action: { click: { id: "verbose_toggle" } }
  in: { viewmodel: DocumentListVM, path: "verbose" }
  to: true
  timeout: 1s
terminate
```
