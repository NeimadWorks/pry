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
started_at: 2026-04-27T15:05:57Z
finished_at: 2026-04-27T15:05:58Z
---

# Verdict — toggle-flow

**Status: PASSED** (10/10 steps, 982ms)

- ✅ Step 1 — `launch` (317ms)
- ✅ Step 2 — `wait_for (timeout 5.0s): window title_matches="DemoApp"` (77ms)
- ✅ Step 3 — `assert_state DocumentListVM.verbose equals false` (0ms)
- ✅ Step 4 — `click { id: "verbose_toggle" }` (138ms)
- ✅ Step 5 — `sleep 0.15s` (152ms)
- ✅ Step 6 — `assert_state DocumentListVM.verbose equals true` (1ms)
- ✅ Step 7 — `click { id: "verbose_toggle" }` (89ms)
- ✅ Step 8 — `sleep 0.15s` (152ms)
- ✅ Step 9 — `assert_state DocumentListVM.verbose equals false` (0ms)
- ✅ Step 10 — `terminate` (55ms)
