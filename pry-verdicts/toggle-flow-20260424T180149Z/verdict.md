---
spec: /Users/Dom/Projects/NeimadWorks/pry/Fixtures/DemoApp/flows/toggle.md
id: toggle-flow
app: fr.neimad.pry.demoapp
status: passed
duration: 0.9s
steps_total: 10
steps_passed: 10
failed_at_step: null
pry_version: 0.1.0-dev
pry_spec_version: 1
started_at: 2026-04-24T18:01:49Z
finished_at: 2026-04-24T18:01:49Z
---

# Verdict — toggle-flow

**Status: PASSED** (10/10 steps, 895ms)

- ✅ Step 1 — `launch` (217ms)
- ✅ Step 2 — `wait_for (timeout 5.0s): window title_matches="DemoApp"` (101ms)
- ✅ Step 3 — `assert_state DocumentListVM.verbose equals false` (0ms)
- ✅ Step 4 — `click { id: "verbose_toggle" }` (141ms)
- ✅ Step 5 — `sleep 0.15s` (153ms)
- ✅ Step 6 — `assert_state DocumentListVM.verbose equals true` (0ms)
- ✅ Step 7 — `click { id: "verbose_toggle" }` (76ms)
- ✅ Step 8 — `sleep 0.15s` (153ms)
- ✅ Step 9 — `assert_state DocumentListVM.verbose equals false` (0ms)
- ✅ Step 10 — `terminate` (53ms)
