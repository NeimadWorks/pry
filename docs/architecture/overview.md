# Architecture overview

> Companion to [PROJECT-BIBLE §6](../../PROJECT-BIBLE.md#6-architecture). Read that first.

## The two components

Pry is deliberately two processes. One lives **inside** the target app (`PryHarness`), one lives **outside** (`pry-mcp`). They communicate over a Unix-domain socket using plain JSON-RPC 2.0.

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

### `pry-mcp` (out-of-process binary)

Allowed: MCP stdio server, app lifecycle, AX queries, CGEvent composition, spec parsing, spec running, verdict formatting.

Forbidden: any UI code, any `Mirror` reflection on the target's types, anything that would need to run inside the target.

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
│   │   └── PryLogTap.swift
│   ├── PryWire/
│   │   └── Messages.swift
│   └── pry-mcp/
│       ├── main.swift
│       ├── MCP/MCPServer.swift
│       ├── Driver/{AppDriver,HarnessClient}.swift
│       ├── Control/{ElementResolver,EventInjector}.swift
│       ├── Spec/{SpecParser,SpecRunner}.swift
│       └── Verdict/VerdictReporter.swift
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
