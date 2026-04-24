---
id: text-field-flow
app: fr.neimad.pry.demoapp
executable_path: /Users/Dom/Projects/NeimadWorks/pry/Fixtures/DemoApp/.build/debug/DemoApp
description: "Type into the draft-name field, observe state, clear, retype."
tags: [smoke, text-input]
timeout: 30s
---

# Text field typing

```pry
launch
wait_for: { role: Window, title_matches: "DemoApp" }
assert_state: { viewmodel: DocumentListVM, path: "draftName", equals: "" }
click: { id: "doc_name_field" }
sleep: 100ms
type: "Ma composition"
sleep: 100ms
assert_state: { viewmodel: DocumentListVM, path: "draftName", equals: "Ma composition" }
terminate
```
