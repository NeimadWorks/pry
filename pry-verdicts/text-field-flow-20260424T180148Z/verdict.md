---
spec: /Users/Dom/Projects/NeimadWorks/pry/Fixtures/DemoApp/flows/text-field.md
id: text-field-flow
app: fr.neimad.pry.demoapp
status: passed
duration: 0.9s
steps_total: 9
steps_passed: 9
failed_at_step: null
pry_version: 0.1.0-dev
pry_spec_version: 1
started_at: 2026-04-24T18:01:48Z
finished_at: 2026-04-24T18:01:49Z
---

# Verdict — text-field-flow

**Status: PASSED** (9/9 steps, 926ms)

- ✅ Step 1 — `launch` (270ms)
- ✅ Step 2 — `wait_for (timeout 5.0s): window title_matches="DemoApp"` (146ms)
- ✅ Step 3 — `assert_state DocumentListVM.draftName equals ""` (1ms)
- ✅ Step 4 — `click { id: "doc_name_field" }` (249ms)
- ✅ Step 5 — `sleep 0.1s` (102ms)
- ✅ Step 6 — `type "Ma composition"` (0ms)
- ✅ Step 7 — `sleep 0.1s` (101ms)
- ✅ Step 8 — `assert_state DocumentListVM.draftName equals "Ma composition"` (2ms)
- ✅ Step 9 — `terminate` (54ms)
