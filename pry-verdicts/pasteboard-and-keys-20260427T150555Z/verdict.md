---
spec: /Users/Dom/Projects/NeimadWorks/pry/Fixtures/DemoApp/flows/pasteboard-and-keys.md
id: pasteboard-and-keys
app: fr.neimad.pry.demoapp
status: passed
duration: 0.8s
steps_total: 12
steps_passed: 12
failed_at_step: null
pry_version: 0.1.0-dev
pry_spec_version: 1
started_at: 2026-04-27T15:05:55Z
finished_at: 2026-04-27T15:05:56Z
---

# Verdict — pasteboard-and-keys

**Status: PASSED** (12/12 steps, 802ms)

- ✅ Step 1 — `launch` (213ms)
- ✅ Step 2 — `wait_for (timeout 5.0s): window title_matches="DemoApp"` (100ms)
- ✅ Step 3 — `write_pasteboard "Pasted from harness"` (0ms)
- ✅ Step 4 — `click { id: "doc_name_field" }` (136ms)
- ✅ Step 5 — `sleep 0.1s` (106ms)
- ✅ Step 6 — `paste` (0ms)
- ✅ Step 7 — `wait_for (timeout 1.0s): DocumentListVM.draftName equals "Pasted from harness"` (84ms)
- ✅ Step 8 — `key "delete" ×19` (3ms)
- ✅ Step 9 — `sleep 0.1s` (104ms)
- ✅ Step 10 — `assert_state DocumentListVM.draftName equals ""` (0ms)
- ✅ Step 11 — `assert_pasteboard contains "Pasted from harness"` (0ms)
- ✅ Step 12 — `terminate` (55ms)
