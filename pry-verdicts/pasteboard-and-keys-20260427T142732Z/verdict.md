---
spec: /Users/Dom/Projects/NeimadWorks/pry/Fixtures/DemoApp/flows/pasteboard-and-keys.md
id: pasteboard-and-keys
app: fr.neimad.pry.demoapp
status: passed
duration: 1.1s
steps_total: 12
steps_passed: 12
failed_at_step: null
pry_version: 0.1.0-dev
pry_spec_version: 1
started_at: 2026-04-27T14:27:32Z
finished_at: 2026-04-27T14:27:33Z
---

# Verdict — pasteboard-and-keys

**Status: PASSED** (12/12 steps, 1.1s)

- ✅ Step 1 — `launch` (387ms)
- ✅ Step 2 — `wait_for (timeout 5.0s): window title_matches="DemoApp"` (108ms)
- ✅ Step 3 — `write_pasteboard "Pasted from harness"` (1ms)
- ✅ Step 4 — `click { id: "doc_name_field" }` (208ms)
- ✅ Step 5 — `sleep 0.1s` (107ms)
- ✅ Step 6 — `paste` (0ms)
- ✅ Step 7 — `wait_for (timeout 1.0s): DocumentListVM.draftName equals "Pasted from harness"` (86ms)
- ✅ Step 8 — `key "delete" ×19` (2ms)
- ✅ Step 9 — `sleep 0.1s` (107ms)
- ✅ Step 10 — `assert_state DocumentListVM.draftName equals ""` (1ms)
- ✅ Step 11 — `assert_pasteboard contains "Pasted from harness"` (1ms)
- ✅ Step 12 — `terminate` (55ms)
