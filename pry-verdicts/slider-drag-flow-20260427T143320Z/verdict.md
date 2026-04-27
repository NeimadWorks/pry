---
spec: /Users/Dom/Projects/NeimadWorks/pry/Fixtures/DemoApp/flows/slider-drag.md
id: slider-drag-flow
app: fr.neimad.pry.demoapp
status: passed
duration: 0.7s
steps_total: 6
steps_passed: 6
failed_at_step: null
pry_version: 0.1.0-dev
pry_spec_version: 1
started_at: 2026-04-27T14:33:20Z
finished_at: 2026-04-27T14:33:21Z
---

# Verdict — slider-drag-flow

**Status: PASSED** (6/6 steps, 705ms)

- ✅ Step 1 — `launch` (216ms)
- ✅ Step 2 — `wait_for (timeout 5.0s): window title_matches="DemoApp"` (97ms)
- ✅ Step 3 — `assert_state DocumentListVM.intensity equals 0` (0ms)
- ✅ Step 4 — `drag from { id: "intensity_slider" } to { id: "intensity_label" }` (338ms)
- ✅ Step 5 — `wait_for (timeout 2.0s): DocumentListVM.intensity any_of [50, 60, 70, 80, 90, 100]` (0ms)
- ✅ Step 6 — `terminate` (53ms)
