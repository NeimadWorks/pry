# `pry-mcp` — MCP tool reference

`pry-mcp` exposes Pry's capabilities to Claude Code (and any MCP-speaking agent) over stdio JSON-RPC. Every tool listed here has a stable JSON I/O shape.

**Primary entry point:** `pry_run_spec`. Use it unless you have a specific reason not to. The low-level primitives exist for exceptional debugging — not for Claude Code to hand-drive a flow.

---

## Lifecycle

### `pry_launch`

Launch the target app and connect to its `PryHarness` socket.

**Input:**
```json
{ "app": "fr.neimad.proof", "args": [], "env": {} }
```

**Output:**
```json
{ "pid": 12345, "socket": "/tmp/pry-fr.neimad.proof.sock", "harness_version": "0.1.0" }
```

Errors: `app_not_found`, `harness_unreachable`, `ax_permission_denied`.

### `pry_attach`

Connect to an already-running app.

**Input:** `{ "app": "fr.neimad.proof" }`
**Output:** same as `pry_launch`.

### `pry_terminate`

Send `SIGTERM`, wait for exit.

**Input:** `{ "app": "fr.neimad.proof", "timeout": "5s" }`
**Output:** `{ "exit_code": 0 }`

---

## Observation

### `pry_tree`

Return the current AX tree merged with any PryHarness-reported frames.

**Input:** `{ "app": "fr.neimad.proof", "window": { "title_matches": "Proof.*" }? }`
**Output:** YAML-encoded tree as a string.

### `pry_find`

Resolve a target to zero, one, or many nodes.

**Input:**
```json
{ "app": "fr.neimad.proof", "target": { "label": "Save" } }
```

**Output:**
```json
{
  "matches": [
    { "role": "Button", "label": "Save", "frame": [120, 340, 80, 32], "enabled": true, "id": null },
    { "role": "MenuItem", "label": "Save", "frame": null, "enabled": true, "id": null }
  ]
}
```

### `pry_state`

Read registered ViewModel state.

**Input:** `{ "app": "fr.neimad.proof", "viewmodel": "DocumentListVM", "path": "documents.count"? }`

- Omit `path` to get all keys for the ViewModel. Useful when Claude Code doesn't know what's exposed.

**Output:** `{ "value": 3 }` or `{ "keys": { "documents.count": 3, "isLoading": false } }`

### `pry_logs`

Capture `OSLog` lines since a cursor. **Best-effort latency (~1 s)** — backed by `OSLogStore`, suitable for post-hoc verdict attachments, not for race-sensitive assertions. See [ADR-006](../architecture/decisions/ADR-006-log-observation-strategy.md).

**Input:** `{ "app": "fr.neimad.proof", "since": "2026-04-22T10:14:02Z"?, "subsystem": "fr.neimad.proof"? }`
**Output:** `{ "lines": [{ "ts": "...", "level": "info", "msg": "..." }, ...], "cursor": "2026-04-22T10:14:05Z" }`

### `pry_snapshot`

PNG of the target window.

**Input:** `{ "app": "fr.neimad.proof", "window": { "title_matches": "Proof.*" }? }`
**Output:** `{ "path": "./pry-verdicts/.../snapshot.png" }`

---

## Control

All control tools inject real events through `CGEventPost`. See [ADR-005](../architecture/decisions/ADR-005-event-injection-strategy.md).

### `pry_click` / `pry_double_click` / `pry_right_click` / `pry_hover`

**Input:** `{ "app": "...", "target": { ... } }`
**Output:** `{ "resolved": { "role": "Button", "frame": [...] } }`

### `pry_type`

**Input:** `{ "app": "...", "text": "Ma composition" }`
**Output:** `{ "chars_sent": 14 }`

### `pry_key`

**Input:** `{ "app": "...", "combo": "cmd+s" }`
**Output:** `{ }`

### `pry_scroll` / `pry_drag`

See [docs/design/spec-format.md §3](../design/spec-format.md#3-step-commands) for the parameters — MCP tool shapes mirror the spec commands 1:1.

---

## Assertions

### `pry_wait_for`

Block until a predicate holds.

**Input:** `{ "app": "...", "predicate": { "contains": { "label": "Done" } }, "timeout": "5s" }`
**Output:** `{ "held": true, "elapsed": "1.2s" }` or `{ "held": false, "elapsed": "5s", "tree_at_timeout": "..." }`

### `pry_assert`

Evaluate a predicate once and return a structured result.

**Input:** `{ "app": "...", "predicate": { ... } }`
**Output:**
```json
{ "passed": false, "expected": "...", "observed": "...", "suggestion": "..." }
```

### `pry_expect_change`

Atomic do-and-observe.

**Input:**
```json
{
  "app": "...",
  "action": { "click": { "id": "create_doc" } },
  "observable": { "viewmodel": "DocumentListVM", "path": "documents.count" },
  "to": 1
}
```

**Output:** `{ "passed": true, "before": 0, "after": 1 }`

---

## Specs (the happy path)

### `pry_run_spec`

Execute a Markdown spec end-to-end and return the verdict.

**Input:**
```json
{
  "source": "path",
  "path": "flows/new-document.md"
}
```

Or inline:

```json
{
  "source": "inline",
  "markdown": "---\nid: ...\napp: ...\n---\n..."
}
```

**Output:**
```json
{
  "status": "failed",
  "verdict_path": "./pry-verdicts/new-document-flow-20260422T101400Z/verdict.md",
  "verdict_markdown": "---\nspec: ...\n..."
}
```

`verdict_markdown` is the full verdict inline so Claude Code can read it without a second tool call. `verdict_path` lets a human open the file.

### `pry_run_suite`

Execute every spec in a directory.

**Input:** `{ "path": "flows/", "tag": "smoke"? }`
**Output:** `{ "total": 12, "passed": 11, "failed": 1, "verdicts": [...] }`

### `pry_list_specs`

Discover specs in a directory.

**Input:** `{ "path": "flows/" }`
**Output:** `{ "specs": [{ "path": "flows/a.md", "id": "...", "tags": [...] }, ...] }`

---

## Error contract

Every tool result may be a success or an error envelope:

```json
{ "error": { "kind": "ax_permission_denied", "message": "...", "fix": "System Settings → Privacy → Accessibility" } }
```

`kind` is one of a closed set. Current values:

- `app_not_found`
- `harness_unreachable`
- `ax_permission_denied`
- `resolution_ambiguous`
- `resolution_empty`
- `timeout`
- `spec_parse_error`
- `socket_disconnected`
- `internal` (always a bug — file an issue)

No tool ever returns a bare `"failed"` without a `kind`.
