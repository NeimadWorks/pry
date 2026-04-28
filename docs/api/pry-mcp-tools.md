# `pry-mcp` — MCP tool reference

`pry-mcp` exposes the runner over stdio JSON-RPC (MCP) and as a CLI. Every
tool listed here has a stable I/O shape and a closed set of error kinds.

**Primary path:** call `pry_run_spec` with a Markdown spec, get back a
structured verdict. The other tools are escape hatches.

For Swift-native consumption (without the MCP daemon), use the
[`PryRunner` library](PryRunner.md) directly.

---

## Lifecycle

### `pry_launch`

Launch the target app and connect to its `PryHarness` socket.

```json
// Input
{ "app": "fr.neimad.proof", "path": "/abs/path/to/binary"?, "args": []?, "env": {}? }

// Output
{ "pid": 12345, "socket": "/tmp/pry-fr.neimad.proof.sock", "harness_version": "0.1.0" }
```

Errors: `app_not_found`, `bundle_not_found`, `harness_unreachable`, `ax_permission_denied`, `launch_failed`.

### `pry_terminate`

```json
{ "app": "fr.neimad.proof" }   →   { "ok": true }
```

---

## Mouse / keyboard / gestures

### `pry_click` / `pry_double_click` / `pry_right_click`

```json
{ "app": "...", "target": <target-spec>, "modifiers": ["shift", "cmd"]? }
```

Returns:

```json
{ "resolved": { "role": "AXButton", "label": "Save", "id": "save_button", "frame": [x, y, w, h] } }
```

### `pry_long_press`

```json
{ "app": "...", "target": <target>, "dwell_ms": 800? }   →   { "ok": true }
```

### `pry_type`

```json
{ "app": "...", "text": "Hello" }   →   { "chars_sent": 5 }
```

### `pry_key`

```json
{ "app": "...", "combo": "cmd+s", "repeat": 1? }   →   { "ok": true }
```

### `pry_drag`

```json
{ "app": "...", "from": <target>, "to": <target>, "steps": 12? }   →   { "ok": true }
```

(`modifiers` not yet plumbed via MCP — use the spec runner or `PryRunner.drag(modifiers:)`.)

### `pry_scroll`

```json
{ "app": "...", "target": <target>, "direction": "up|down|left|right", "amount": 3? }   →   { "ok": true }
```

### `pry_magnify`

Pinch approximation via Option+scroll.

```json
{ "app": "...", "target": <target>, "delta": 100 }   →   { "ok": true }
```

### `pry_select_menu`

Walks an AX menu path by issuing `Press` actions on each level.

```json
{ "app": "...", "path": ["File", "Open Recent", "foo.pgn"] }   →   { "ok": true }
```

### `pry_menu_inspect`

Like `pry_select_menu` but stops at the deepest path segment, leaves the
menu open, and returns the children of that level. The introspection
counterpart — useful when you need to discover which sub-menu items
exist before writing a `select_menu:` step.

```json
{ "app": "...", "path": ["View", "View Mode"]? }
→ { "path": ["View", "View Mode"], "children": ["Icons", "List", "Grid"] }
```

Empty `path` (or omitted) returns the menu bar's top-level titles. Use
`pry_key combo: "esc"` to dismiss the menu after inspection.

### `pry_focus`

Report what's currently AX-focused. JSON dump of role, label, id, frame.

```json
{ "app": "..." }   →   { "role": "AXTextField", "label": null, "id": "name_field", "frame": [120, 340, 260, 22] }
```

Same data exposed in-spec via `dump_focus:` and `wait_for_focus:`.

### `pry_open_file`

Drive an `NSOpenPanel` to select a specific path. Sends Cmd+Shift+G,
types the path, and accepts.

```json
{ "app": "...", "path": "/abs/path/to/file.pgn" }   →   { "ok": true }
```

### `pry_save_file`

Drive an `NSSavePanel`: navigates to the path's directory, fills the name
field, accepts.

```json
{ "app": "...", "path": "/abs/path/to/output.pdf" }   →   { "ok": true }
```

### `pry_panel_accept`

Click the default action button on whatever panel is open
(sheet-attached or modal dialog window). Optional `button` to choose by name.

```json
{ "app": "...", "button": "Open"? }   →   { "ok": true }
```

### `pry_panel_cancel`

Sends Escape to the front panel.

```json
{ "app": "..." }   →   { "ok": true }
```

---

## Observation

### `pry_state`

```json
// All registered keys for one VM:
{ "app": "...", "viewmodel": "DocVM" }
→ { "keys": { "documents.count": 3, "isLoading": false } }

// Or one path:
{ "app": "...", "viewmodel": "DocVM", "path": "documents.count" }
→ { "value": 3 }
```

Errors: `viewmodel_not_registered` (with `data.registered: [...]`),
`path_not_found` (with `data.available_paths: [...]`).

### `pry_tree`

```json
{
  "app": "...",
  "window": { "title": "..."?, "title_matches": "..."? }?,
  "compact": true?    // strip `SwiftUI.ModifiedContent<...>` chains over 200 chars
}
→ { "yaml": "<full AX tree as YAML>" }
```

`compact: true` replaces label / id values longer than 200 characters
with `<swiftui-modifier-chain>`. Real SwiftUI apps generate huge
generic-type label strings; the compact form keeps the dump
grep-friendly.

### `pry_find`

Like `pry_click`'s resolution but returns *all* matches (no ambiguity error).

```json
{ "app": "...", "target": <target> }
→ { "matches": [ { "role": "...", "label": "...", "id": "...", "frame": [...], "enabled": true }, ... ] }
```

### `pry_snapshot`

```json
{ "app": "...", "path": "/tmp/out.png"? }
→ { "path": "/tmp/out.png" }
```

### `pry_logs`

Best-effort, ~1 s latency (ADR-006). For audit / diagnostic, not assertions.

```json
{ "app": "...", "since": "ISO8601"?, "subsystem": "..."? }
→ { "lines": [ { "ts": "...", "level": "info", "msg": "...", "subsystem": "...", "category": "..." }, ... ],
    "cursor": "ISO8601" }
```

---

## Time control (ADR-007)

Only affects code that uses `PryClock` (host-app opt-in).

### `pry_clock_get`

```json
{ "app": "..." }   →   { "iso8601": "...", "paused": false }
```

### `pry_clock_set`

```json
{ "app": "...", "iso8601": "2026-01-01T00:00:00Z", "paused": true? }
→ { "iso8601": "...", "fired_callbacks": 0 }
```

### `pry_clock_advance`

Fast-forward by N seconds, firing scheduled work in chronological order.

```json
{ "app": "...", "seconds": 5 }
→ { "iso8601": "...", "fired_callbacks": 1 }
```

---

## Pasteboard

### `pry_pasteboard_read`

```json
{ "app": "..." }   →   { "string": "...", "types": ["public.utf8-plain-text", ...] }
```

### `pry_pasteboard_write`

```json
{ "app": "...", "string": "..." }   →   { "ok": true }
```

---

## Animations (ADR-009)

### `pry_set_animations`

```json
{ "app": "...", "enabled": false }   →   { "enabled": false }
```

---

## Spec runner

### `pry_run_spec`

The primary path. Reads or accepts a Markdown spec, runs it end-to-end,
returns the verdict.

```json
{
  "path": "flows/foo.md",        // — or —
  "markdown": "---\nid: ...\n...",
  "verdicts_dir": "./pry-verdicts"?,
  "snapshots": "on_failure"?     // never | on_failure | every_step | always
}
→ {
  "status": "passed | failed | errored | timed_out",
  "verdict_path": "./pry-verdicts/.../verdict.md"?,
  "verdict_markdown": "---\n..."
}
```

### `pry_run_suite`

Run every `.md` spec in a directory. Aggregates and optionally exports JUnit/TAP/Markdown summary.

```json
{
  "path": "flows",
  "tag": "smoke"?,
  "verdicts_dir": "./pry-verdicts"?,
  "parallel": 4?,           // groups by app; specs hitting the same bundle ID still serialize
  "retry_failed": 1?,       // per-spec retry on non-passed status
  "junit": "out.xml"?,
  "tap": "out.tap"?,
  "summary_md": "out.md"?
}
→ {
  "total": 8,
  "passed": 8,
  "failed": 0,
  "errored": 0,
  "verdicts": [ { "spec": "...", "status": "passed", "duration": 0.7, "failed_at_step": null }, ... ]
}
```

### `pry_list_specs`

Discover specs under a directory.

```json
{ "path": "flows" }
→ { "specs": [ { "path": "...", "id": "...", "tags": [...] }, ... ] }
```

### `pry_lint`

Parse every `.md` under `path` as a Pry spec without launching any app.
Cheap CI gate — catches frontmatter typos, unknown commands, malformed
targets/predicates.

```json
{ "path": "flows", "verbose": false? }
→ {
  "total": 9,
  "ok": 9,
  "failed": 0,
  "issues": [
    { "spec": "...", "line": 12, "kind": "unknown_command", "message": "unknown command 'aseert_state'" },
    ...
  ]
}
```

### `pry_init`

Scaffold (or extend) a `.pry/config.yaml` mapping a bundle ID to a
SwiftPM product's build path.

```json
{
  "bundleID": "fr.neimad.demo",
  "product": "DemoApp",
  "directory": "."?,           // default: current working directory
  "force": false?              // override existing entry for this bundle
}
→ {
  "configPath": "/abs/.pry/config.yaml",
  "written": true,
  "contents": "apps:\n  fr.neimad.demo:\n    executable_path: ${swift_bin}/DemoApp\n"
}
```

---

## Target spec shape

Every tool that takes a `target` accepts the same six forms (precedence
high→low). Provide exactly one form (the others should be omitted):

```json
{ "id": "save_button" }
{ "role": "AXButton", "label": "Save" }
{ "label": "Save" }
{ "label_matches": "Save.*" }
{ "tree_path": "Window[0]/Group/Button[2]" }
{ "point": { "x": 120, "y": 340 } }
```

### `nth` disambiguator

Any of the above can carry an `nth: N` integer field to pick the N-th match
(0-indexed, tree pre-order) without erroring on ambiguity:

```json
{ "id": "row", "nth": 0 }                      // first match
{ "label": "Save", "nth": 2 }                  // third button labelled "Save"
```

This is the standard fix for the SwiftUI `accessibilityIdentifier`
propagation gotcha (a container's identifier appears on every descendant
`Text`, `Image`, etc, so `{ id: "container" }` would otherwise match
multiple elements). See [`writing-specs.md` § SwiftUI gotchas](../guides/writing-specs.md#swiftui-gotchas).

### `expect_total: N` companion

Pair `nth:` with `expect_total: N` to make the choice self-checking. The
resolver fails loudly if the actual match count diverges from the
expectation — catches silent regressions when an unrelated layout change
shifts which element occupies index N.

```json
{ "role": "AXButton", "label": "Documents", "nth": 0, "expect_total": 2 }
```

Without `expect_total`, the day a sibling appears or disappears your
spec quietly clicks the wrong element. With it, the run errors with
`expected_total=2, actual=3 — layout drift?` and the candidate
descriptors.

---

## Error contract

Every tool returns either a success result or an error envelope:

```json
{ "error": { "kind": "ax_permission_denied", "message": "...", "fix": "System Settings → Privacy & Security → Accessibility" } }
```

`kind` is one of a closed set:

| Kind | Cause |
|---|---|
| `app_not_found`, `bundle_not_found`, `executable_not_found` | launch input is wrong |
| `harness_unreachable` | socket never appeared |
| `ax_permission_denied` | parent process not trusted |
| `resolution_ambiguous` | target matched > 1 element |
| `resolution_empty` | target matched 0 elements |
| `viewmodel_not_registered` | `pry_state` / `assert_state` against unknown VM |
| `path_not_found` | unknown path on a registered VM |
| `snapshot_failed` | window capture failed (Screen Recording perm?) |
| `spec_parse_error` | bad spec syntax |
| `invalid_params` | malformed input |
| `not_launched` | tool requires a running app |
| `timed_out` | wait/global budget exceeded |
| `internal` | bug — file an issue |

`pry-mcp` never returns a bare `"failed"` without a `kind`.

---

## CLI mirror

`pry-mcp` also exposes a CLI mirroring most tools 1:1 — useful for hand-driven
testing and local automation:

```sh
pry-mcp version
pry-mcp launch    --app fr.neimad.x --path /abs/path
pry-mcp terminate --app fr.neimad.x
pry-mcp state     --app fr.neimad.x --viewmodel DocVM [--path documents.count]
pry-mcp click     --app fr.neimad.x --id new_doc_button
pry-mcp type      --app fr.neimad.x --text "hello"
pry-mcp key       --app fr.neimad.x --combo cmd+s
pry-mcp tree      --app fr.neimad.x [--compact]      # AX tree as YAML
pry-mcp menu      --app fr.neimad.x [--path "View > View Mode"]
                                                      # walk menu, dump children, leave open
pry-mcp focus     --app fr.neimad.x                   # currently focused element as JSON
pry-mcp find      --app fr.neimad.x --label Save
pry-mcp snapshot  --app fr.neimad.x --out /tmp/x.png
pry-mcp drag      --app fr.neimad.x --from-id a --to-id b
pry-mcp scroll    --app fr.neimad.x --id list --direction down --amount 3
pry-mcp logs      --app fr.neimad.x --subsystem fr.neimad.x

pry-mcp run        --spec flows/foo.md
pry-mcp run-suite  --dir flows [--tag smoke] [--parallel 4] [--retry-failed 2]
                   [--junit junit.xml] [--tap out.tap] [--summary-md out.md]
pry-mcp list-specs --dir flows
pry-mcp watch      --dir flows                # re-run on change
pry-mcp lint       --dir flows [--json]       # parse-only validation; CI gate
pry-mcp init       --bundle-id fr.neimad.x --product MyApp [--directory .] [--force]
                                              # scaffold .pry/config.yaml
pry-mcp report     --build pry-verdicts [--out pry-verdicts/index.html]
                                              # self-contained HTML dashboard with embedded PNGs
```

`pry-mcp` with no args (or `pry-mcp mcp`) starts stdio MCP mode — register
this command in your client's MCP server config.
