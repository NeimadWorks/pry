# Pry — agent guide

> Entry point for AI agents (Claude Code, Cursor, ...) opening this repo.

If you're a coding agent and you have to drive Pry — either to write specs, to
extend the runner, or to integrate Pry into another project — this is the page
to read first. It indexes everything else by intent.

---

## TL;DR

Pry runs Markdown test specs against macOS apps. Two consumption modes:

```swift
// 1) Direct from Swift (XCTest, custom CLI, scripts)
import PryRunner
let v = try await Pry.runSpec(atPath: "Tests/Flows/foo.md")

// or step-by-step:
let pry = try await Pry.launch(app: "fr.neimad.demo", executablePath: "...")
try await pry.click(.id("save_button"), modifiers: ["cmd"])
try await pry.advanceClock(by: 5.0)
let n: Int? = try await pry.state(of: "DocVM", path: "documents.count")
```

```sh
# 2) Via the MCP server (Claude Code, Cursor, ...)
{ "mcpServers": { "pry": { "command": "pry-mcp" } } }

# Or interactive CLI:
pry-mcp run --spec flows/foo.md
pry-mcp run-suite --dir flows --parallel 4 --junit out.xml
```

Architecture: target app links **`PryHarness`** (`#if DEBUG`), exposes a
Unix-socket server. **`PryRunner`** drives it from outside via AX, CGEvent,
and JSON-RPC. **`pry-mcp`** is a thin stdio MCP wrapper around `PryRunner`.

---

## Where to look for what

### "I want to write a test spec"

→ [`docs/design/spec-format.md`](design/spec-format.md) — full Markdown grammar (frontmatter, blocks, all step commands, target/predicate forms, control flow, fixtures, handlers, clock control)
→ [`docs/design/verdict-format.md`](design/verdict-format.md) — what comes back
→ [`docs/guides/writing-specs.md`](guides/writing-specs.md) — patterns and anti-patterns
→ Examples: [`Fixtures/DemoApp/flows/`](../Fixtures/DemoApp/flows/) — 8 working specs

### "I want to call Pry from Swift code"

→ [`docs/api/PryRunner.md`](api/PryRunner.md) — `Pry` actor API + `SpecRunner` + types
→ [`docs/api/PryHarness.md`](api/PryHarness.md) — `PryHarness.start()`, `PryRegistry`, `PryInspectable`, `PryStateBroadcaster`, `PryClock`, `PryAnimations`

### "I'm Claude Code / an MCP client"

→ [`docs/api/pry-mcp-tools.md`](api/pry-mcp-tools.md) — every `pry_*` tool with input/output JSON shapes and stable error kinds

### "I want to know why X is the way it is"

→ [`PROJECT-BIBLE.md`](../PROJECT-BIBLE.md) — non-negotiables, non-goals, invariants
→ [`docs/architecture/decisions/`](architecture/decisions/) — ADRs, indexed in [`README.md`](architecture/decisions/README.md)
→ [`docs/architecture/overview.md`](architecture/overview.md) — components map and responsibilities

### "I'm picking up where the last session left off"

→ [`CLAUDE.md`](../CLAUDE.md) — live session state, last delta at the bottom

### "I want to extend the runner"

→ Source layout: `Sources/PryRunner/{Spec,Verdict,Control,Driver}/` + `Pry.swift`. The `Tools.swift` & `MCPServer.swift` in `Sources/pry-mcp/` are thin dispatchers; logic lives in `PryRunner`.
→ Tests: `Tests/PryRunnerTests/PryRunnerTests.swift` (parser, verdict, live-AX gated by `PRY_INTEGRATION=1`)

---

## Cheat sheet — spec grammar

Everything below is reference-level. Full grammar with edge cases in [spec-format.md](design/spec-format.md).

### Frontmatter

```yaml
---
id: my-flow                          # required, unique
app: fr.neimad.myapp                 # required, bundle ID
executable_path: /path/to/binary     # optional — for SwiftPM-built fixtures
description: "..."
tags: [smoke, regression]
timeout: 30s
animations: off                      # default on (Wave 1)
screenshots: every_step              # never | on_failure (default) | every_step | always
vars: { user: "alice", count: 3 }    # variable bindings — referenced as ${user} (Wave 2)
with_fs:                             # filesystem fixture — installed before launch (Wave 4)
  base: ~/.pry-tmp/${spec_id}
  layout:
    - file: report.txt, content: "Hello"
    - dir: assets
    - file: assets/img.png, source: ./test-assets/img.png
with_defaults:                       # NSUserDefaults overrides per-bundle (Wave 4)
  AppleLocale: fr_FR
---
```

### Block kinds

- ` ```pry ` — main step list (multiple allowed; concatenated)
- ` ```pry setup ` — runs before main; failure aborts
- ` ```pry teardown ` — runs always (even after failure)
- ` ```pry flow NAME(p1, p2) ` — reusable named sequence; call via `call: NAME`
- ` ```pry handler NAME on TRIGGER [once|always] ` — async handler; runs in parallel

Triggers: `sheet:"Replace.*"`, `state:VM.path`, `window:"Compose.*"`.

### Step commands

**Lifecycle** — `launch`, `launch_with: { args, env }`, `terminate`, `relaunch`

**Control flow (Wave 2)** — `if: PRED then: [...] else: [...]`, `for: { var, in: [...] }`, `repeat: N`, `call: name` (with `args:`)

**Waits** — `wait_for: PREDICATE [timeout: 2s]`, `sleep: 100ms`, `wait_for_idle: 2s`

**Mouse/touch** — `click`, `double_click`, `right_click`, `hover`, `long_press`, `drag: { from, to, steps?, modifiers? }`, `marquee: { from: {x,y}, to: {x,y} }`, `scroll: { target, direction, amount }`, `magnify: { target, delta }`

All click/drag steps accept `modifiers: [shift, cmd, opt, ctrl]`.

**Keyboard** — `type: "..."` or `type: { text, delay_ms }`, `key: "cmd+s"` or `key: { combo, repeat }`

**Time control (Wave 1)** — `clock.advance: 5s`, `clock.set: { iso8601, paused? }`, `set_animations: off|on`

**Sheets/menus/copy/paste (Wave 1)** — `accept_sheet: "Save"`, `dismiss_alert`, `select_menu: "File > Open Recent > foo"`, `copy`, `paste`, `write_pasteboard: "..."`, `assert_pasteboard: "..."`

**Assertions** — `assert_tree: PREDICATE`, `assert_state: { viewmodel, path, equals|matches|any_of }`, `expect_change: { action: { click: ... }, in: { viewmodel, path }, to: VALUE, timeout? }`

**Debug** — `snapshot: name`, `dump_tree: name`, `dump_state: name`

### Targets

```yaml
{ id: "save_button" }                    # AXIdentifier (preferred)
{ role: AXButton, label: "Save" }
{ label: "Save" }
{ label_matches: "Save.*" }
{ tree_path: "Window[0]/Group/Button[2]" }
{ point: { x: 120, y: 340 } }            # last resort

# Any of the above can carry: modifiers: [shift, cmd]
```

### Predicates

```yaml
contains: <target>
not_contains: <target>
count: { of: <target>, equals: 3 }
visible: <target>
enabled: <target>
focused: <target>
state: { viewmodel: "VM", path: "x", equals: 1 }
window: { title_matches: "Compose.*" }    # window-shortcut
all_of: [PRED, PRED]
any_of: [PRED, PRED]
not: PRED
```

---

## Cheat sheet — Pry Swift API

```swift
// Launch
let pry = try await Pry.launch(app: "fr.neimad.x", executablePath: "...")
let pry = try await Pry.attach(to: "fr.neimad.x")

// Spec runner
let v = try await Pry.runSpec(atPath: "flows/foo.md")
let v = try await Pry.runSpec(markdown: source)
let vs = try await Pry.runSuite(at: "flows", tag: "smoke", parallel: 4, retry: 1)

// Control
try await pry.click(.id("save"), modifiers: ["cmd"])
try await pry.doubleClick(.id("row")); try await pry.rightClick(.id("row"))
try await pry.longPress(.id("trigger"), dwellMs: 800)
try await pry.type("hello", intervalMs: 30)
try await pry.key("cmd+s", repeat: 1)
try await pry.drag(from: .id("a"), to: .id("b"), modifiers: ["shift"])
try await pry.scroll(.id("list"), direction: .down, amount: 5)
try await pry.magnify(.id("board"), delta: 100)
try await pry.copy(); try await pry.paste()

// Observation
let n: Int? = try await pry.state(of: "VM", path: "x")
let snap = try await pry.snapshot(of: "VM")             // [String: any Sendable]
let tree: AXNode = pry.tree(window: nil)
let r: Resolved = try await pry.resolve(.id("x"))
let png: Data? = await pry.snapshotPNG()
let lines = try await pry.logs(since: nil, subsystem: "...")
let count = pry.windowCount()
let focused = pry.focusedIdentifier()

// Time
try await pry.advanceClock(by: 5.0)
try await pry.setClock(to: Date(), paused: true)
try await pry.pauseClock(); try await pry.resumeClock()
try await pry.setAnimations(enabled: false)

// Pasteboard
try await pry.writePasteboard("hello")
let s = try await pry.readPasteboard()

// Cleanup
await pry.terminate()
```

---

## Cheat sheet — host-app adoption (PryHarness)

Minimum:

```swift
import PryHarness

@main
struct MyApp: App {
    init() {
        #if DEBUG
        PryHarness.start()
        #endif
    }
    var body: some Scene {
        WindowGroup {
            ContentView().environmentObject(vm).task {
                #if DEBUG
                PryRegistry.shared.register(vm)
                #endif
            }
        }
    }
}

@MainActor
final class DocVM: ObservableObject, PryInspectable {
    @Published var documents: [Doc] = []
    func prySnapshot() -> [String: any Sendable] {
        ["documents.count": documents.count]
    }
}
```

For time-based code (debouncing, scheduled work, animations, polling):

```swift
import PryHarness

func scheduleAutoSave() {
    PryClock.shared.after(0.5) { [weak self] in
        Task { @MainActor in self?.save() }
    }
}

// Tests can fast-forward via `pry.advanceClock(by: 0.5)` instead of waiting real time.
```

For real-time state notifications (pushed to subscribed runners):

```swift
extension DocVM: PryStateBroadcaster {
    func prySubscribeStateChanges(_ notify: @escaping @MainActor () -> Void) -> any PryStateSubscription {
        let cancel = $documents.sink { _ in notify() }
        // ... wrap in a struct PryStateSubscription with cancel()
    }
}
```

---

## Common patterns

### Test a debounced/scheduled action without waiting

```pry
click: { id: "trigger" }
wait_for: { state: { viewmodel: VM, path: "scheduleRequestedCount", equals: 1 } }
clock.advance: 5s
wait_for: { state: { viewmodel: VM, path: "scheduledFiredCount", equals: 1 } }
```

### Handle a confirmation sheet that may or may not appear

```pry
handlers:
  - when: sheet:"Replace.*" once
    do:
      - accept_sheet: "Skip"
```

(Block syntax: `` ```pry handler dismiss_replace on sheet:"Replace.*" once ``)

### Multi-select then act on selection

```pry
click: { id: "row_1" }
click: { id: "row_3", modifiers: [cmd] }
click: { id: "row_5", modifiers: [cmd] }
key: "delete"
assert_state: { viewmodel: ListVM, path: "items.count", equals: 7 }   # was 10
```

### Iterate over data

```pry
vars: { moves: ["e2e4", "e7e5", "g1f3"] }

for: { var: move, in: ["e2e4", "e7e5", "g1f3"] }
  - click: { id: "sq_${move}" }
```

### Setup / teardown

```markdown
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
```

### Assert visual

```pry
snapshot: before-action
click: { id: "transform" }
wait_for_idle: 1s
snapshot: after-action
# (Visual diff is invoked manually for now via ImageDiff.diff() — assert_snapshot
#  step lands when golden file workflow is finalized.)
```

---

## File map

```
pry/
├── PROJECT-BIBLE.md               # source of truth, invariants
├── CLAUDE.md                      # live session state
├── README.md                      # public pitch + install
├── Package.swift                  # 4 products
│
├── Sources/
│   ├── PryHarness/                # in-process: socket server, registry, clock
│   ├── PryWire/                   # shared Codable JSON-RPC types
│   ├── PryRunner/                 # public Swift library — runner logic
│   │   ├── Pry.swift              # ergonomic actor API
│   │   ├── Spec/                  # parser, runner, AST
│   │   ├── Verdict/               # verdict types + reporter + exporters
│   │   ├── Control/               # AX walker, event injector, element resolver, capture
│   │   ├── Driver/                # AppDriver + HarnessClient
│   │   ├── Audit/                 # AccessibilityAudit (Wave 4)
│   │   ├── Visual/                # ImageDiff (Wave 4)
│   │   └── Fixtures.swift         # FilesystemFixtures, DefaultsFixtures (Wave 4)
│   └── pry-mcp/                   # thin stdio MCP wrapper + CLI
│
├── Tests/                         # PryWireTests, PryHarnessTests, PryRunnerTests
├── Fixtures/DemoApp/              # SwiftUI fixture used by tests + flows
├── docs/
│   ├── AGENTS.md                  # ← you are here
│   ├── architecture/
│   │   ├── overview.md
│   │   ├── decisions/             # ADRs 001-011
│   │   └── diagrams/
│   ├── design/                    # principles, spec-format, verdict-format
│   ├── api/                       # PryHarness.md, PryRunner.md, PryWire.md, pry-mcp-tools.md
│   └── guides/                    # writing-specs.md
└── spikes/                        # Phase 0 spike evidence (frozen)
```

---

## Conventions an agent should follow

1. **Don't reopen locked decisions.** [PROJECT-BIBLE §13](../PROJECT-BIBLE.md#13-non-negotiables) and [§15](../PROJECT-BIBLE.md#15-non-goals) are closed.
2. **Don't add SwiftPM dependencies.** Zero-dep is enforced.
3. **Spec author preference order for targets**: `id` > `role+label` > `label` > `label_matches`. Avoid `point` and `tree_path`.
4. **Use `wait_for` and `clock.advance`, not `sleep`.** Sleep is documented as an anti-pattern.
5. **When extending grammar**, update [spec-format.md](design/spec-format.md) in the same change. The doc is the user-facing reference; the parser is implementation.
6. **When extending MCP tools**, update [pry-mcp-tools.md](api/pry-mcp-tools.md) and the catalog in `MCPServer.swift` together.
7. **Failed verdicts must include diagnostic context.** Invariant 4 — never emit "failed" without expected/observed/AX-snippet.
8. **Append a `## Session YYYY-MM-DD — <title>` block to [CLAUDE.md](../CLAUDE.md) at end of session.**
