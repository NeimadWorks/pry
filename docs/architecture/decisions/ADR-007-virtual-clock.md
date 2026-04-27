# ADR-007 — Virtual clock (`PryClock`)

**Status:** Accepted
**Date:** 2026-04-27

## Context

Real apps depend on `Date.now`, `Timer`, `DispatchQueue.asyncAfter`, debouncing,
animation timing, scheduled work, and polling. Tests that wait real-time for
those mechanisms are slow, flaky, and unable to verify time-based behaviors
that span minutes or hours.

## Decision

PryHarness exposes an in-process `PryClock` that the host app **opts into** by
calling `clock.now`, `clock.timer(...)`, `clock.sleep(...)` instead of
`Date()`/`Timer.scheduledTimer(...)`/`Task.sleep(...)`. In RELEASE the clock
delegates to the system. In DEBUG, `pry-mcp` (or any `PryRunner` client) can:

- read the clock (`clock.now`)
- set the clock to an absolute date
- advance the clock by a duration, firing all scheduled work whose deadline
  falls within that window in chronological order
- pause and resume the clock

Adoption is incremental: any subsystem still using `Date()` directly stays
real-time. Subsystems wrapped in `PryClock` become deterministic.

## Wire surface

Three new methods on the harness socket: `clock_get`, `clock_set`,
`clock_advance`. Their results are simple ISO 8601 timestamps + a count of
scheduled callbacks that fired during the operation.

## Rationale

- Adoption is opt-in per code path. Apps can adopt incrementally.
- No magic interception of `Date()` (would require swizzling).
- The clock state is per-process; no global TimeMachine. Safer.
- API mirrors point-libre's clock pattern that's already familiar to TCA users.

## Alternatives considered

- Method swizzling on `Date.init()` — rejected, fragile, breaks Foundation expectations.
- Mach absolute time injection — rejected, too low-level, doesn't help with `Timer`.
- Global setter à la `XCTest.skipUI` — rejected, hides scope, leaks across tests.

## Consequences

- Apps that want full time control must wrap their `Date.now`, `Timer`,
  `DispatchQueue.asyncAfter`, and `Task.sleep` calls in `PryClock` equivalents.
- Tests that don't need virtual time work unchanged.
- A future ADR may add a `Clock` protocol conformance to bridge with
  swift-foundation's `ClockProtocol`.
