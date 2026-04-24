---
spec: /Users/Dom/Projects/NeimadWorks/pry/Fixtures/DemoApp/flows/text-field.md
id: text-field-flow
app: fr.neimad.pry.demoapp
status: passed
duration: 0.7s
steps_total: 9
steps_passed: 9
failed_at_step: null
pry_version: 0.1.0-dev
pry_spec_version: 1
started_at: 2026-04-24T18:07:08Z
finished_at: 2026-04-24T18:07:09Z
---

# Verdict — text-field-flow

**Status: PASSED** (9/9 steps, 747ms)

- ✅ Step 1 — `launch` (267ms)
- ✅ Step 2 — `wait_for (timeout 5.0s): window title_matches="DemoApp"` (73ms)
- ✅ Step 3 — `assert_state DocumentListVM.draftName equals ""` (0ms)
- ✅ Step 4 — `click { id: "doc_name_field" }` (141ms)
- ✅ Step 5 — `sleep 0.1s` (104ms)
- ✅ Step 6 — `type "Ma composition"` (0ms)
- ✅ Step 7 — `sleep 0.1s` (106ms)
- ✅ Step 8 — `assert_state DocumentListVM.draftName equals "Ma composition"` (1ms)
- ✅ Step 9 — `terminate` (56ms)
