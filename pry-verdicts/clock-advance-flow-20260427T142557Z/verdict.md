---
spec: /Users/Dom/Projects/NeimadWorks/pry/Fixtures/DemoApp/flows/clock-advance.md
id: clock-advance-flow
app: fr.neimad.pry.demoapp
status: passed
duration: 0.9s
steps_total: 9
steps_passed: 9
failed_at_step: null
pry_version: 0.1.0-dev
pry_spec_version: 1
started_at: 2026-04-27T14:25:57Z
finished_at: 2026-04-27T14:25:57Z
---

# Verdict — clock-advance-flow

**Status: PASSED** (9/9 steps, 882ms)

- ✅ Step 1 — `launch` (375ms)
- ✅ Step 2 — `wait_for (timeout 5.0s): window title_matches="DemoApp"` (116ms)
- ✅ Step 3 — `assert_state DocumentListVM.scheduledFiredCount equals 0` (2ms)
- ✅ Step 4 — `click { id: "schedule_button" }` (236ms)
- ✅ Step 5 — `wait_for (timeout 2.0s): DocumentListVM.scheduleRequestedCount equals 1` (86ms)
- ✅ Step 6 — `clock.advance 6.0s` (1ms)
- ✅ Step 7 — `wait_for (timeout 1.0s): DocumentListVM.scheduledFiredCount equals 1` (9ms)
- ✅ Step 8 — `assert_state DocumentListVM.debounceMessage equals "Scheduled work fired!"` (0ms)
- ✅ Step 9 — `terminate` (54ms)
