---
spec: /Users/Dom/Projects/NeimadWorks/pry/Fixtures/DemoApp/flows/clock-advance.md
id: clock-advance-flow
app: fr.neimad.pry.demoapp
status: passed
duration: 0.7s
steps_total: 9
steps_passed: 9
failed_at_step: null
pry_version: 0.1.0-dev
pry_spec_version: 1
started_at: 2026-04-27T14:19:39Z
finished_at: 2026-04-27T14:19:39Z
---

# Verdict — clock-advance-flow

**Status: PASSED** (9/9 steps, 657ms)

- ✅ Step 1 — `launch` (216ms)
- ✅ Step 2 — `wait_for (timeout 5.0s): window title_matches="DemoApp"` (99ms)
- ✅ Step 3 — `assert_state DocumentListVM.scheduledFiredCount equals 0` (0ms)
- ✅ Step 4 — `click { id: "schedule_button" }` (194ms)
- ✅ Step 5 — `wait_for (timeout 2.0s): DocumentListVM.scheduleRequestedCount equals 1` (84ms)
- ✅ Step 6 — `clock.advance 6.0s` (1ms)
- ✅ Step 7 — `wait_for (timeout 1.0s): DocumentListVM.scheduledFiredCount equals 1` (10ms)
- ✅ Step 8 — `assert_state DocumentListVM.debounceMessage equals "Scheduled work fired!"` (0ms)
- ✅ Step 9 — `terminate` (50ms)
