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

**Status:** `v0.1.0-dev`. All five spikes green (one triggered [ADR-006](docs/architecture/decisions/ADR-006-log-observation-strategy.md) to drop real-time log assertions). Spec runner end-to-end: `pry-mcp run --spec flows/new-document.md` against the DemoApp fixture produces a PASS verdict in ~1 s. Breaking changes to the spec grammar bump `pry_spec_version`.

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

Pry is two components:

- **PryHarness** — a Swift package you link into your app under `#if DEBUG`. Exposes a passive Unix-socket server for state reads, log tails, and snapshots. Zero effect on RELEASE builds.
- **pry-mcp** — an out-of-process CLI + MCP server. Launches your app, resolves targets via the Accessibility API, injects real `CGEvent`s, runs Markdown specs, writes verdicts.

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

A Pry test is a Markdown file with YAML frontmatter and fenced `pry` code blocks containing steps. The grammar is documented in [docs/design/spec-format.md](docs/design/spec-format.md). Verdict format: [docs/design/verdict-format.md](docs/design/verdict-format.md).

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
  PryHarness/   in-process Swift library (linked into your app, DEBUG only)
  PryWire/      shared JSON-RPC message types
  pry-mcp/      out-of-process CLI + MCP server
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
