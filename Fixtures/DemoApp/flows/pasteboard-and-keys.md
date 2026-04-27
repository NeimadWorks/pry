---
id: pasteboard-and-keys
app: fr.neimad.pry.demoapp
executable_path: /Users/Dom/Projects/NeimadWorks/pry/Fixtures/DemoApp/.build/debug/DemoApp
description: "Pasteboard write/read + cmd+v paste + key repeat into the draft field."
tags: [smoke, wave3]
animations: off
timeout: 15s
---

# Pasteboard, paste, key repeat

```pry
launch
wait_for: { role: Window, title_matches: "DemoApp" }

# Seed the pasteboard via the harness, then paste it into the focused field.
write_pasteboard: "Pasted from harness"
click: { id: "doc_name_field" }
sleep: 100ms
paste

wait_for:
  state: { viewmodel: DocumentListVM, path: "draftName", equals: "Pasted from harness" }
  timeout: 1s

# Erase via key repeat (delete 19 chars).
key: { combo: "delete", repeat: 19 }
sleep: 100ms
assert_state: { viewmodel: DocumentListVM, path: "draftName", equals: "" }

# Verify pasteboard read works.
assert_pasteboard: "Pasted from harness"

terminate
```
