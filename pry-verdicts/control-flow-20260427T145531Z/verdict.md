---
spec: /Users/Dom/Projects/NeimadWorks/pry/Fixtures/DemoApp/flows/control-flow.md
id: control-flow
app: fr.neimad.pry.demoapp
status: passed
duration: 1.1s
steps_total: 6
steps_passed: 6
failed_at_step: null
pry_version: 0.1.0-dev
pry_spec_version: 1
started_at: 2026-04-27T14:55:31Z
finished_at: 2026-04-27T14:55:32Z
---

# Verdict — control-flow

**Status: PASSED** (6/6 steps, 1.1s)

- ✅ Step 1 — `[setup] launch` (443ms)
- ✅ Step 2 — `[setup] wait_for (timeout 5.0s): window title_matches="DemoApp"` (190ms)
- ✅ Step 3 — `[setup] assert_state DocumentListVM.documents.count equals 0` (15ms)
- ✅ Step 4 — `call tap_n_times` (343ms)
- ✅ Step 5 — `wait_for (timeout 1.0s): DocumentListVM.documents.count equals 3` (82ms)
- ✅ Step 6 — `[teardown] terminate` (55ms)
