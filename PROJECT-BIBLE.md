# PROJECT-BIBLE — Pry

> Source of truth. Read before writing code. Do not re-litigate locked decisions.

---

## 1. Identity

- **Name** — Pry
- **Bundle prefix** — `fr.neimad.pry`
- **Tier** — Neimad (open source, personal-first)
- **Repo** — `github.com/neimad/pry` (or org equivalent)
- **Tagline** — The test runner that reads Markdown and clicks like a human.

Pry is a companion to **Smithy**. Smithy builds. Pry tests. They share nothing but a naming family and the same operator — you.

---

## 2. Vision

Claude Code today cannot reliably test a Swift app. The loop is: build → launch → screenshot → upload PNG → analyze pixels → decide. Every cycle burns 2,000+ tokens on an image that has no semantic structure. Flows are untestable because Claude cannot click. State is opaque.

Pry replaces that loop with:

1. A **Markdown test script** written by Claude Code (or by hand).
2. A **runner** that launches the target app, drives it through real event injection, observes via AX + in-process introspection, and writes a **structured verdict report**.
3. A **verdict report** (also Markdown) that answers precisely: *did this pass, if not where, what was seen, what was expected, what was the app's state at failure.*

Claude Code writes the test, runs one MCP tool call, reads the verdict. No screenshots in the default path. No prose ambiguity. No re-exploration.

The product must be explainable in one sentence: **Pry runs Markdown test scripts against macOS apps and returns verdicts Claude Code can act on.**

---

## 3. Personas & Validation

Three personas validate feature completeness. If a feature serves none of them, it does not ship.

### Persona A — Dom (operator)

Indie dev, writes apps solo. Needs to regression-test Proof, Probe, Narrow, Harald etc. before each release without writing XCUITest. Values: zero ceremony, zero Xcode GUI, runnable from terminal, reviewable diffs.

**Needs Pry to:**
- Run `pry test flows/new-document.md` from terminal and get a pass/fail exit code.
- Fail loudly with precise location when a layout regresses.
- Never require re-recording after a UI change if the intent is unchanged.
- Work without a running Xcode instance.

**Red flag features for Dom:** any cloud service, any test recorder GUI, any dependency on simulator, any per-OS-version fragility.

### Persona B — Claude Code (automated operator)

Long-horizon coding agent. Given a feature request, wants to:
1. Implement the feature.
2. Write a test spec in Markdown.
3. Run it via MCP.
4. Read a structured verdict.
5. Fix and repeat until green.

**Needs Pry to:**
- Expose every capability as MCP tools with precise JSON I/O.
- Return verdicts in **machine-parseable structure** (YAML/JSON) wrapped in human-readable Markdown.
- Never require Claude to interpret a pixel diff unless explicitly asked.
- Support `pry_run_spec(path)` as a single high-level call — not 40 low-level clicks.
- Fail verdicts must include: step index, step description, expectation, actual observation, AX tree delta, relevant logs, optional snapshot.

**Red flag features for Claude Code:** stateful sessions that must be kept alive, interactive prompts, ambiguous error strings, tools that return only "failed" without context.

### Persona C — External Swift developer (future)

Indie or studio Mac dev who discovers Pry on GitHub. Not a Neimad customer — a peer. Adopts Pry if it makes their Claude Code workflow obviously better on their own apps.

**Needs Pry to:**
- Install in under 5 minutes. One Swift package + one CLI binary.
- Work with **any** SwiftUI or AppKit macOS app, not only Neimad apps.
- Not require source changes beyond `#if DEBUG import PryHarness; PryHarness.start()`.
- Document the Markdown test format in one readable page.

**Red flag features for C:** Neimad-specific branding in required interfaces, assumptions about app architecture, required accessibility identifiers on every view.

### Validation matrix

Every capability listed in §8 is tagged `[A]`, `[B]`, `[C]` for which personas it serves. A capability serving only one persona requires extra justification.

---

## 4. Distribution & Licensing

- **PryHarness** (Swift package, in-process) — **MIT**, public on GitHub.
- **pry-mcp** (CLI binary + MCP server) — **MIT**, public on GitHub. Distributed as source + signed Homebrew tap binary.
- **Installation path for Dom's own apps** — local Swift Package dependency pointing to a pinned tag. No Paddle, no Sparkle. This is infrastructure, not a product.

**Distribution tier decision (ADR-001):** Pry components ship **direct / open source**. No App Store, no sandbox. `pry-mcp` uses AX API and CGEvent injection — sandbox-incompatible by design.

---

## 5. Tech Stack

Defaults apply unless listed here.

| Concern | Choice | Justification |
|---|---|---|
| Language | Swift 6, strict concurrency | Consistent with all Neimad projects |
| PryHarness UI interop | SwiftUI + AppKit | Must introspect both |
| pry-mcp IPC | Unix domain socket, JSON-RPC 2.0 | Lightweight, local-only, no network |
| pry-mcp ↔ Claude Code | stdio MCP protocol | Standard |
| State capture | `Mirror` + registered keypath protocol | See §9 |
| Log capture | `OSLogStore` streaming | Native, no app changes |
| Snapshot rendering | `CGWindowListCreateImage` on target window | Post-event-injection, real pixels |
| Target resolution | AX API (`AXUIElementCreateApplication`) | Real user pathway |
| Event injection | `CGEventPost(.cgSessionEventTap, ...)` | Goes through the full event chain |
| Minimum macOS | 14.0 | Consistent with portfolio |
| Dependencies | zero | Enforced |

No Combine. No async/await on the socket wire protocol (plain Data + JSONDecoder). No external MCP SDK — stdio JSON-RPC is ~200 lines.

---

## 6. Architecture

### 6.1 Two-component split

```
┌───────────────────────────────────────────────────┐
│ Target app (compiled with PryHarness, DEBUG only) │
│                                                   │
│  ┌─────────────────────────────────────────────┐  │
│  │ PryHarness                                  │  │
│  │                                             │  │
│  │  • Starts Unix socket server at             │  │
│  │    /tmp/pry-<bundleID>.sock                 │  │
│  │  • Registers ViewModels exposed by app      │  │
│  │  • Streams OSLog entries                    │  │
│  │  • Responds to JSON-RPC requests:           │  │
│  │    - inspect_tree                           │  │
│  │    - read_state                             │  │
│  │    - read_logs                              │  │
│  │    - snapshot                               │  │
│  │                                             │  │
│  │  • Does NOT perform clicks / typing.        │  │
│  │    Events come from outside via CGEvent.    │  │
│  └─────────────────────────────────────────────┘  │
└───────────────────────────────────────────────────┘
                         ▲
                         │ Unix socket (JSON-RPC)
                         │
┌────────────────────────┴──────────────────────────┐
│ pry-mcp (CLI / MCP server, out-of-process)        │
│                                                   │
│  • Speaks MCP over stdio to Claude Code           │
│  • Launches target app (or attaches to running)   │
│  • Connects to PryHarness socket                  │
│  • Resolves targets via AX API                    │
│  • Injects CGEvents at resolved coords            │
│  • Orchestrates test specs (run_spec)             │
│  • Writes verdict reports                         │
└───────────────────────────────────────────────────┘
                         ▲
                         │ stdio JSON-RPC (MCP)
                         │
                    Claude Code
```

### 6.2 Why split

The **CONTROL channel** (event injection, app lifecycle, AX queries) must run **outside** the target process. CGEvent injection from within the same process is unreliable and filtered by AppKit's "synthetic event" heuristics. AX queries on self are technically allowed but forbidden by Apple guidelines and fragile under sandboxed children.

The **OBSERVE channel** for state + logs must run **inside** the target process. `Mirror`, ViewModel keypaths, and the SwiftUI runtime are only reachable in-process.

Splitting respects this. PryHarness is passive (answers queries). pry-mcp is active (drives the app). They talk via a local socket — no network, no auth, no serialization lib dependency.

### 6.3 Module boundaries

**PryHarness** (in-process, Swift package)
- `PryHarness.start()` — lifecycle entry, idempotent, no-op in RELEASE builds.
- `PryRegistry` — ViewModel registration protocol.
- `PrySocketServer` — Unix socket listener.
- `PryInspector` — AX + Mirror-based tree walker.
- `PryLogTap` — OSLogStore subscriber.

What does NOT belong: event injection, test script parsing, verdict formatting, MCP protocol.

**pry-mcp** (out-of-process, CLI binary)
- `MCPServer` — stdio JSON-RPC server exposing Pry tools.
- `AppDriver` — launch/attach/terminate lifecycle.
- `HarnessClient` — socket client to PryHarness.
- `ElementResolver` — AX target resolution (label, identifier, coords).
- `EventInjector` — CGEvent composition and post.
- `SpecParser` — Markdown test script → step tree.
- `SpecRunner` — executes step tree, collects verdict.
- `VerdictReporter` — formats structured Markdown output.

What does NOT belong: any UI code, any in-process introspection.

---

## 7. The Markdown Test Spec Format

The killer feature. Claude Code writes these, Pry runs them, verdicts come back.

### 7.1 Philosophy

- **Declarative, not procedural.** Describe expected behavior, not button coordinates.
- **Linear by default.** Most tests are a top-to-bottom flow. Branching is exceptional.
- **Readable by humans.** A non-technical Dom skim can tell what's being tested.
- **Diffable.** Changes to a test are reviewable as plain text diffs.

### 7.2 File structure

Two-part files. Frontmatter (YAML) for metadata, body (Markdown with fenced `pry` blocks) for steps.

````markdown
---
id: new-document-flow
app: fr.neimad.proof
description: User creates a new document and names it.
tags: [flow, documents, smoke]
timeout: 30s
---

# New Document Flow

## Preconditions
- App launches clean (no restored documents).

```pry
launch
wait_for: { role: Window, title_matches: "Proof.*" }
assert_tree:
  contains: { role: Button, label: "New Document" }
```

## Create the document

```pry
click: { label: "New Document" }
wait_for: { role: TextField, placeholder: "Document name" }
  timeout: 2s
type: "Ma composition"
click: { label: "Create" }
```

## Verify outcome

```pry
assert_state:
  viewmodel: DocumentListVM
  path: documents.count
  equals: 1
assert_tree:
  contains: { role: StaticText, label: "Ma composition" }
snapshot: final-state
```
````

### 7.3 Step grammar

Every step is one of the following commands. One per line inside a `pry` block.

**Lifecycle**
- `launch` — start the app configured in frontmatter.
- `launch_with: { args: [...], env: {...} }`
- `terminate`
- `relaunch`

**Navigation / wait**
- `wait_for: <predicate>` with optional `timeout: <duration>`
- `sleep: <duration>` — discouraged, requires justification comment.

**Control (inject real events)**
- `click: <target>` | `double_click:` | `right_click:`
- `hover: <target>`
- `type: "<text>"` — into focused element.
- `key: "<combo>"` — e.g. `"cmd+s"`, `"esc"`, `"tab"`.
- `scroll: { target: <target>, direction: up|down|left|right, amount: <int> }`
- `drag: { from: <target>, to: <target> }`

**Observation**
- `assert_tree: <predicate>` — fail if AX tree does not match.
- `assert_state: { viewmodel: <name>, path: <keypath>, equals: <value> }`
- `assert_logs: { contains: "<substring>", since: <step_ref> }`
- `assert_no_errors` — shortcut: no ERROR or FAULT log lines since last assertion.
- `expect_change: { action: <step>, in: <observable>, to: <value> }` — atomic do-and-verify.

**Debug aids**
- `snapshot: <name>` — captures window PNG, attached to verdict only on failure by default.
- `dump_tree: <name>` — writes full AX tree as YAML attachment.
- `dump_state: <name>` — writes all registered ViewModel states.

### 7.4 Target grammar

A `<target>` is one of:

```yaml
{ label: "text" }                    # AX label match (exact)
{ label_matches: "regex" }
{ id: "accessibility_identifier" }   # accessibilityIdentifier (preferred)
{ role: Button, label: "Save" }      # role-constrained
{ tree_path: "Window[0]/Group/Button[2]" }  # positional fallback
{ point: { x: 120, y: 340 } }        # absolute screen, last resort
```

Resolution order: `id` > `role+label` > `label` > `label_matches` > `tree_path` > `point`. Any lower-precedence resolver matching multiple elements is an error, not a silent first-match.

### 7.5 Predicate grammar

```yaml
contains: <target>            # at least one matching node anywhere in tree
not_contains: <target>
count: { of: <target>, equals: <n> }
visible: <target>             # on-screen, non-zero frame, not obscured
enabled: <target>
focused: <target>
state:
  viewmodel: <name>
  path: <keypath>
  equals: <value>
  matches: <regex>
  any_of: [...]
```

Predicates compose with `all_of:`, `any_of:`, `not:`.

---

## 8. Capabilities (persona-tagged)

| Capability | Description | Personas |
|---|---|---|
| `pry_launch` | Start target app, connect harness | A, B, C |
| `pry_attach` | Connect to already-running target | A, B |
| `pry_terminate` | Kill target cleanly | A, B, C |
| `pry_tree` | Current AX + merged tree | B |
| `pry_find` | Resolve a target to nodes | B |
| `pry_state` | Read registered ViewModel keypath | A, B |
| `pry_logs` | Capture logs since cursor | A, B |
| `pry_snapshot` | PNG of target window region | A, B |
| `pry_click` / `_type` / `_key` / ... | Low-level control primitives | B |
| `pry_wait_for` | Block until predicate or timeout | A, B |
| `pry_assert` | Predicate eval with structured result | B |
| `pry_expect_change` | Atomic do-and-observe | A, B |
| `pry_run_spec` | Execute a Markdown test file end-to-end | A, B, C |
| `pry_run_suite` | Execute a folder of specs | A, C |
| `pry_list_specs` | Discover specs in a directory | B |

`pry_run_spec` is the **primary entry point for Claude Code**. All other tools are available but the intended 95% flow is: write `.md`, call `pry_run_spec`, read verdict.

---

## 9. State Introspection Contract

ViewModels opt in via a single protocol:

```swift
public protocol PryInspectable: AnyObject {
    static var pryName: String { get }
    func prySnapshot() -> [String: any Sendable]
}
```

Registration:

```swift
#if DEBUG
PryRegistry.shared.register(DocumentListVM.self) { vm in
    [
        "documents.count": vm.documents.count,
        "selection.id": vm.selection?.id.uuidString as Any,
        "isLoading": vm.isLoading,
    ]
}
#endif
```

Keypaths in test specs are **string keys** from `prySnapshot()`. Deliberate: no runtime keypath resolution, no reflection magic, explicit surface. Claude Code sees exactly what's available via `pry_state` with no `path`.

---

## 10. Verdict Report Format

Returned by `pry_run_spec`. Markdown with YAML frontmatter. Human-readable, machine-parseable. See [docs/design/verdict-format.md](docs/design/verdict-format.md) for the full reference.

Non-negotiable verdict contents on failure:
1. **Which step** (index + source line + literal command).
2. **Expected** (derived from step).
3. **Observed** (what actually happened, with enough detail to debug).
4. **Diagnostic context** — AX tree snippet around failure, registered state, recent logs.
5. **Suggestion** — when the failure mode is a known pattern (ambiguous resolution, element not visible, disabled button), include a one-line fix hint.
6. **Attachments** — file paths on disk, not inline.

On success, verdict is compact: frontmatter + step list with durations. No noise.

---

## 11. Validated Assumptions

> To be filled after spike. These are the **binary questions the spike must answer**. Nothing below this line is spec until the spike returns.

### Required spikes

1. **AX frames reliability on SwiftUI views** — does `AXUIElementCopyAttributeValue(.frame)` on a pure SwiftUI `Button` give screen coordinates matching the actual hit-test region, on macOS 14 and 15?
2. **Synthetic CGEvent acceptance** — does `CGEventPost(.cgSessionEventTap, ...)` with a mouseDown/mouseUp pair at AX-resolved coordinates actually trigger SwiftUI `.onTapGesture` and Button actions? Are events ever filtered as "synthetic"?
3. **`accessibilityIdentifier` propagation** — does `.accessibilityIdentifier("foo")` on a SwiftUI view reliably surface as `AXIdentifier` queryable from an external process?
4. **OSLogStore streaming latency** — can pry-mcp tail an app's OSLog in <200ms end-to-end? Is subsystem filtering stable?
5. **Mirror + protocol registration** — does the `PryInspectable` pattern correctly expose `@Published` values from an `ObservableObject` via `prySnapshot()`? Any Sendable gotchas under Swift 6 strict concurrency?

Each spike: one Swift file, one binary question, PASS/FAIL + evidence.

### Placeholder for results

```
Spike 1 — AX frames reliability:        [x] PASS [ ] FAIL — evidence: spikes/01-ax-frames/README.md (macOS 26.4.1, 6/6 view types, 1/1 run)
Spike 2 — Synthetic CGEvent acceptance: [x] PASS [ ] FAIL — evidence: spikes/02-cgevent-acceptance/README.md (macOS 26.4.1, Swift 6.3.1, 1/1)
Spike 3 — accessibilityIdentifier:      [x] PASS [ ] FAIL — evidence: spikes/01-ax-frames/README.md (combined driver; 6/6 view types, 1/1 run)
Spike 4 — OSLogStore latency:           [ ] PASS [x] FAIL — evidence: spikes/04-oslog-streaming/README.md (p50 ~1.2s; ADR-006 triggered; assert_logs / assert_no_errors removed from v1 grammar)
Spike 5 — Mirror introspection:         [x] PASS [ ] FAIL — evidence: spikes/05-mirror-introspection/README.md (macOS 26.4.1, Swift 6.3.1, no Sendable warnings, snapshot round-trip correct)
```

### Branch decisions

- **If 1+2 both PASS** → canonical architecture (§6.1) ships as-is.
- **If 2 FAILS** → fallback to AX-based `AXPerformAction(.press)` for buttons and `AXSetAttributeValue(.value)` for text fields. Lower coverage on custom gestures, but functional for 90% of UI.
- **If 1 FAILS on some SwiftUI views** → require `accessibilityIdentifier` as default resolution strategy; document the pattern as a best practice for Pry-friendly apps.
- **If 3 FAILS** → require a PryHarness-side coordinate registry (views self-report their frames via a `.pryTagged("id")` modifier).
- **If 4 or 5 FAIL** → corresponding capability is marked experimental and reduced in surface.
  - Spike 4 FAILED (2026-04-22): activated. `pry_logs` stays best-effort (~1 s); `assert_logs` and `assert_no_errors` removed from v1 grammar. See [ADR-006](docs/architecture/decisions/ADR-006-log-observation-strategy.md).

No spec beyond §11 is final until this block is filled.

---

## 12. Repo Structure

```
pry/
├── PROJECT-BIBLE.md          # this file
├── CLAUDE.md                 # live session state
├── README.md                 # public pitch + quickstart
├── LICENSE                   # MIT
│
├── Package.swift             # SwiftPM root, declares two products
│
├── Sources/
│   ├── PryHarness/           # in-process Swift library
│   ├── PryWire/              # shared wire types (JSON-RPC messages)
│   └── pry-mcp/              # CLI binary
│
├── Tests/
├── docs/
├── Fixtures/DemoApp/
└── spikes/
```

See [docs/architecture/overview.md](docs/architecture/overview.md) for the fully expanded tree and per-module rationale.

---

## 13. Non-Negotiables

- **No network calls, ever.** Socket is Unix-domain, localhost-only by construction.
- **No data retention.** Verdicts written to disk where the spec runner decides (default: `./pry-verdicts/`). No global database.
- **No telemetry.** Even opt-in.
- **No required changes to production code paths.** PryHarness is `#if DEBUG`, full stop. RELEASE builds of the target app must be byte-identical with or without the PryHarness dependency on the source side (guaranteed via `#if DEBUG` gates on all public API surface).
- **No test recorder GUI.** Specs are written, not recorded.
- **No cloud execution.** Pry runs where the developer runs.
- **No flakiness tolerance.** A failing test must fail for the reason the verdict states. Timing-based flakiness is a bug in Pry, not "the nature of UI tests."

---

## 14. Invariants

1. PryHarness has zero effect on RELEASE builds.
2. Target app never knows it is being tested (from a behavior standpoint — no test-only branches in app logic).
3. Event injection goes through the real system event path. No shortcuts via in-process dispatch.
4. Every verdict failure includes location + expected + observed + diagnostic context. No "failed" without context.
5. Every public MCP tool has a Markdown spec example in `docs/api/pry-mcp-tools.md`.
6. Every ADR that supersedes another links both directions.
7. The Markdown spec format is versioned (`pry_spec_version: 1` implicit in frontmatter). Breaking changes bump the version and require a migration note. **v1 grammar is frozen** (2026-04-24): no removals or renames until v2.

---

## 15. Non-Goals

- ❌ iOS support.
- ❌ Visual regression testing as a primary feature.
- ❌ Performance benchmarking.
- ❌ Unit test replacement.
- ❌ Cross-platform (Windows/Linux).
- ❌ Remote execution / CI cloud runners.
- ❌ GUI test recorder.
- ❌ LLM-driven test generation inside Pry.
- ❌ Screenshot-based assertion via image diff.

---

## 16. Open Questions (pre-spike)

- **Q1** — Should PryHarness expose a way to **pause** the app for deterministic state snapshots during event flurries?
- **Q2** — Should `pry_run_spec` stream partial verdict back, or only emit the final report? Leaning: final-only for v1.
- **Q3** — How does Pry handle multi-window apps? Proposed: frontmatter `window: { title_matches: "..." }`.
- **Q4** — Does `pry_run_spec` accept specs from stdin as well as file paths? Leaning: yes.
- **Q5** — When does the Tier 2 real-time log tee ([ADR-006](docs/architecture/decisions/ADR-006-log-observation-strategy.md)) land? Blocks reintroducing `assert_logs` / `assert_no_errors`. Not v1.

---

## 17. Session Continuity

- **PROJECT-BIBLE.md** (this file) — source of truth, edited only on accepted deltas. Never rewritten wholesale mid-session.
- **CLAUDE.md** — live state. Updated at the end of every session with a `## Session YYYY-MM-DD — Delta` block: what changed, what's blocked, single next action.
- **ADRs** — permanent record of architectural choices. Superseded, never deleted.
- **`spikes/NN-name/README.md`** — each spike's result preserved with the evidence that justified the branch decision.

Zero verbal briefing should be required to resume work. A new assistant reads README → PROJECT-BIBLE → CLAUDE.md and is operational.
