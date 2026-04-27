---
spec: /Users/Dom/Projects/NeimadWorks/pry/Fixtures/DemoApp/flows/slider-drag.md
id: slider-drag-flow
app: fr.neimad.pry.demoapp
status: passed
duration: 0.8s
steps_total: 6
steps_passed: 6
failed_at_step: null
pry_version: 0.1.0-dev
pry_spec_version: 1
started_at: 2026-04-27T01:19:27Z
finished_at: 2026-04-27T01:19:28Z
---

# Verdict — slider-drag-flow

**Status: PASSED** (6/6 steps, 822ms)

- ✅ Step 1 — `launch` (271ms)
- ✅ Step 2 — `wait_for (timeout 5.0s): window title_matches="DemoApp"` (65ms)
- ✅ Step 3 — `assert_state DocumentListVM.intensity equals 0` (0ms)
- ✅ Step 4 — `drag from { id: "intensity_slider" } to { id: "intensity_label" }` (428ms)
- ✅ Step 5 — `wait_for (timeout 2.0s): DocumentListVM.intensity any_of [50, 60, 70, 80, 90, 100]` (0ms)
- ✅ Step 6 — `terminate` (55ms)
