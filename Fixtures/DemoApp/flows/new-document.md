---
id: new-document-flow
app: fr.neimad.pry.demoapp
executable_path: /Users/Dom/Projects/NeimadWorks/pry/Fixtures/DemoApp/.build/debug/DemoApp
description: "Click the New Document button and verify the document list grows."
tags: [smoke, documents]
timeout: 30s
---

# New document flow

Exercise the golden path: launch the fixture app, click the "New Document"
button, and assert the ViewModel saw the click.

## Preconditions

```pry
launch
wait_for: { role: Window, title_matches: "DemoApp" }
```

## Starting state

```pry
assert_state: { viewmodel: DocumentListVM, path: "documents.count", equals: 0 }
assert_state: { viewmodel: DocumentListVM, path: "clickCount", equals: 0 }
```

## Create three documents

```pry
click: { id: "new_doc_button" }
click: { id: "new_doc_button" }
click: { id: "new_doc_button" }
```

## Verify outcome

CGEvent → AppKit → SwiftUI main-actor is asynchronous. Use `wait_for` on the
state predicate so the assertion doesn't race the last click.

```pry
wait_for: { state: { viewmodel: DocumentListVM, path: "documents.count", equals: 3 } }
  timeout: 2s
assert_state: { viewmodel: DocumentListVM, path: "clickCount", equals: 3 }
assert_tree: { contains: { role: AXButton, label: "New Document" } }
terminate
```
