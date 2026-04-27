---
id: import-export-flow
app: fr.neimad.pry.demoapp
executable_path: /Users/Dom/Projects/NeimadWorks/pry/Fixtures/DemoApp/.build/debug/DemoApp
description: "Drive NSOpenPanel + NSSavePanel via Pry's panel helpers."
tags: [smoke, panels]
animations: off
timeout: 30s
vars:
  fixture_dir: "/tmp/pry-import-export"
---

# Import / Export panel flow

Demonstrates Wave-1 file panel helpers:
- `open_file: PATH` — drives an `NSOpenPanel` to select a specific file
- `save_file: PATH` — drives an `NSSavePanel` to write at a specific location
- Both work whether the panel attaches as a sheet or a separate window.

```pry setup
launch
wait_for: { role: Window, title_matches: "DemoApp" }
```

## Import a file via NSOpenPanel

Pre-condition: a known file exists on disk. We don't use `with_fs` here so the
absolute path is hard-coded; in real specs you'd declare `with_fs:` and use
`${fixture_dir}/sample.txt`.

```pry
write_pasteboard: "ignored"

# Click "Import…" — the app opens an NSOpenPanel.
click: { id: "import_button" }

# Drive the open panel to /etc/hosts (always present on macOS — convenient
# for a deterministic test that doesn't require a fixture file).
open_file: "/etc/hosts"

wait_for:
  state: { viewmodel: DocumentListVM, path: "lastImportedURL", matches: ".*/etc/hosts$" }
  timeout: 3s
```

## Export to a temp file via NSSavePanel

```pry
click: { id: "export_button" }

# Drive the save panel to a unique tmp path. The helper navigates to /tmp
# via Cmd+Shift+G, fills the name field, and clicks Save.
save_file: "/tmp/pry-export-demo.txt"

wait_for:
  state: { viewmodel: DocumentListVM, path: "lastExportedURL", matches: ".*/pry-export-demo\\.txt$" }
  timeout: 3s
```

```pry teardown
terminate
```
