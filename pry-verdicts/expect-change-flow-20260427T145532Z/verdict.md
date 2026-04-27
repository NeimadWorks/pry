---
spec: /Users/Dom/Projects/NeimadWorks/pry/Fixtures/DemoApp/flows/expect-change.md
id: expect-change-flow
app: fr.neimad.pry.demoapp
status: passed
duration: 0.8s
steps_total: 5
steps_passed: 5
failed_at_step: null
pry_version: 0.1.0-dev
pry_spec_version: 1
started_at: 2026-04-27T14:55:32Z
finished_at: 2026-04-27T14:55:33Z
---

# Verdict — expect-change-flow

**Status: PASSED** (5/5 steps, 842ms)

- ✅ Step 1 — `launch` (270ms)
- ✅ Step 2 — `wait_for (timeout 5.0s): window title_matches="DemoApp"` (76ms)
- ✅ Step 3 — `expect_change click { id: "new_doc_button" } → DocumentListVM.documents.count = 1` (259ms)
- ✅ Step 4 — `expect_change click { id: "verbose_toggle" } → DocumentListVM.verbose = true` (183ms)
- ✅ Step 5 — `terminate` (55ms)
