# Pry

[![CI](https://github.com/neimad/pry/actions/workflows/ci.yml/badge.svg)](https://github.com/neimad/pry/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-lightgrey.svg)](#)

> The test runner that reads Markdown and clicks like a human.

Pry runs Markdown test scripts against macOS apps and returns verdicts [Claude Code](https://claude.com/claude-code) can act on. No screenshots. No pixel diffs. No XCUITest.

```
┌── spec ──┐                 ┌── verdict ──┐
│ click:   │  ── pry run ──▶ │ FAILED at   │
│ "Save"   │                 │ step 6 ...  │
└──────────┘                 └─────────────┘
```

**Status:** `v0.1.0` (first tagged release). Phase 0 spikes green; Waves 1–4 delivered (virtual clock, control flow, modifier-clicks, magnify, pasteboard, async handlers, fixtures, parallel run-suite, JUnit/TAP/markdown exporters, file panels). Spec grammar `pry_spec_version: 1` frozen. Runner exposes 25+ MCP tools and a public Swift library (`PryRunner`). 9 DemoApp specs PASS. CI/release plumbing in place.

**For AI agents** opening this repo: read [`docs/AGENTS.md`](docs/AGENTS.md) first — it indexes the docs by intent and includes a grammar + API cheat sheet.

---

## Why

Claude Code cannot reliably test a Swift app today. The loop is: build → launch → screenshot → upload PNG → analyze pixels → decide. Every cycle burns 2,000+ tokens on an image with no semantic structure. Flows are untestable because Claude cannot click. State is opaque.

Pry replaces that loop with:

1. A **Markdown test script** (written by Claude Code or a human).
2. A **runner** that drives the app through real event injection and observes via AX + in-process introspection.
3. A **structured verdict report** that answers: *did this pass, if not where, what was seen, what was expected, what was the app's state at failure.*

One MCP tool call in. One parseable report out.

---

## How it works

Pry ships as **four products** in one SwiftPM package:

| Product | Used by | What it is |
|---|---|---|
| `PryHarness` | The app under test, `#if DEBUG` | Passive Unix-socket server, `PryInspectable` protocol, `PryRegistry`. Zero effect on RELEASE builds. |
| `PryWire` | Both sides | Shared Codable JSON-RPC types. No logic. |
| `PryRunner` | Tests / CLIs / custom Swift code | The runner library. Spec parser, runner, verdict reporter, AX walker, event injector, app driver, `Pry` ergonomic actor API. |
| `pry-mcp` | Claude Code / interactive CLI | A thin wrapper that exposes `PryRunner` over stdio MCP and a CLI. |

**You can use Pry two ways:**

1. **Through MCP** — register `pry-mcp` in Claude Code's settings; the agent calls `pry_run_spec`, `pry_click`, etc. The story in this README so far.
2. **Directly from Swift** — `import PryRunner` in any Swift project (a SwiftPM CLI, an XCTest target, your own custom test orchestrator). No daemon, no protocol, just a normal Swift API.

They talk over `/tmp/pry-<bundleID>.sock`. No network. No cloud. No telemetry.

See [docs/architecture/overview.md](docs/architecture/overview.md) for the full picture.

---

## Quickstart

### 0. Install `pry-mcp`

```sh
# Via Homebrew tap (once 0.1.0 is tagged and the tap is published):
brew install neimad/tap/pry-mcp

# Or from source:
git clone https://github.com/neimad/pry
cd pry
swift build -c release
cp .build/release/pry-mcp /usr/local/bin/
```

Grant **Accessibility** permission to the terminal or IDE that will run `pry-mcp`:
*System Settings → Privacy & Security → Accessibility → add Terminal (or equivalent) → quit and relaunch it*.

### 1. Add the harness to your app

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/neimad/pry", from: "0.1.0")
],
targets: [
    .target(name: "MyApp", dependencies: [
        .product(name: "PryHarness", package: "pry", condition: .when(configuration: .debug))
    ])
]
```

```swift
// MyApp.swift
#if DEBUG
import PryHarness
#endif

@main
struct MyApp: App {
    init() {
        #if DEBUG
        PryHarness.start()
        #endif
    }
    // ...
}
```

### 2. Register the ViewModels you want Pry to read

```swift
#if DEBUG
PryRegistry.shared.register(DocumentListVM.self) { vm in
    [
        "documents.count": vm.documents.count,
        "isLoading": vm.isLoading,
    ]
}
#endif
```

### 3. Write a spec

````markdown
---
id: new-document-flow
app: fr.neimad.proof
---

# New document flow

```pry
launch
wait_for: { role: Window, title_matches: "Proof.*" }
click: { id: "new_doc_button" }
type: "Ma composition"
click: { role: Button, label: "Create" }
assert_state:
  viewmodel: DocumentListVM
  path: documents.count
  equals: 1
```
````

### 4. Run it

```sh
# One-shot
pry-mcp run --spec flows/new-document.md

# All specs in a directory, filtered by tag
pry-mcp run-suite --dir flows --tag smoke
```

Or register `pry-mcp` as an MCP server and let Claude Code call `pry_run_spec` directly.

---

## Spec format

A Pry test is a Markdown file with YAML frontmatter and fenced `pry` code blocks containing steps. Grammar `pry_spec_version: 1` covers:

- **Lifecycle**: launch, terminate, relaunch
- **Mouse/touch**: click (with modifiers), double-click, right-click, hover (with dwell), long-press, drag (with modifiers), marquee, scroll, magnify
- **Keyboard**: type (with delay), key (with repeat)
- **Time**: `clock.advance`, `clock.set`, `set_animations` (Wave 1, ADR-007/009)
- **Sheets/menus/pasteboard**: `accept_sheet`, `dismiss_alert`, `select_menu`, `copy`, `paste`, `write_pasteboard`, `assert_pasteboard`
- **Assertions**: `assert_state`, `assert_tree`, `expect_change`
- **Control flow**: `if`/`then`/`else`, `for`, `repeat`, `call` to named flows (Wave 2)
- **Async handlers**: `handler NAME on sheet:"..."` runs in parallel (ADR-008)
- **Fixtures**: `with_fs`, `with_defaults`, `screenshots: every_step` (Wave 4, ADR-010/011)

Full reference: [docs/design/spec-format.md](docs/design/spec-format.md). Verdict format: [docs/design/verdict-format.md](docs/design/verdict-format.md).

## Using as a Swift library (no MCP)

Add `PryRunner` to your `Package.swift`:

```swift
.package(url: "https://github.com/neimad/pry", from: "0.1.0"),

.target(name: "MyAppTests", dependencies: [
    .product(name: "PryRunner", package: "pry")
])
```

Then drive your app directly:

```swift
import PryRunner

// Spec-driven: read a Markdown spec, get a structured Verdict back.
let verdict = try await Pry.runSpec(atPath: "Tests/Flows/opening.md")
XCTAssertEqual(verdict.status, .passed, VerdictReporter.render(verdict))

// Programmatic: launch, drive, observe.
let pry = try await Pry.launch(
    app: "fr.neimad.carnet",
    executablePath: carnetBinaryPath
)
try await pry.click(.id("sq_e2"))
try await pry.click(.id("sq_e4"))
let ply: Int? = try await pry.state(of: "BoardVM", path: "ply")
XCTAssertEqual(ply, 1)
await pry.terminate()
```

Use this when you want Pry inside an XCTest target, a Swift Testing suite, your own CI tooling, or any Swift project that doesn't want to spawn `pry-mcp` as a subprocess.

## Using from Claude Code

Register `pry-mcp` as an MCP server in your Claude Code settings:

```json
{
  "mcpServers": {
    "pry": {
      "command": "/usr/local/bin/pry-mcp"
    }
  }
}
```

Then ask Claude Code to write a spec and run it. The agent will call `pry_run_spec` and get a structured verdict back.

Tools exposed: `pry_launch`, `pry_terminate`, `pry_state`, `pry_click`, `pry_type`, `pry_key`, `pry_tree`, `pry_find`, `pry_snapshot`, `pry_logs`, `pry_run_spec`, `pry_run_suite`, `pry_list_specs`. Full reference: [docs/api/pry-mcp-tools.md](docs/api/pry-mcp-tools.md).

---

## Scope

### What Pry is

- A macOS-only, on-device UI test runner.
- A Markdown → verdict pipeline.
- An MCP server for coding agents.

### What Pry is not

- iOS support
- A visual regression tool
- A unit test framework
- A test recorder GUI
- A cloud runner
- Cross-platform

Full non-goals list in [PROJECT-BIBLE §15](PROJECT-BIBLE.md#15-non-goals).

---

## Repo layout

```
Sources/
  PryHarness/   in-process library (linked into your app, DEBUG only)
  PryWire/      shared JSON-RPC message types
  PryRunner/    out-of-process runner library — usable from any Swift code
  pry-mcp/      thin stdio MCP + CLI wrapper around PryRunner
Tests/
Fixtures/
  DemoApp/      tiny SwiftUI app for dogfooding
docs/
spikes/         retained spike evidence — see PROJECT-BIBLE §11
```

---

## Contributing

Read [PROJECT-BIBLE.md](PROJECT-BIBLE.md) before opening an issue or PR. It is the source of truth; §13 (non-negotiables) and §15 (non-goals) exist specifically to close scope debates.

Architectural changes require an ADR under [docs/architecture/decisions/](docs/architecture/decisions/).

See [CONTRIBUTING.md](CONTRIBUTING.md) for the code workflow.

---

## License

MIT. See [LICENSE](LICENSE).

Pry is part of the Neimad toolchain. Its sibling is [Smithy](https://github.com/neimad/smithy): Smithy builds, Pry tests.
