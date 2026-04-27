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
started_at: 2026-04-27T14:26:02Z
finished_at: 2026-04-27T14:26:03Z
---

# Verdict — toggle-flow

**Status: PASSED** (10/10 steps, 941ms)

- ✅ Step 1 — `launch` (271ms)
- ✅ Step 2 — `wait_for (timeout 5.0s): window title_matches="DemoApp"` (71ms)
- ✅ Step 3 — `assert_state DocumentListVM.verbose equals false` (0ms)
- ✅ Step 4 — `click { id: "verbose_toggle" }` (149ms)
- ✅ Step 5 — `sleep 0.15s` (157ms)
- ✅ Step 6 — `assert_state DocumentListVM.verbose equals true` (0ms)
- ✅ Step 7 — `click { id: "verbose_toggle" }` (83ms)
- ✅ Step 8 — `sleep 0.15s` (153ms)
- ✅ Step 9 — `assert_state DocumentListVM.verbose equals false` (0ms)
- ✅ Step 10 — `terminate` (55ms)
