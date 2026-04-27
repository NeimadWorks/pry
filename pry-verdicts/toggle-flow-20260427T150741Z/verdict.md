---
spec: /Users/Dom/Projects/NeimadWorks/pry/Fixtures/DemoApp/flows/toggle.md
id: toggle-flow
app: fr.neimad.pry.demoapp
status: passed
duration: 1.0s
steps_total: 10
steps_passed: 10
failed_at_step: null
pry_version: 0.1.0-dev
pry_spec_version: 1
started_at: 2026-04-27T15:07:41Z
finished_at: 2026-04-27T15:07:42Z
---

# Verdict — toggle-flow

**Status: PASSED** (10/10 steps, 964ms)

- ✅ Step 1 — `launch` (269ms)
- ✅ Step 2 — `wait_for (timeout 5.0s): window title_matches="DemoApp"` (87ms)
- ✅ Step 3 — `assert_state DocumentListVM.verbose equals false` (0ms)
- ✅ Step 4 — `click { id: "verbose_toggle" }` (150ms)
- ✅ Step 5 — `sleep 0.15s` (160ms)
- ✅ Step 6 — `assert_state DocumentListVM.verbose equals true` (0ms)
- ✅ Step 7 — `click { id: "verbose_toggle" }` (86ms)
- ✅ Step 8 — `sleep 0.15s` (155ms)
- ✅ Step 9 — `assert_state DocumentListVM.verbose equals false` (0ms)
- ✅ Step 10 — `terminate` (55ms)
