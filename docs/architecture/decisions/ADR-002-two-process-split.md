# ADR-002 — Two-process split

**Status:** Accepted
**Date:** 2026-04-22
**Supersedes:** —
**Superseded by:** —

## Context

A UI test runner needs two capabilities that cannot cleanly coexist in one process:

1. **Drive the app** — inject clicks, type keys, resolve elements via AX, manage app lifecycle.
2. **Observe the app** — read `ObservableObject` state, tail `OSLog`, snapshot windows.

## Decision

Pry splits into two components communicating via a Unix-domain socket with JSON-RPC 2.0:

- `PryHarness` — in-process, passive, answers queries only.
- `pry-mcp` — out-of-process, active, drives the app and runs specs.

## Rationale

- **`CGEventPost` from within the target process is unreliable.** AppKit applies synthetic-event heuristics to events that originate in the same process; some are silently dropped. A separate process is the supported pathway for real event injection.
- **AX on self is discouraged.** Apple's guidelines steer you toward out-of-process AX clients. In-process AX queries behave inconsistently under App Nap, and fail under future sandboxed extensions.
- **In-process reflection is the only way to see ViewModel state.** `Mirror`, `@Published`, and anything typed-erased behind `ObservableObject` is not observable from another process. The `PryInspectable` protocol lives in `PryHarness` because it has to.
- **Splitting is cheaper than it looks.** Unix socket + JSON-RPC is ~200 lines each side. Shared `Codable` types in `PryWire` enforce the contract at compile time. No external serialization dependency, per [PROJECT-BIBLE §5](../../../PROJECT-BIBLE.md#5-tech-stack).

## Alternatives considered

- **Single in-process framework.** Rejected: event injection and AX reliability.
- **XPC service.** Rejected: heavier than needed, adds `launchd` plist ceremony, and gives us nothing a Unix socket doesn't.
- **Mach ports.** Rejected: more primitive than we need, no Codable story.
- **Local TCP socket.** Rejected: would cross the network boundary, enabling exposure risk. Violates [PROJECT-BIBLE §13](../../../PROJECT-BIBLE.md#13-non-negotiables) ("no network calls, ever").

## Consequences

- Two release artifacts to maintain. Acceptable — they change slowly and share `PryWire`.
- Socket lifecycle needs careful handling: orphaned sockets after crashes must be cleaned up on `PryHarness.start()`.
- Inter-process debugging is slightly more work. Mitigated by rich verdict reports ([ADR-003](ADR-003-markdown-spec-format.md)).
- Contract is policed by `PryWire`: any new message type must be added there before either side can use it.
