---
spec: /Users/Dom/Projects/NeimadWorks/pry/Fixtures/DemoApp/flows/clock-advance.md
id: clock-advance-flow
app: fr.neimad.pry.demoapp
status: passed
duration: 1.2s
steps_total: 9
steps_passed: 9
failed_at_step: null
pry_version: 0.1.0-dev
pry_spec_version: 1
started_at: 2026-04-27T14:19:31Z
finished_at: 2026-04-27T14:19:32Z
---

# Verdict — clock-advance-flow

**Status: PASSED** (9/9 steps, 1.2s)

- ✅ Step 1 — `launch` (757ms)
- ✅ Step 2 — `wait_for (timeout 5.0s): window title_matches="DemoApp"` (105ms)
- ✅ Step 3 — `assert_state DocumentListVM.scheduledFiredCount equals 0` (1ms)
- ✅ Step 4 — `click { id: "schedule_button" }` (202ms)
- ✅ Step 5 — `wait_for (timeout 2.0s): DocumentListVM.scheduleRequestedCount equals 1` (87ms)
- ✅ Step 6 — `clock.advance 6.0s` (1ms)
- ✅ Step 7 — `wait_for (timeout 1.0s): DocumentListVM.scheduledFiredCount equals 1` (11ms)
- ✅ Step 8 — `assert_state DocumentListVM.debounceMessage equals "Scheduled work fired!"` (0ms)
- ✅ Step 9 — `terminate` (55ms)
