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
| `executable_path` | string | no | — | absolute path; useful for SwiftPM-built fixtures. Falls back to `.pry/config.yaml` and then NSWorkspace lookup. See "Project config" below. |
| `description` | string | no | — | one-liner |
| `tags` | [string] | no | `[]` | for `--tag` filtering |
| `timeout` | duration | no | `60s` | whole-spec budget |
| `animations` | `on` \| `off` | no | `on` | calls `set_animations` after launch (ADR-009) |
| `screenshots` | `never` \| `on_failure` \| `every_step` \| `always` | no | `on_failure` | per-step screenshot policy (ADR-011) |
| `screenshots_embed` | bool | no | `false` | inline PNGs as base64 data URLs in `verdict.md` so the report is self-contained |
| `state_delta` | `off` \| `on_failure` \| `every_step` | no | `on_failure` | capture VM snapshots after each step; multi-step timeline rendered in failure context |
| `ax_tree_diff` | `off` \| `on_failure` | no | `on_failure` | record the AX tree at launch and diff vs the failure-time tree |
| `slow_warn_ms` | int | no | — | flag any step slower than this threshold with a `⚠️` note in the verdict |
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

Both forms are supported. Indented YAML (recommended, matches the rest of
your editor's YAML expectations):

```yaml
with_fs:
  base: ~/.pry-tmp/${spec_id}
  layout:
    - file: report.txt, content: "Hello"
    - dir: assets
    - file: assets/logo.png, source: ./test-data/logo.png
```

Or inline YAML-flow on a single line:

```yaml
with_fs: { base: "~/.pry-tmp/${spec_id}", layout: [{ file: report.txt, content: "Hello" }] }
```

The parser pre-rewrites the indented form to inline before parsing, so
both produce identical results. Prior to v0.2 the indented form was
silently dropped — fixed.

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
| `wait_for_focus: TARGET` (+ optional `timeout: 1s`) | block until target acquires AX focus. Replaces empirical `sleep:` after sheet dismiss / panel accept. |

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
| `type: "text"` | bulk Unicode CGEvent — fast but a single multi-char event. Some fields (SwiftUI `.onKeyPress`, IME-aware, search-as-you-type) filter on `key.count == 1` and silently drop bulk events. Use `type_chars:` for those. |
| `type: { text: "...", delay_ms: 30 }` | per-char with explicit delay |
| `type_chars: "saf"` | per-character typing (30 ms default gap). Right default for fields that filter on single-character keypresses. |
| `type_chars: { text: "...", interval_ms: 50 }` | per-character with explicit gap |
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
| `assert_state: { viewmodel, path, equals \| not_equals \| matches \| not_matches \| any_of \| gt \| gte \| lt \| lte \| between }` | fail if VM state mismatches |
| `soft_assert_state: { ... }` | same shape as `assert_state`, but accumulates failures across the spec instead of bailing; all surfaced at the end if anything failed |
| `assert_focus: <target>` | fail unless `target` is the AX-focused element |
| `assert_eventually: PREDICATE` (+ `timeout: 1s`) | like `wait_for` but on failure the verdict frames it as an assertion (expected/observed) rather than a wait timeout |
| `assert_stable: PREDICATE for: 1s` | predicate must hold continuously across the window. Polls every 80 ms. Anti-flicker checks ("the toast disappeared and didn't flash back"). |
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
| `accept_sheet: "Save"` | clicks the named button on a sheet attached to a window; without arg, picks default among OK/Save/Done/Continue/Allow/Yes |
| `dismiss_alert` | sends Escape |
| `select_menu: "File > Open Recent > foo.pgn"` | walks the menu path via AX `Press` |
| `copy` / `paste` | `cmd+c` / `cmd+v` shorthand |
| `write_pasteboard: "..."` | seed system pasteboard via the harness |

### File panels (NSOpenPanel / NSSavePanel)

| Command | Notes |
|---|---|
| `open_file: "/abs/path/to/file"` | drives an open-style panel: Cmd+Shift+G → type path → accept |
| `save_file: "/abs/path/to/file"` | drives a save panel: navigate to dir → fill name field → accept |
| `panel_accept: "Open"?` | clicks the default button; recognizes both sheet-attached and dialog-window panels |
| `panel_cancel` | sends Escape |

`open_file` / `save_file` assume the panel is already open (typically after a
`select_menu: "File > Open"` or a click that triggers `NSOpenPanel.begin`).
The helpers wait up to 2 s for the panel to surface in the AX tree before
driving keystrokes. Real macOS canonicalizes paths through symlinks
(`/etc` → `/private/etc`, `/tmp` → `/private/tmp`) — assert with
`matches: ".*/foo$"` rather than `equals: "/foo"`.

### Control flow (Wave 2)

| Command | Notes |
|---|---|
| `if: PREDICATE then: [STEPS] else: [STEPS]` | run then-branch if predicate holds, else-branch otherwise |
| `for: { var: NAME, in: [...] }` + indented `- STEP` lines | iterate over a YAML array, binding `${NAME}` |
| `repeat: N` + indented `- STEP` lines | run the body N times |
| `call: NAME` | invoke a flow defined by ` ```pry flow NAME ` |
| `call: { name: NAME, args: { ... } }` | with arguments (forwarded as variables) |
| `with_retry: N` + indented `- STEP` lines | run the body once; on failure, retry up to N more times with a 200 ms backoff |

### Selection helpers

| Command | Notes |
|---|---|
| `select_range: { from: TARGET, to: TARGET }` | click `from`, then shift-click `to` (range selection) |
| `multi_select: [TARGET, TARGET, ...]` | click first, cmd-click each subsequent (additive selection) |

### Capturing into runtime variables

| Command | Notes |
|---|---|
| `copy_to: { var: NAME, from: pasteboard }` | snapshot the pasteboard into `${NAME}` |
| `copy_to: { var: NAME, from: { viewmodel: VM, path: P } }` | snapshot a single VM value into `${NAME}` |

Once captured, runtime vars interpolate the same way frontmatter `vars:`
do (`${NAME}` in any string field). Useful for "click copy, then verify
that the same string lands somewhere else later."

### Debug aids

| Command | Notes |
|---|---|
| `snapshot: NAME` | window PNG; respects `screenshots` policy |
| `dump_tree: NAME` | full AX tree as YAML attachment |
| `dump_state: NAME` | all registered VM states |
| `dump_focus: NAME` | log "currently AX-focused element" (id, role, label) to stderr — quick inline diagnostic without writing an attachment |

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

### Disambiguating with `nth:`

Add `nth: N` to any target to pick the N-th match (0-indexed, tree pre-order):

```yaml
{ id: "row", nth: 0 }                       # first match — common in SwiftUI
{ label: "Save", nth: 2 }                   # third button labelled "Save"
```

This is the standard escape hatch for the SwiftUI propagation gotcha:
`.accessibilityIdentifier` on a container leaks to every descendant, so
`{ id: "container" }` matches multiple elements. See the SwiftUI gotchas in
[`writing-specs.md`](../guides/writing-specs.md#swiftui-gotchas).

`nth:` alone is fragile: the day a layout refactor adds or removes a
sibling, your spec silently picks a different element. Pair `nth:` with
`expect_total: N` to make the choice self-checking — the resolver fails
loudly when the actual match count diverges:

```yaml
{ role: AXButton, label: "Documents", nth: 0, expect_total: 2 }
```

### Modifier keys on click/drag

Any target object can carry a `modifiers: [shift, cmd]` array, used by
`click`, `double_click`, `right_click`, and `drag`.

---

## 6. Predicates

```yaml
contains: <target>
not_contains: <target>
count: { of: <target>, equals|gt|gte|lt|lte|between: <n> | [<lo>, <hi>] }
visible: <target>
enabled: <target>
focused: <target>

state:
  viewmodel: <name>
  path: <keypath>
  equals: <value>                  # — or —
  not_equals: <value>              # negated equals
  matches: <regex>                 # auto-coerces Int/Double to string
  not_matches: <regex>             # negated matches
  any_of: [<v>, <v>, ...]
  gt:  <n>                         # numeric > n
  gte: <n>                         # numeric >= n
  lt:  <n>
  lte: <n>
  between: [<low>, <high>]         # inclusive range

window: { title_matches: "..." }   # window-existence shortcut
panel: any                         # any open NSOpenPanel/NSSavePanel/AXSheet
panel: { title_matches: "Save.*" } # panel filtered by title regex
sheet: any                         # AXSheet only (SwiftUI .sheet, NSWindow.beginSheet)
sheet: { title_matches: "..." }    # sheet filtered by title regex
```

`matches:` auto-coerces numeric values to their string representation, so
`matches: "^[0-9]+$"` works against an Int `symbolCount` without needing
the host VM to expose a String wrapper.

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

## 9. Project config (`.pry/config.yaml`)

For repo-wide settings — particularly app `executable_path` so each spec
doesn't have to hardcode a per-machine absolute path. The runner walks up
from the spec's directory, looking for `.pry/config.yaml` (max 8 levels).

```yaml
apps:
  fr.neimad.works.narrow:
    executable_path: ./.build/arm64-apple-macosx/debug/Narrow
    auto_build: true               # run `swift build` from the config's directory before launch
  fr.neimad.proof:
    executable_path: ~/Apps/Proof.app/Contents/MacOS/Proof
```

`auto_build: true` runs `swift build` (no args) from the config file's
directory before each launch of that bundle. Build failure surfaces as
a clean `auto_build_failed` step error — no silent stale-binary launch.
Cuts the local "edit Swift → bundle.sh → run Pry" cycle.

Path resolution rules:

- Relative paths resolve against the config file's directory
- `~` expands to `$HOME`
- `${swift_bin}` expands to `swift build --show-bin-path` run from the
  config file's directory (useful for SwiftPM apps)

Override hierarchy (highest first):

1. **Spec frontmatter** `executable_path:`
2. **Env var** `PRY_EXEC_<UPPERCASED_BUNDLE_ID>` with `.` and `-` replaced
   by `_`. Example: `PRY_EXEC_FR_NEIMAD_NARROW=/path/to/Narrow`
3. **`.pry/config.yaml`** `apps[<bundle-id>].executable_path`
4. **NSWorkspace** lookup by bundle ID (catches installed `.app`s)

## 10. Versioning

- `pry_spec_version: 1` is implicit. Specs may set it explicitly to fail
  fast on a future incompatible runner.
- v1 is **frozen** for v1.0 of Pry — no breaking removals or renames.
- Additive changes (new step kinds, new predicates) ship within v1 and are
  documented here as added.
- A v2 grammar will require a migration note in this file.
