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
