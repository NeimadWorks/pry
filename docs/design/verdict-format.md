# Verdict report format

The output of `pry_run_spec` and `pry run`. Markdown with YAML frontmatter — human-readable *and* machine-parseable.

A verdict always has the same top-level shape regardless of pass/fail. Failures carry extra diagnostic sections; successes stay compact.

---

## Frontmatter

```yaml
---
spec: flows/new-document.md
id: new-document-flow
app: fr.neimad.proof
status: passed | failed | errored | timed_out
duration: 4.2s
steps_total: 7
steps_passed: 7
failed_at_step: null       # or integer index (1-based)
pry_version: 0.1.0
pry_spec_version: 1
started_at: 2026-04-22T10:14:00Z
finished_at: 2026-04-22T10:14:04Z
---
```

`status`:
- `passed` — all steps completed, all assertions held.
- `failed` — an assertion did not hold, or a control step could not resolve its target.
- `errored` — runtime error (harness disconnected, AX permission missing, socket crashed).
- `timed_out` — global spec `timeout` elapsed mid-run.

Consumers (including Claude Code) branch on `status` first, then read the body.

---

## Success verdict

Compact. Frontmatter + a step list with durations. No noise.

```markdown
---
spec: flows/new-document.md
status: passed
duration: 4.2s
steps_total: 7
steps_passed: 7
---

# Verdict — new-document-flow

**Status: PASSED** (7/7 steps, 4.2s)

- ✅ 1 — `launch` (1.8s)
- ✅ 2 — `wait_for: Window` (0.3s)
- ✅ 3 — `assert_tree: contains New Document` (0.1s)
- ✅ 4 — `click: New Document` (0.2s)
- ✅ 5 — `type: "Ma composition"` (0.4s)
- ✅ 6 — `click: Create` (0.2s)
- ✅ 7 — `assert_state: documents.count == 1` (1.2s)
```

---

## Failure verdict

Full diagnostic context. Non-negotiable sections on failure:

1. **Which step** — index, source line, literal command.
2. **Expected** — derived from the step's intent.
3. **Observed** — what actually happened.
4. **Diagnostic context** — AX tree snippet, registered state, recent logs.
5. **Suggestion** — present when the failure matches a known pattern (ambiguous resolution, element not visible, disabled button, etc.).
6. **Attachments** — file paths on disk, not inline blobs.

```markdown
---
spec: flows/new-document.md
id: new-document-flow
app: fr.neimad.proof
status: failed
duration: 4.2s
steps_total: 7
steps_passed: 5
failed_at_step: 6
---

# Verdict — new-document-flow

**Status: FAILED at step 6**

## Step 6 — `click: { label: "Create" }`

**Expected:** button resolves and click fires.
**Observed:** 2 elements match `{ label: "Create" }`:
  - `Button[role=Button, enabled=true, frame=(120,340,80,32)]` in Window "Proof"
  - `MenuItem[role=MenuItem, label="Create"]` in MenuBar

**Resolution:** ambiguous. A higher-precedence resolver is required.

**Suggestion:** specify `role: Button` or add `accessibilityIdentifier("create_doc")` in the app and use `{ id: "create_doc" }`.

### AX tree context at failure

```yaml
Window "Proof":
  Group:
    TextField (placeholder: "Document name", value: "Ma composition", focused: true)
    HStack:
      Button "Cancel" (enabled: true)
      Button "Create" (enabled: true)   # candidate 1
MenuBar:
  Menu "File":
    MenuItem "Create"                   # candidate 2
```

### Registered state at failure

```yaml
DocumentListVM:
  documents.count: 0
  isLoading: false
```

### Relevant logs (last 3s)

```
2026-04-22 10:14:02 [Proof] DocumentListVM: preparing to create
2026-04-22 10:14:02 [Proof] TextField: value committed "Ma composition"
```

### Attachments

- `pry-verdicts/new-document-flow-20260422T101400Z/step-6-failure.png`
- `pry-verdicts/new-document-flow-20260422T101400Z/step-6-tree.yaml`

## Preceding steps

- ✅ Step 1 — `launch` (1.8s)
- ✅ Step 2 — `wait_for: Window` (0.3s)
- ✅ Step 3 — `assert_tree: contains New Document` (0.1s)
- ✅ Step 4 — `click: New Document` (0.2s)
- ✅ Step 5 — `type: "Ma composition"` (0.4s)
- ❌ Step 6 — `click: Create` (timed out after 1.2s, resolution ambiguous)
- ⏭ Step 7 — `assert_state: documents.count == 1` (skipped)
```

---

## Error verdict

Environmental failure — not a test failure. Most common causes:
- `pry-mcp` lacks Accessibility permission.
- `PryHarness` socket never appeared (harness not linked, or app crashed on launch).
- Socket disconnected mid-run.

```markdown
---
status: errored
error_kind: harness_unreachable
failed_at_step: 1
---

# Verdict — ... (ERRORED)

**Error:** Could not connect to PryHarness socket at `/tmp/pry-fr.neimad.proof.sock` within 5s after launch.

**Likely cause:** the target app was built without the `PryHarness` dependency, or `PryHarness.start()` is not being called from `init()`.

**Fix:** see [README — Quickstart](../../README.md#quickstart).
```

---

## On-disk layout

Each run creates a directory: `./pry-verdicts/<id>-<UTC-timestamp>/`

```
pry-verdicts/
  new-document-flow-20260422T101400Z/
    verdict.md
    step-6-failure.png
    step-6-tree.yaml
```

`verdict.md` is the canonical report. Other files are attachments referenced by path in the report.

---

## Parseability contract

The frontmatter YAML is guaranteed to be valid YAML with the fields listed above. Consumers should parse the frontmatter first to get `status` and step counts, then read the body only when needed.

The body is well-formed CommonMark. Heading hierarchy is stable:

- `# Verdict — <id>` (always, level 1)
- `## Step N — <command>` (only on failure)
- `### AX tree context at failure` / `### Registered state at failure` / `### Relevant logs` / `### Attachments` (only on failure)
- `## Preceding steps` (always, even on success where it's just "## Steps")

Claude Code can extract the failure step by grepping `failed_at_step:` in the frontmatter, then jumping to `## Step <N>`.
