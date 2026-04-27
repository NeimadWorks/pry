# Architecture overview

> Companion to [PROJECT-BIBLE §6](../../PROJECT-BIBLE.md#6-architecture). Read that first.

## The four products

Pry ships as four SwiftPM products in one package:

| Product | Process | Purpose |
|---|---|---|
| `PryHarness` | In the target app | Passive socket server + `PryInspectable` protocol + `PryRegistry`. `#if DEBUG`-gated. |
| `PryWire` | Both sides | Codable JSON-RPC types. No logic, no dependencies. |
| `PryRunner` | Out-of-process | Runner library: spec parser, runner, verdict reporter, AX walker, event injector, `Pry` ergonomic actor API. Linkable from any Swift code. |
| `pry-mcp` | Out-of-process | Thin stdio MCP wrapper around `PryRunner`. Plus a CLI mode for hand-driven testing. |

`PryHarness` and `PryRunner` are the two *real* halves. `PryWire` is the contract glue between them. `pry-mcp` is just the daemon that exposes `PryRunner` over the MCP protocol — anything `pry-mcp` does, you can also do by `import PryRunner` directly.

## The two processes

Pry is deliberately two processes. One lives **inside** the target app (`PryHarness`), one lives **outside** (`PryRunner` — embedded in `pry-mcp` or in your own Swift code). They communicate over a Unix-domain socket using plain JSON-RPC 2.0.

| Concern | Location | Why there |
|---|---|---|
| Event injection (clicks, keys) | `pry-mcp` (outside) | `CGEventPost` from within the same process is filtered by AppKit's synthetic-event heuristics. |
| AX tree queries | `pry-mcp` (outside) | AX-on-self is discouraged by Apple and fragile across sandboxed children. |
| App lifecycle (launch/terminate) | `pry-mcp` (outside) | Obvious. |
| ViewModel / `Mirror` reads | `PryHarness` (inside) | SwiftUI state and `ObservableObject`s are only reachable in-process. |
| `OSLogStore` tail | `PryHarness` (inside) | Subsystem filtering is simpler when bound to the app's own signposts. |
| Window pixel snapshots | `PryHarness` (inside) | Simpler to target self-window via `CGWindowID`; also lets us grab during overlay transitions. |
| Markdown spec parsing | `pry-mcp` (outside) | The runner orchestrates; harness stays passive. |
| Verdict reporting | `pry-mcp` (outside) | Runner owns the ground truth of the run. |

**Rule of thumb:** PryHarness is passive — it answers queries. pry-mcp is active — it drives.

## Sequence: `pry_run_spec`

```
Claude Code         pry-mcp                      target app (PryHarness)
     │                 │                                    │
     │ pry_run_spec ──▶│                                    │
     │                 │ parse spec                         │
     │                 │ launch app (NSWorkspace) ────────▶ │
     │                 │                                    │ PryHarness.start()
     │                 │ connect /tmp/pry-<bundle>.sock ◀──▶│ socket up
     │                 │                                    │
     │                 │ (for each step)                    │
     │                 │   resolve target via AX ◀──────────│ (external AX query, no socket traffic)
     │                 │   inject CGEvent ─────────────────▶│ OS → AppKit → SwiftUI
     │                 │   read_state / read_logs ─────────▶│ Mirror, OSLogStore
     │                 │                                    │
     │                 │ format verdict.md                  │
     │ ◀── verdict ────│                                    │
```

## Why JSON-RPC on a Unix socket

- **No network** — `AF_UNIX` is localhost-only by construction. Zero attack surface.
- **No auth** — the filesystem permission on the socket is the auth.
- **No serialization dep** — `JSONEncoder` / `JSONDecoder` ship with Foundation. The wire protocol is ~200 lines of Swift.
- **No external MCP SDK** — stdio JSON-RPC for the Claude Code side is another ~200 lines. [Discussed in ADR-002](decisions/ADR-002-two-process-split.md).

## Module boundaries (what goes where)

### `PryHarness` (in-process Swift package)

Allowed: socket server, `Mirror` walker, `OSLogStore` tail, `CGWindowListCreateImage`, `PryInspectable` protocol.

Forbidden: event injection, spec parsing, verdict formatting, MCP protocol, any code that must run when the target app is not running.

### `PryWire` (shared package)

Contains only Codable message types that flow on the socket. No logic. No dependencies. Imported by both `PryHarness` and `pry-mcp` so the wire contract is enforced at compile time.

### `PryRunner` (out-of-process library)

Allowed: app lifecycle (`AppDriver`), AX queries (`ElementResolver`, `AXTreeWalker`), CGEvent injection (`EventInjector`), spec parsing (`SpecParser`), spec running (`SpecRunner`), verdict formatting (`VerdictReporter`), window capture (`WindowCapture`), client side of the harness socket (`HarnessClient`), top-level ergonomic API (`Pry`).

Forbidden: any UI code, any `Mirror` reflection on the target's types, MCP protocol concerns.

### `pry-mcp` (out-of-process binary)

Allowed: stdio MCP server (`MCPServer`), tool dispatch (`PryTools`), CLI subcommand parser (`CLI`). Imports `PryRunner` and exposes it.

Forbidden: any logic that should be reusable from non-MCP callers — that goes in `PryRunner` instead.

## Repo layout

```
pry/
├── PROJECT-BIBLE.md
├── CLAUDE.md
├── README.md
├── LICENSE
├── Package.swift
│
├── Sources/
│   ├── PryHarness/
│   │   ├── PryHarness.swift
│   │   ├── PryRegistry.swift
│   │   ├── PrySocketServer.swift
│   │   ├── PryInspector.swift
│   │   ├── PryInspectable.swift
│   │   └── PryLogTap.swift
│   ├── PryWire/
│   │   └── Messages.swift
│   ├── PryRunner/
│   │   ├── Pry.swift                    # ergonomic actor API
│   │   ├── Spec/{Spec,Step,SpecParser,SpecRunner,YAMLFlow}.swift
│   │   ├── Verdict/{Verdict,VerdictReporter}.swift
│   │   ├── Control/{ElementResolver,EventInjector,AXTreeWalker,WindowCapture}.swift
│   │   └── Driver/{AppDriver,HarnessClient}.swift
│   └── pry-mcp/
│       ├── main.swift
│       ├── CLI.swift
│       └── MCP/{MCPServer,Tools}.swift
│
├── Tests/
│   ├── PryHarnessTests/
│   ├── PryWireTests/
│   └── PryMCPTests/
│
├── docs/
│   ├── architecture/{overview.md, decisions/, diagrams/}
│   ├── design/{principles.md, spec-format.md, verdict-format.md}
│   ├── api/{PryHarness.md, PryWire.md, pry-mcp-tools.md}
│   └── guides/{writing-specs.md}
│
├── Fixtures/DemoApp/   # tiny SwiftUI app used by spikes and integration tests
└── spikes/             # retained spike evidence (see PROJECT-BIBLE §11)
```

No orphan folders. No `Utilities/`, no `Common/`, no `Helpers/`. Every directory justifies its existence in one sentence.

## Life of a test run

1. Claude Code (or a human) writes `flows/new-document.md`.
2. The agent calls the MCP tool `pry_run_spec(path: "flows/new-document.md")`.
3. `pry-mcp` parses the spec, launches the target app via `NSWorkspace.open(_:)`, and waits for the harness socket to appear.
4. For each step: resolve target (if any) → inject event (if any) → wait for predicate (if any) → record observation.
5. On first failing step: capture AX tree, registered state, recent logs, optional PNG snapshot. Stop.
6. Emit the verdict as Markdown with YAML frontmatter. Return its contents as the MCP tool result. Write the file to `./pry-verdicts/<spec-id>-<timestamp>.md`.

## Related ADRs

- [ADR-001 — Distribution tier: direct / open source](decisions/ADR-001-distribution-tier.md)
- [ADR-002 — Two-process split](decisions/ADR-002-two-process-split.md)
- [ADR-003 — Markdown test spec format](decisions/ADR-003-markdown-spec-format.md)
- [ADR-004 — State introspection protocol](decisions/ADR-004-state-introspection-protocol.md)
- [ADR-005 — Event injection strategy](decisions/ADR-005-event-injection-strategy.md)
