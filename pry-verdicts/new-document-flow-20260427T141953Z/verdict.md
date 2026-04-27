---
spec: /Users/Dom/Projects/NeimadWorks/pry/Fixtures/DemoApp/flows/new-document.md
id: new-document-flow
app: fr.neimad.pry.demoapp
status: passed
duration: 1.0s
steps_total: 11
steps_passed: 11
failed_at_step: null
pry_version: 0.1.0-dev
pry_spec_version: 1
started_at: 2026-04-27T14:19:53Z
finished_at: 2026-04-27T14:19:54Z
---

# Verdict — new-document-flow

**Status: PASSED** (11/11 steps, 1.0s)

- ✅ Step 1 — `launch` (218ms)
- ✅ Step 2 — `wait_for (timeout 5.0s): window title_matches="DemoApp"` (318ms)
- ✅ Step 3 — `assert_state DocumentListVM.documents.count equals 0` (0ms)
- ✅ Step 4 — `assert_state DocumentListVM.clickCount equals 0` (0ms)
- ✅ Step 5 — `click { id: "new_doc_button" }` (148ms)
- ✅ Step 6 — `click { id: "new_doc_button" }` (107ms)
- ✅ Step 7 — `click { id: "new_doc_button" }` (69ms)
- ✅ Step 8 — `wait_for (timeout 2.0s): DocumentListVM.documents.count equals 3` (84ms)
- ✅ Step 9 — `assert_state DocumentListVM.clickCount equals 3` (0ms)
- ✅ Step 10 — `assert_tree: contains { role: AXButton, label: "New Document" }` (19ms)
- ✅ Step 11 — `terminate` (52ms)
