---
spec: /Users/Dom/Projects/NeimadWorks/pry/Fixtures/DemoApp/flows/import-export.md
id: import-export-flow
app: fr.neimad.pry.demoapp
status: passed
duration: 13.8s
steps_total: 10
steps_passed: 10
failed_at_step: null
pry_version: 0.1.0-dev
pry_spec_version: 1
started_at: 2026-04-27T15:05:07Z
finished_at: 2026-04-27T15:05:21Z
---

# Verdict — import-export-flow

**Status: PASSED** (10/10 steps, 13.8s)

- ✅ Step 1 — `[setup] launch` (271ms)
- ✅ Step 2 — `[setup] wait_for (timeout 5.0s): window title_matches="DemoApp"` (107ms)
- ✅ Step 3 — `write_pasteboard "ignored"` (0ms)
- ✅ Step 4 — `click { id: "import_button" }` (189ms)
- ✅ Step 5 — `open_file "/etc/hosts"` (10.6s)
- ✅ Step 6 — `wait_for (timeout 3.0s): DocumentListVM.lastImportedURL matches /.*/etc/hosts$/` (254ms)
- ✅ Step 7 — `click { id: "export_button" }` (536ms)
- ✅ Step 8 — `save_file "/tmp/pry-export-demo.txt"` (1.8s)
- ✅ Step 9 — `wait_for (timeout 3.0s): DocumentListVM.lastExportedURL matches /.*/pry-export-demo\.txt$/` (86ms)
- ✅ Step 10 — `[teardown] terminate` (55ms)
