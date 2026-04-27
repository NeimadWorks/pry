---
spec: /Users/Dom/Projects/NeimadWorks/pry/Fixtures/DemoApp/flows/control-flow.md
id: control-flow
app: fr.neimad.pry.demoapp
status: passed
duration: 0.8s
steps_total: 6
steps_passed: 6
failed_at_step: null
pry_version: 0.1.0-dev
pry_spec_version: 1
started_at: 2026-04-27T14:27:08Z
finished_at: 2026-04-27T14:27:09Z
---

# Verdict — control-flow

**Status: PASSED** (6/6 steps, 789ms)

- ✅ Step 1 — `[setup] launch` (216ms)
- ✅ Step 2 — `[setup] wait_for (timeout 5.0s): window title_matches="DemoApp"` (108ms)
- ✅ Step 3 — `[setup] assert_state DocumentListVM.documents.count equals 0` (0ms)
- ✅ Step 4 — `call tap_n_times` (327ms)
- ✅ Step 5 — `wait_for (timeout 1.0s): DocumentListVM.documents.count equals 3` (86ms)
- ✅ Step 6 — `[teardown] terminate` (52ms)
