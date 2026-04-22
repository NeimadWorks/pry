# Pry

> The test runner that reads Markdown and clicks like a human.

Pry runs Markdown test scripts against macOS apps and returns verdicts [Claude Code](https://claude.com/claude-code) can act on. No screenshots. No pixel diffs. No XCUITest.

```
┌── spec ──┐                 ┌── verdict ──┐
│ click:   │  ── pry run ──▶ │ FAILED at   │
│ "Save"   │                 │ step 6 ...  │
└──────────┘                 └─────────────┘
```

**Status:** pre-spike. The architecture is locked (see [`PROJECT-BIBLE.md`](PROJECT-BIBLE.md)) but nothing ships until the five spikes in §11 return green. Expect the API to move before `v0.1`.

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

> Not yet shippable. Tracking toward `v0.1` once the spike results in [§11 of PROJECT-BIBLE](PROJECT-BIBLE.md#11-validated-assumptions) are green.

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

### 3. Install `pry-mcp`

```sh
brew install neimad/tap/pry-mcp
```

### 4. Write a spec

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

### 5. Run it

```sh
pry run flows/new-document.md
```

Or register the MCP server and let Claude Code call `pry_run_spec` directly.

---

## Spec format

A Pry test is a Markdown file with YAML frontmatter and fenced `pry` code blocks containing steps. The grammar is documented in [docs/design/spec-format.md](docs/design/spec-format.md). Verdict format: [docs/design/verdict-format.md](docs/design/verdict-format.md).

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
