# ADR-006 — Log observation strategy

**Status:** Accepted
**Date:** 2026-04-22
**Supersedes:** — (refines [ADR-002](ADR-002-two-process-split.md) module boundaries)
**Superseded by:** —

## Context

[Spike 4](../../../spikes/04-oslog-streaming/README.md) measured `OSLogStore` latency for same-process reads: p50 ~1.2 s, p95 ~3.6 s. The investigation isolated the cost to a single `getEntries()` call — with `poll_count == 1` on every iteration, `OSLogStore` does not provide real-time visibility into `os_log` emissions on macOS.

This invalidates assertion-grade log checks as originally drafted in the Markdown spec grammar.

## Decision

Log observation splits into two tiers:

### Tier 1 — `OSLogStore`-backed, best-effort, ~1 s latency (v1)

- `pry_logs` MCP tool ships. It reads `OSLogStore` with scope `.currentProcessIdentifier` from within `PryHarness`.
- Used post-hoc by the verdict reporter to attach "Relevant logs (last Ns)" to failure reports.
- Documented as **best-effort**, not a real-time channel.

### Tier 2 — PryHarness-side log tee, real-time (v2, deferred)

- `PryHarness` exposes a `PryLog` wrapper around `Logger` that both calls `os_log(_:)` AND appends to an in-memory ring buffer + on-disk tail file. Opt-in: app imports `PryLog` instead of `Logger`.
- The on-disk tail is read live by `pry-mcp`, giving assertion-grade latency.
- Not in scope for v1. Requires a public surface change to `PryHarness` and opt-in per app.

### Removed from v1 spec grammar

The following commands from the earlier draft of [docs/design/spec-format.md](../../design/spec-format.md) are **removed** from `pry_spec_version: 1`:

- `assert_logs: { contains: "...", since: <step_ref> }`
- `assert_no_errors`

These would race unflushed log entries under Tier 1 semantics and produce flakes. They return in v2 once Tier 2 is available.

## Rationale

- **Accuracy over capability.** Principle 8 (no flakiness tolerance) means we must not ship an assertion that can race the unified log flush. A slow-but-correct capability (`pry_logs` for audit) is preferable to a fast-but-flaky one (`assert_logs` over `OSLogStore`).
- **No new dependencies.** Tier 2 uses only `Logger`, `FileHandle`, and a ring buffer — all Foundation / OSLog. No custom log framework, no subscribers pattern.
- **Opt-in keeps the default simple.** Persona C can adopt Pry without switching log APIs. Only teams that need real-time log assertions pay the `PryLog`-instead-of-`Logger` cost.
- **Separation matches ADR-002.** The tee lives in `PryHarness` (in-process, passive) — `pry-mcp` still only reads state through well-defined channels.

## Alternatives considered

- **Private `log stream`-style API.** Rejected: private API, notarization and long-term compatibility risk.
- **Tail `log stream` as a child process.** Rejected: process management complexity, stderr parsing, and a cross-process dependency for what should be a fast path.
- **Use `os_signpost` instead of `os_log`.** Signposts have different semantics (interval markers) and don't carry arbitrary message payloads well. Wrong tool.
- **Accept the latency and ship `assert_logs` with a big default timeout.** Rejected: masks failures as timeouts and produces slow verdicts. Flakiness in disguise.

## Consequences

- v1 verdict reports still contain a "Relevant logs" section — populated from `OSLogStore` at verdict-write time, when the flush has already happened. Accuracy for post-hoc inspection is fine.
- Users asking "can Pry assert on a log line?" get a "not in v1" answer pointing to this ADR.
- Tier 2 has a design placeholder in [PROJECT-BIBLE §16](../../../PROJECT-BIBLE.md#16-open-questions-pre-spike) (add Q5).
- `docs/api/pry-mcp-tools.md` marks `pry_logs` latency explicitly.
- `docs/design/spec-format.md` removes the Observation commands that depend on real-time logs.
