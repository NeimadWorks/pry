---
id: control-flow
app: fr.neimad.pry.demoapp
executable_path: /Users/Dom/Projects/NeimadWorks/pry/Fixtures/DemoApp/.build/debug/DemoApp
description: "Demonstrate variables, loops, and a sub-flow."
tags: [smoke, grammar]
vars: { initial_count: 0 }
timeout: 15s
---

# Control flow demo

Wave 2 grammar: setup/teardown blocks, variables, repeat loops, and a
named flow callable from main.

```pry setup
launch
wait_for: { role: Window, title_matches: "DemoApp" }
assert_state: { viewmodel: DocumentListVM, path: "documents.count", equals: ${initial_count} }
```

```pry flow tap_n_times(n)
repeat: 3
  - click: { id: "new_doc_button" }
```

```pry
call: tap_n_times
wait_for:
  state: { viewmodel: DocumentListVM, path: "documents.count", equals: 3 }
  timeout: 1s
```

```pry teardown
terminate
```
