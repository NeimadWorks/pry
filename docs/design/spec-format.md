# Pry test spec format

Reference for `.md` test specs. Grammar version: **`pry_spec_version: 1`**
(frozen for v1.0 — no breaking removals or renames until v2).

A Pry test is a Markdown file with YAML frontmatter and fenced ` ```pry `
code blocks. Prose is for humans; the fenced blocks are for the runner.

This document covers the full grammar including Wave 1-4 additions
(`PryClock`, control flow, fixtures, async handlers).

---

## 1. File anatomy

```markdown
---
id: my-flow
app: fr.neimad.myapp
description: "Optional one-liner."
tags: [smoke, regression]
timeout: 30s
---

# Optional human prose between blocks

```pry setup
launch
wait_for: { role: Window, title_matches: "MyApp" }
```

```pry
click: { id: "save_button" }
assert_state: { viewmodel: DocVM, path: "isDirty", equals: false }
```

```pry teardown
terminate
```
```

Multiple ` ```pry ` blocks in the same file are **concatenated** in source
order. Setup and teardown blocks have special semantics (see §4).

---

## 2. Frontmatter

YAML between `---` markers at the very top of the file.

| Key | Type | Required | Default | Notes |
|---|---|---|---|---|
| `id` | string | yes | — | unique identifier; appears in verdicts |
| `app` | string | yes | — | bundle identifier of the target |
| `executable_path` | string | no | — | absolute path; useful for SwiftPM-built fixtures |
| `description` | string | no | — | one-liner |
| `tags` | [string] | no | `[]` | for `--tag` filtering |
| `timeout` | duration | no | `60s` | whole-spec budget |
| `animations` | `on` \| `off` | no | `on` | calls `set_animations` after launch (ADR-009) |
| `screenshots` | `never` \| `on_failure` \| `every_step` \| `always` | no | `on_failure` | per-step screenshot policy (ADR-011) |
| `vars` | object | no | `{}` | `${name}` substitutions in step bodies |
| `with_fs` | object | no | — | filesystem fixture (Wave 4) |
| `with_defaults` | object | no | `{}` | NSUserDefaults overrides per-bundle |

### `vars`

Variables are interpolated as `${name}` in any step's string fields:

```yaml
vars: { user: "alice", count: 3 }
```

```pry
type: "Hello ${user}"
```

### `with_fs`

```yaml
with_fs:
  base: ~/.pry-tmp/${spec_id}
  layout:
    - file: report.txt, content: "Hello"
    - dir: assets
    - file: assets/logo.png, source: ./test-data/logo.png
```

The base directory is created before launch and removed after teardown.
Entries:
- `file: PATH, content: STRING` — write a file
- `dir: PATH` — create directory
- `file: PATH, source: SRC` — copy from source path

The path `${spec_id}` is interpolated to the spec's `id`.

### `with_defaults`

```yaml
with_defaults:
  AppleLocale: fr_FR
  AppleLanguages: [fr, en]
  MyAppDebugFlag: true
```

Calls `defaults write <bundleID> KEY VALUE` before launch, snapshots prior
values, restores after teardown.

---

## 3. Block kinds

` ```pry ` blocks open with the `pry` token followed by an optional kind
suffix:

| Header | Kind | Purpose |
|---|---|---|
| ` ```pry ` | main | the test's primary step list |
| ` ```pry setup ` | setup | runs before main; failure aborts spec |
| ` ```pry teardown ` | teardown | runs always (even on failure) |
| ` ```pry flow NAME ` | flow definition | reusable named sequence |
| ` ```pry flow NAME(p1, p2) ` | parameterized flow | flow with arguments |
| ` ```pry handler NAME on TRIGGER ` | async handler | runs in parallel; reacts to events |
| ` ```pry handler NAME on TRIGGER once ` | one-shot handler | unbinds after first match |
| ` ```pry handler NAME on TRIGGER always ` | recurring | re-bindable every match |

### Handler triggers

| Form | Fires when |
|---|---|
| `sheet:any` | any AXSheet appears |
| `sheet:"REGEX"` | a sheet whose title matches REGEX appears |
| `state:VM.path` | a specific VM key changes |
| `state:VM.*` | any key on VM changes |
| `window:any` | a new window appears |
| `window:"REGEX"` | a window whose title matches REGEX appears |

### Example with handler

```markdown
```pry handler dismiss_replace on sheet:"Replace.*" once
- accept_sheet: "Skip"
```

```pry
copy
paste
# If the replace dialog shows up, the handler dismisses it.
```
```

### Example with flow

```markdown
```pry flow tap_n_times(n)
repeat: 3
  - click: { id: "increment_button" }
```

```pry
call: tap_n_times
# Or with args (when v2 lands; v1 ignores args):
# call: { name: tap_n_times, args: { n: 5 } }
```
```

---

## 4. Step commands

One step per top-level line. Indented continuation lines extend the previous
step's parameters (used for multi-line `assert_state:`, `wait_for:` with
timeout, etc).

### Lifecycle

| Command | Effect |
|---|---|
| `launch` | start the app from frontmatter |
| `launch_with: { args: [...], env: {...} }` | launch with custom argv / env |
| `terminate` | SIGTERM, wait, SIGKILL if needed |
| `relaunch` | terminate + launch |

### Waits

| Command | Effect |
|---|---|
| `wait_for: PREDICATE` (+ optional `timeout: 5s`) | block until predicate holds |
| `sleep: 200ms` | discouraged; prefer `wait_for` or `clock.advance` |
| `wait_for_idle: 2s` | wait until AX tree is stable |

### Mouse / touch

| Command | Notes |
|---|---|
| `click: TARGET` | inject mouse down + up at target center |
| `double_click: TARGET` | two clicks within system double-click interval |
| `right_click: TARGET` | secondary button |
| `hover: TARGET` | move only |
| `hover: { id: "x", dwell_ms: 800 }` | move + dwell (for tooltips) |
| `long_press: { id: "x", dwell_ms: 800 }` | down, hold, up |
| `drag: { from: TARGET, to: TARGET, steps?: 12, modifiers?: [shift] }` | real drag with interpolation |
| `marquee: { from: { x, y }, to: { x, y }, modifiers?: [...] }` | rubber-band drag in empty space |
| `scroll: { target: TARGET, direction: up\|down\|left\|right, amount?: 3 }` | wheel scroll at target |
| `magnify: { target: TARGET, delta: 100 }` | pinch approximation (Option+scroll); `delta > 0` zooms in |

All click/drag commands accept `modifiers: [shift, cmd, opt, ctrl]`.

### Keyboard

| Command | Notes |
|---|---|
| `type: "text"` | unicode typing into focused element |
| `type: { text: "...", delay_ms: 30 }` | per-char delay (type-to-select) |
| `key: "cmd+s"` | one keystroke; combos with `+` |
| `key: { combo: "down", repeat: 5 }` | repeat the combo N times |

Modifiers in combos: `cmd`, `shift`, `opt` (or `option`/`alt`), `ctrl`.
Named keys: `return`, `tab`, `space`, `escape`, `delete`, `up`, `down`,
`left`, `right`, `home`, `end`, `pageup`, `pagedown`. Letters and digits
mapped per US keyboard.

### Assertions

| Command | Notes |
|---|---|
| `assert_tree: PREDICATE` | fail if AX tree doesn't satisfy |
| `assert_state: { viewmodel, path, equals \| matches \| any_of }` | fail if VM state mismatches |
| `expect_change: { action: { click: TARGET }, in: { viewmodel, path }, to: VALUE, timeout?: 2s }` | atomic do-then-observe |
| `assert_pasteboard: "substring"` | NSPasteboard contains substring |

`expect_change.action` accepts: `{ click: T }`, `{ double_click: T }`,
`{ right_click: T }`, `{ key: "combo" }`, `{ type: "text" }`.

### Time control (Wave 1, ADR-007)

| Command | Notes |
|---|---|
| `clock.advance: 5s` | fast-forward; fires all `PryClock.after(...)` work whose deadline ≤ new time |
| `clock.set: { iso8601: "...", paused?: true }` | absolute time |
| `set_animations: off` (or `on`) | enable/disable app-wide animations |

Time control only affects code paths that use `PryClock` (host-app opt-in).
See [`PryHarness.md`](../api/PryHarness.md#pryclock) for adoption.

### Sheets / menus / pasteboard (Wave 1)

| Command | Notes |
|---|---|
| `accept_sheet: "Save"` | clicks the named button; without arg, picks default among OK/Save/Done/Continue/Allow/Yes |
| `dismiss_alert` | sends Escape |
| `select_menu: "File > Open Recent > foo.pgn"` | walks the menu path via AX `Press` |
| `copy` / `paste` | `cmd+c` / `cmd+v` shorthand |
| `write_pasteboard: "..."` | seed system pasteboard via the harness |

### Control flow (Wave 2)

| Command | Notes |
|---|---|
| `if: PREDICATE then: [STEPS] else: [STEPS]` | run then-branch if predicate holds, else-branch otherwise |
| `for: { var: NAME, in: [...] }` + indented `- STEP` lines | iterate over a YAML array, binding `${NAME}` |
| `repeat: N` + indented `- STEP` lines | run the body N times |
| `call: NAME` | invoke a flow defined by ` ```pry flow NAME ` |
| `call: { name: NAME, args: { ... } }` | with arguments (forwarded as variables) |

### Debug aids

| Command | Notes |
|---|---|
| `snapshot: NAME` | window PNG; respects `screenshots` policy |
| `dump_tree: NAME` | full AX tree as YAML attachment |
| `dump_state: NAME` | all registered VM states |

---

## 5. Targets

Resolution order (highest precedence first):

```yaml
{ id: "save_button" }                       # 1 — AXIdentifier exact
{ role: AXButton, label: "Save" }           # 2 — role + label
{ label: "Save" }                           # 3 — exact label
{ label_matches: "Save.*" }                 # 4 — regex on label
{ tree_path: "Window[0]/Group/Button[2]" }  # 5 — positional fallback
{ point: { x: 120, y: 340 } }               # 6 — absolute screen coords
```

**Ambiguity is an error**, not silent first-match. Two equally-precedent
matches throw `resolution_ambiguous` with the candidate list in the verdict.

Any target object can carry a `modifiers: [shift, cmd]` array, used by
`click`, `double_click`, `right_click`, and `drag`.

---

## 6. Predicates

```yaml
contains: <target>
not_contains: <target>
count: { of: <target>, equals: <n> }
visible: <target>
enabled: <target>
focused: <target>

state:
  viewmodel: <name>
  path: <keypath>
  equals: <value>           # — or —
  matches: <regex>          # — or —
  any_of: [<v>, <v>, ...]

window: { title_matches: "..." }   # window-existence shortcut
```

Composition:

```yaml
all_of: [PREDICATE, PREDICATE, ...]
any_of: [PREDICATE, PREDICATE, ...]
not: PREDICATE
```

---

## 7. Verdict policy & screenshots

The frontmatter `screenshots:` field controls when window PNGs are written:

- `never` — no automatic snapshot
- `on_failure` (default) — snapshot the failing step only
- `every_step` — snapshot after every step (timeline)
- `always` — same as every_step

Manual `snapshot: name` steps always fire regardless of the policy.

---

## 8. Removed / not in v1

These were drafted but removed before v1 (per ADR-006 and CG/HID limits):

- `assert_logs: { contains: "..." }` — `OSLogStore` ~1 s flush latency makes
  real-time log assertions race-prone. Use `assert_state` against an exposed
  VM property instead. `pry_logs` is still available for post-hoc inspection.
- `assert_no_errors` — same reason.
- True multi-touch pinch — replaced by `magnify` which uses `Option+scroll`
  (handles SwiftUI `MagnificationGesture` in many apps). True 2-finger HID
  pinch deferred.
- `drag_between_apps` — cross-process pasteboard-driven drag. Not in v1.

These remain non-goals or land behind a new ADR.

---

## 9. Versioning

- `pry_spec_version: 1` is implicit. Specs may set it explicitly to fail
  fast on a future incompatible runner.
- v1 is **frozen** for v1.0 of Pry — no breaking removals or renames.
- Additive changes (new step kinds, new predicates) ship within v1 and are
  documented here as added.
- A v2 grammar will require a migration note in this file.
