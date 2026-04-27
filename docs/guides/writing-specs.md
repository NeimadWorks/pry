# Writing Pry specs

A practical guide. For the full grammar reference, see [docs/design/spec-format.md](../design/spec-format.md).

---

## The shape of a good spec

A Pry spec tells a story: preconditions → actions → expectations. Keep it linear. One spec = one flow.

```markdown
---
id: export-pdf
app: fr.neimad.proof
tags: [flow, export]
---

# Export a document to PDF

## Preconditions

```pry
launch
wait_for: { role: Window, title_matches: "Proof.*" }
click: { id: "sample_doc" }
```

## Open the export sheet

```pry
key: "cmd+e"
wait_for: { role: Sheet, title: "Export" }
```

## Choose PDF and confirm

```pry
click: { role: RadioButton, label: "PDF" }
click: { role: Button, label: "Export…" }
wait_for: { role: SavePanel }
type: "demo.pdf"
key: "return"
```

## Verify the file was written

```pry
assert_state:
  viewmodel: ExportVM
  path: lastExport.path
  matches: ".*/demo\\.pdf$"
assert_no_errors
```
```

---

## Anti-patterns

### ❌ Using `sleep` to paper over timing

```pry
click: { label: "Save" }
sleep: 2s                   # ← bad
click: { label: "Close" }
```

Replace with `wait_for`:

```pry
click: { label: "Save" }
wait_for: { not: { enabled: { label: "Save" } } }
click: { label: "Close" }
```

### ❌ Depending on label text that might localize

```pry
click: { label: "Enregistrer" }   # ← fragile
```

Use `id` from `accessibilityIdentifier` in the app:

```pry
click: { id: "save_doc" }
```

### ❌ Asserting on a pixel snapshot

```pry
click: { label: "Save" }
snapshot: final                   # ← this is a debug aid, not an assertion
```

If you want to assert the outcome, assert on state:

```pry
click: { label: "Save" }
assert_state:
  viewmodel: DocumentVM
  path: isDirty
  equals: false
```

Snapshots attach to the verdict on failure — that's their job. They are not test gates.

### ❌ One spec covering five flows

If your spec has three `## Preconditions` sections with different setup, split it. One spec per flow. Common setup belongs in a shared helper in a future version of the grammar; for now, duplicate the preamble.

---

## How to scope a target

The resolution order is: `id` > `role+label` > `label` > `label_matches` > `tree_path` > `point`.

**Start high.** Your first attempt should be `{ id: "..." }`. If your app doesn't have an `accessibilityIdentifier` on the element, add one. It is the single highest-leverage change you can make for test stability.

**Add role when label collides.** If a button and a menu item share a label (common: "Save", "New", "Close"), add `role: Button`.

**Avoid `tree_path` except as a last resort.** Tree paths break when layouts change. They are documented for completeness; use them for elements that genuinely have no semantic identity.

**Never commit specs that use `point: { x, y }`.** Absolute coordinates are a test smell. If you resorted to them mid-exploration, find the semantic target before checking in.

---

## Assertions: state > tree > logs

Three ways to check an outcome. In order of preference:

1. **`assert_state`** — ViewModel state is the truest source of truth. It survives layout changes, localizations, animations.
2. **`assert_tree`** — AX tree predicates. Use for "the user can see a success message" or "the Save button is now disabled" — things that are inherently about the UI.
3. **`assert_logs`** — when state isn't exposed and the tree doesn't reflect it. Example: a background task completed. Wrap with `assert_no_errors` to catch silent failures.

The more a test relies on logs, the more brittle it is. Treat logs as a last resort or a complementary check.

---

## Dealing with flakiness

A flaky Pry test is almost always one of these:

1. **Missing `wait_for`.** The next step races the UI update. Add a `wait_for` on the expected post-condition of the previous step.
2. **Ambiguous target resolution.** Two elements match; the "wrong" one wins sometimes. The verdict will tell you which ones matched — narrow with `id` or `role`.
3. **State snapshot taken during animation.** `@Published` values can flip twice during a transition. `wait_for` the steady state before `assert_state`.

Never wrap a spec in a retry loop. A test that needs retries is a test that is not testing the thing it claims to test.

---

## When to split into multiple specs

Split when:

- The flows are independent and should be able to run in any order.
- A failure in one should not block the other from running.
- The preconditions diverge materially.

Keep together when:

- Later steps genuinely depend on earlier steps' state.
- The combined flow mirrors a single user intent ("create and then name the thing").

In doubt, split. Shorter specs produce clearer verdicts.

---

## Patterns from Wave 1-4

### Time-dependent code

If your VM uses `PryClock` for debouncing, scheduled work, or polling
([adoption guide](../api/PryHarness.md#virtual-clock-pryclock-adr-007)),
test it deterministically without real wait:

```pry
click: { id: "trigger" }                                # registers a 5s scheduled job
wait_for: { state: { viewmodel: VM, path: "scheduleRequestedCount", equals: 1 } }
clock.advance: 5s
wait_for: { state: { viewmodel: VM, path: "scheduledFiredCount", equals: 1 } }
```

The wait between click and `clock.advance` is the standard race-killer:
make sure the schedule was registered (the button action ran on main actor)
before fast-forwarding. Otherwise the advance moves the clock past a
deadline that hasn't been added yet.

### Async dialogs you don't control timing of

Use a handler to dismiss them automatically wherever they show up:

````markdown
```pry handler dismiss_replace on sheet:"Replace.*" once
- accept_sheet: "Skip"
```

```pry
copy
paste
# If a "Replace existing file?" sheet appears at any point, the handler
# clicks "Skip" and the main flow continues.
```
````

### Setup / teardown

Setup runs before main; failure aborts. Teardown **always** runs (even on
failure):

````markdown
```pry setup
launch
wait_for: { role: Window, title_matches: "MyApp" }
```

```pry
# main flow
```

```pry teardown
terminate
```
````

### Loops, variables, sub-flows

````markdown
---
vars: { user: "alice" }
---

```pry flow login_as(name)
- click: { id: "login_button" }
- type: "${name}"
- key: "return"
```

```pry
call: { name: login_as, args: { name: "${user}" } }
for: { var: doc, in: ["doc1", "doc2", "doc3"] }
  - click: { id: "${doc}_link" }
  - assert_state: { viewmodel: ViewerVM, path: "currentDoc", matches: "${doc}.*" }
```
````

### Filesystem fixtures (Canopy-style file managers)

````yaml
---
with_fs:
  base: ~/.pry-tmp/${spec_id}
  layout:
    - file: report.txt, content: "Hello world"
    - dir: assets
    - file: assets/img.png, source: ./fixtures/img.png
---
````

The base directory is created before launch and deleted after teardown.
Reference it inside the spec via `${fixture_dir}` (auto-set when `with_fs`
is present).

### Multi-select pattern

```pry
click: { id: "row_1" }
click: { id: "row_3", modifiers: [cmd] }
click: { id: "row_5", modifiers: [cmd] }
key: "delete"
assert_state: { viewmodel: ListVM, path: "items.count", equals: 7 }
```

### Marquee selection

For empty-area drag selection:

```pry
marquee:
  from: { x: 100, y: 200 }
  to: { x: 400, y: 500 }
```

### Drive Open / Save dialogs

```pry
# 1. Trigger the panel — usually via menu or button.
select_menu: "File > Open…"

# 2. Drive it. The helper handles Cmd+Shift+G + type + accept.
open_file: "/Users/me/Documents/sample.pgn"

# 3. Verify your VM saw the URL. Use `matches:` because macOS canonicalizes
#    /etc → /private/etc and /tmp → /private/tmp.
wait_for:
  state: { viewmodel: DocVM, path: "lastImportedURL", matches: ".*/sample\\.pgn$" }
  timeout: 3s
```

For exporting:

```pry
click: { id: "export_button" }
save_file: "/tmp/exported.pdf"
wait_for:
  state: { viewmodel: DocVM, path: "lastExportedURL", matches: ".*/exported\\.pdf$" }
```

If the panel is non-standard (third-party file picker, a custom dialog with
its own button labels), drive it with the lower-level `key`/`type`/`click`
primitives plus `panel_accept: "<button>"` / `panel_cancel`.

### Disable animations for snapshot determinism

In frontmatter:

```yaml
animations: off
screenshots: every_step
```

Animations are restored automatically after teardown.
