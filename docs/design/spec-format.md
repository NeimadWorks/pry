# Pry test spec format

The user-facing reference for writing `.md` test specs. Grammar version: **`pry_spec_version: 1`**.

A Pry test is a Markdown file with YAML frontmatter and fenced ` ```pry ` blocks. Prose is for humans. The fenced blocks are for the runner.

---

## 1. File structure

````markdown
---
id: new-document-flow
app: fr.neimad.proof
description: User creates a new document and names it.
tags: [flow, documents, smoke]
timeout: 30s
---

# New document flow

## Preconditions

- App launches clean.

```pry
launch
wait_for: { role: Window, title_matches: "Proof.*" }
```

## Create the document

```pry
click: { id: "new_doc_button" }
type: "Ma composition"
click: { role: Button, label: "Create" }
```

## Verify

```pry
assert_state:
  viewmodel: DocumentListVM
  path: documents.count
  equals: 1
```
````

---

## 2. Frontmatter

| Key | Type | Required | Description |
|---|---|---|---|
| `id` | string | yes | Stable identifier. Appears in verdicts. Should be unique across the suite. |
| `app` | string | yes | Bundle identifier of the target. `pry-mcp` launches or attaches to this app. |
| `description` | string | no | One-line intent. |
| `tags` | [string] | no | For filtering via `pry run --tag smoke`. |
| `timeout` | duration | no | Default 60s. Whole-spec budget. |
| `window` | predicate | no | Scoping predicate if the target is multi-window (see §4). |
| `pry_spec_version` | int | no | Defaults to `1`. Bump only with a formal migration. |

Durations are parsed as `Ns`, `Nms`, `Nmin`.

---

## 3. Step commands

Every line inside a ` ```pry ` block is one step. Order matters: top-to-bottom execution.

### Lifecycle

| Command | Effect |
|---|---|
| `launch` | Launch the app in frontmatter, wait for socket. |
| `launch_with: { args: [...], env: {...} }` | Same, with custom argv / env. |
| `terminate` | Send `SIGTERM`, wait for exit. |
| `relaunch` | `terminate` then `launch`. State is wiped. |

### Waits

| Command | Effect |
|---|---|
| `wait_for: <predicate>` | Block until predicate holds. Default timeout 5s. |
| `wait_for: <predicate>` + `  timeout: <duration>` | Override the timeout. |
| `sleep: <duration>` | Discouraged. Use `wait_for`. Requires a `# ...` justification comment on the preceding line. |

### Control (injects real events)

| Command | Effect |
|---|---|
| `click: <target>` | Resolve target, inject mouse down/up at its center. |
| `double_click: <target>` | Two clicks within the system double-click interval. |
| `right_click: <target>` | Secondary-button click. |
| `hover: <target>` | Mouse move only. Useful for tooltip/hover states. |
| `type: "<text>"` | Key events delivered to the currently focused element. |
| `key: "<combo>"` | Modifier combo, e.g. `"cmd+s"`, `"esc"`, `"tab"`, `"shift+cmd+n"`. |
| `scroll: { target: <target>, direction: up\|down\|left\|right, amount: <int> }` | Scroll wheel events. |
| `drag: { from: <target>, to: <target> }` | Mouse down at `from`, move to `to`, mouse up. |

### Observation

| Command | Effect |
|---|---|
| `assert_tree: <predicate>` | Fail if the AX tree does not satisfy the predicate. |
| `assert_state: { viewmodel: <name>, path: <keypath>, equals: <value> }` | Fail if registered state mismatches. |
| `assert_logs: { contains: "<substring>", since: <step_ref> }` | Fail if substring absent in logs captured since `<step_ref>`. |
| `assert_no_errors` | Fail if any `ERROR` or `FAULT` log lines since the last assertion. |
| `expect_change: { action: <step>, in: <observable>, to: <value> }` | Atomic do-and-verify: run `action`, assert `observable` now holds `value`. |

### Debug aids

| Command | Effect |
|---|---|
| `snapshot: <name>` | Captures window PNG. Attached to verdict on failure by default; always attached if the spec is run with `--snapshots=always`. |
| `dump_tree: <name>` | Writes full AX tree as a YAML attachment to the verdict. |
| `dump_state: <name>` | Writes all registered ViewModel states. |

---

## 4. Target grammar

A `<target>` resolves to exactly one AX element. Forms, in precedence order:

```yaml
{ id: "accessibility_identifier" }    # 1 — highest precedence
{ role: Button, label: "Save" }       # 2
{ label: "text" }                     # 3 — AX label exact match
{ label_matches: "regex" }            # 4
{ tree_path: "Window[0]/Group/Button[2]" }  # 5 — positional fallback
{ point: { x: 120, y: 340 } }         # 6 — absolute screen coords, last resort
```

**Ambiguity is an error, not a silent first-match.** If the chosen form matches >1 element, the verdict explains which candidates matched and suggests narrowing (typically: add an `id` via `.accessibilityIdentifier(...)` in the app, or add a `role` constraint).

### Window scoping

Multi-window apps can scope by frontmatter:

```yaml
window: { title_matches: "Document — .*" }
```

Or per-step:

```yaml
click: { label: "Save", window: { title: "Export" } }
```

---

## 5. Predicate grammar

Predicates express expectations about tree state, element visibility, or ViewModel state.

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
  equals: <value>
  # or:
  matches: <regex>
  # or:
  any_of: [<value>, <value>, ...]
```

Composition:

```yaml
all_of:
  - contains: { role: Button, label: "Save" }
  - enabled: { role: Button, label: "Save" }

any_of:
  - visible: { label: "Loading…" }
  - visible: { label: "Done" }

not:
  contains: { label: "Error" }
```

---

## 6. Versioning & migration

- Current version: **1** (implicit; explicit via `pry_spec_version: 1`).
- Breaking grammar changes bump the version.
- A migration note lives in this file under "Migration from vN to vN+1."
- Specs declaring an unsupported version fail fast with a clear error.

No v2 yet. First candidate for v2: streaming partial verdicts ([PROJECT-BIBLE §16 Q2](../../PROJECT-BIBLE.md#16-open-questions-pre-spike)).
