---
spec: /Users/Dom/Projects/NeimadWorks/pry/Fixtures/DemoApp/flows/toggle.md
id: toggle-flow
app: fr.neimad.pry.demoapp
status: errored
duration: 0.0s
steps_total: 10
steps_passed: 0
failed_at_step: null
pry_version: 0.1.0-dev
pry_spec_version: 1
started_at: 2026-04-24T18:00:59Z
finished_at: 2026-04-24T18:00:59Z
error_kind: internal
---

# Verdict — toggle-flow

**Status: ERRORED**

**Error kind:** `internal`

**Message:** connect(/tmp/pry-fr.neimad.pry.demoapp.sock) failed: errno=61 (harness not listening?)

- ⚠️ Step 1 — `launch` (2ms) — connect(/tmp/pry-fr.neimad.pry.demoapp.sock) failed: errno=61 (harness not listening?)
- ⏭ Step 2 — `wait_for (timeout 5.0s): window title_matches="DemoApp"` (0ms)
- ⏭ Step 3 — `assert_state DocumentListVM.verbose equals false` (0ms)
- ⏭ Step 4 — `click { id: "verbose_toggle" }` (0ms)
- ⏭ Step 5 — `sleep 0.15s` (0ms)
- ⏭ Step 6 — `assert_state DocumentListVM.verbose equals true` (0ms)
- ⏭ Step 7 — `click { id: "verbose_toggle" }` (0ms)
- ⏭ Step 8 — `sleep 0.15s` (0ms)
- ⏭ Step 9 — `assert_state DocumentListVM.verbose equals false` (0ms)
- ⏭ Step 10 — `terminate` (0ms)
