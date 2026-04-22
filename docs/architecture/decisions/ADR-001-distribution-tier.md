# ADR-001 — Distribution tier: direct / open source

**Status:** Accepted
**Date:** 2026-04-22
**Supersedes:** —
**Superseded by:** —

## Context

Neimad projects ship under one of three tiers: App Store, direct download (notarized), or open source. Pry must pick one. The product is a UI test runner that reads Markdown and injects real system events into a target macOS app.

## Decision

Pry ships **direct / open source (MIT)** on GitHub. No App Store. No sandbox.

Both components are MIT-licensed:

- `PryHarness` — Swift package, in-process, linked `#if DEBUG` into the target app.
- `pry-mcp` — CLI + MCP server, distributed as source and as a signed Homebrew tap binary.

## Rationale

- **Sandbox-incompatible by design.** `pry-mcp` uses the Accessibility API and `CGEventPost`. Both require user approval under System Settings → Privacy & Security; neither is permitted for sandboxed apps. App Store is off the table.
- **Infrastructure, not product.** Pry is plumbing for developers. Charging indie devs to install a test runner would be a category error.
- **Persona C requires it.** [PROJECT-BIBLE §3](../../../PROJECT-BIBLE.md#persona-c--external-swift-developer-future) locks that external Swift developers are a first-class persona. Closed-source or paid gates them out immediately.
- **The Smithy pairing.** Pry is Smithy's test companion; Smithy is also open infrastructure. Matching license and distribution keeps the mental model simple.

## Consequences

- We will never have a sandboxed build of `pry-mcp`. Accept.
- Homebrew tap requires Developer ID signing + notarization for the binary distribution path. The source path is always available for anyone who wants to build from checkout.
- No telemetry ever (also locked in [PROJECT-BIBLE §13](../../../PROJECT-BIBLE.md#13-non-negotiables)).
- Issues and PRs come from external contributors; CONTRIBUTING.md and PROJECT-BIBLE.md must be the arbiter of scope disputes, not conversation history.
