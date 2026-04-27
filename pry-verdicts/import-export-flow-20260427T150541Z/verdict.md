---
spec: /Users/Dom/Projects/NeimadWorks/pry/Fixtures/DemoApp/flows/import-export.md
id: import-export-flow
app: fr.neimad.pry.demoapp
status: passed
duration: 13.1s
steps_total: 10
steps_passed: 10
failed_at_step: null
pry_version: 0.1.0-dev
pry_spec_version: 1
started_at: 2026-04-27T15:05:41Z
finished_at: 2026-04-27T15:05:54Z
---

# Verdict — import-export-flow

**Status: PASSED** (10/10 steps, 13.1s)

- ✅ Step 1 — `[setup] launch` (218ms)
- ✅ Step 2 — `[setup] wait_for (timeout 5.0s): window title_matches="DemoApp"` (116ms)
- ✅ Step 3 — `write_pasteboard "ignored"` (0ms)
- ✅ Step 4 — `click { id: "import_button" }` (145ms)
- ✅ Step 5 — `open_file "/etc/hosts"` (10.0s)
- ✅ Step 6 — `wait_for (timeout 3.0s): DocumentListVM.lastImportedURL matches /.*/etc/hosts$/` (250ms)
- ✅ Step 7 — `click { id: "export_button" }` (517ms)
- ✅ Step 8 — `save_file "/tmp/pry-export-demo.txt"` (1.7s)
- ✅ Step 9 — `wait_for (timeout 3.0s): DocumentListVM.lastExportedURL matches /.*/pry-export-demo\.txt$/` (85ms)
- ✅ Step 10 — `[teardown] terminate` (54ms)
