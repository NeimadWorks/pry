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

## SwiftUI gotchas

If you're testing a SwiftUI app, three things will bite you. Document them
in the host-app's own README too.

### `.accessibilityIdentifier` propagates to descendants

Putting `.accessibilityIdentifier("foo")` on a `VStack` sets `AXIdentifier=foo`
on the container **and on every descendant** (`Text`, `Image`, etc). When
your spec says `click: { id: "foo" }`, Pry resolves it to multiple AX
elements and fails with `resolution_ambiguous`.

Three ways to fix it:

```pry
# 1) Disambiguate with nth: (0-indexed, tree pre-order — the container is usually [0])
click: { id: "foo", nth: 0 }

# 2) Add a tighter constraint in the host app — use a more specific identifier
#    on the actual interactive child (Button), not the container.

# 3) Use { role: ..., label: ... } to narrow by AX role.
click: { role: AXButton, label: "Save" }
```

The cleanest answer is option 2 — give identifiers only to the elements you
want to test against. Containers shouldn't carry them.

### `List` surfaces as `AXOutline`, `Toggle` as `AXCheckBox`

The SwiftUI → AX role map is non-obvious on macOS:

| SwiftUI | AX role |
|---|---|
| `Button` | `AXButton` |
| `Toggle` | `AXCheckBox` |
| `Text` | `AXStaticText` |
| `TextField` | `AXTextField` |
| `List` | `AXOutline` (not `AXList`) |
| `Slider` | `AXSlider` |
| `Stepper` | `AXIncrementor` |

When you write `{ role: AXButton, ... }`, use the AX side, not the SwiftUI
side. Run `pry-mcp tree --app <bundle>` once to inspect what your app
actually exposes.

### Custom tap zones need explicit AX traits

A `Rectangle().onTapGesture { ... }` does not surface as `AXButton` by
default — it shows up as `AXGroup` and Pry's role-based resolvers won't
find it:

```swift
Rectangle()
    .onTapGesture { ... }
    .accessibilityAddTraits(.isButton)        // ← required
    .contentShape(Rectangle())                // ← so the whole rect responds
    .accessibilityIdentifier("tap_zone")
```

### `.onKeyPress` fields need `type_chars`, not `type`

SwiftUI fields that observe keystrokes via `.onKeyPress` (search, command palette,
chess move-input, anything with a per-keystroke handler) don't see strings
delivered as a single Unicode-string event. `type:` posts one event for the whole
string; `.onKeyPress` only fires for events that carry a key code.

```pry
# Doesn't fire onKeyPress in the host app:
type: "e2e4"

# Synthesizes one keyDown/keyUp pair per character — onKeyPress sees each one:
type_chars: "e2e4"
```

Use `type:` for ordinary `TextField`/`TextEditor`. Use `type_chars:` whenever the
host code reads `KeyPress` events directly.

## Patterns from the Canopy wave

These patterns came out of dogfooding Pry on a real file-manager app. They are
not new grammar — they're combinations of existing primitives that solve
recurring friction.

### Anti-flicker: `assert_stable`

A predicate can flip true → false → true during animations or async loads.
`assert_stable` requires the predicate to hold continuously for a duration
before passing:

```pry
click: { id: "load_button" }
# Bad: loading spinner flips visible briefly twice — equals: false fires too early
# wait_for: { state: { viewmodel: VM, path: "isLoading", equals: false } }

# Good: require the steady state for 500ms
assert_stable:
  for: 500ms
  state: { viewmodel: VM, path: "isLoading", equals: false }
```

### Replace `sleep` with `wait_for_focus`

After triggering a focus change (Tab key, programmatic focus shift), don't
sleep — wait for the focused element by AXIdentifier:

```pry
click: { id: "search_field" }
# Bad: sleep: 200ms
wait_for_focus: { id: "search_field", timeout: 1s }
type_chars: "query"
```

`dump_focus: "where-is-it"` writes the currently-focused element's id/role/label
to stderr — handy when you don't yet know what to assert against.

### Guard against silent layout drift with `expect_total`

`nth: N` picks one element from a multi-match. If the layout grows from 5 rows
to 50, `nth: 0` keeps passing — but you're now testing a different scenario.
`expect_total:` makes the count an explicit precondition:

```pry
click: { id: "row", nth: 0, expect_total: 5 }
# Fails loudly with "expected 5 matches, found 50" if the data set changed.
```

### Soft assertions for inspection passes

`soft_assert_state` records a failure but lets the spec continue. Useful when
you want one verdict reporting all field-level mismatches at once instead of
stopping at the first:

```pry
soft_assert_state: { viewmodel: FormVM, path: "name",  equals: "Ada" }
soft_assert_state: { viewmodel: FormVM, path: "email", equals: "ada@example.com" }
soft_assert_state: { viewmodel: FormVM, path: "age",   equals: 36 }
# Verdict reports all three; spec fails iff any one did.
```

Reserve hard `assert_state` for invariants that, once broken, make subsequent
steps meaningless.

### `auto_build: true` for SwiftPM fixtures

In `.pry/config.yaml`:

```yaml
apps:
  fr.neimad.demo:
    executable_path: ./Fixtures/DemoApp/.build/debug/DemoApp
    auto_build: true
```

The runner runs `swift build` from the config directory before the first
`launch` of that app. Saves the "I edited the fixture, forgot to rebuild,
spent 10 minutes debugging stale behaviour" loop.

### Multi-line `with_fs` is fine

`with_fs:` accepts either inline-flow or block-style YAML. Use whichever
reads better:

```yaml
---
with_fs:
  base: ~/.pry-tmp/${spec_id}
  layout:
    - file: notes.txt
      content: |
        line one
        line two
    - dir: archive
    - file: archive/old.txt, source: ./fixtures/old.txt
---
```

### Disable animations for snapshot determinism

In frontmatter:

```yaml
animations: off
screenshots: every_step
```

Animations are restored automatically after teardown.
