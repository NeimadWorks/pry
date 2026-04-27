# ADR-009 — Animation gating

**Status:** Accepted
**Date:** 2026-04-27

## Context

SwiftUI implicit animations make snapshot timing flaky. AppKit transitions
between view states leave a window for a few hundred milliseconds.

## Decision

PryHarness exposes a "animations off" toggle that the test runner can flip:

- `setAnimationsEnabled(false)` — applies `NSAnimationContext`-wide `.duration = 0`
  and sets `CATransaction.disableActions(true)`.
- `setAnimationsEnabled(true)` — restores defaults.

Spec grammar gains `animations: off` in frontmatter (default `on`) and a
`set_animations: off|on` step.

## Rationale

When animations matter for the test (a fade-in must complete before a click),
keep them on and use `wait_for_idle`. Otherwise turn them off and remove a
class of flake source.

## Consequences

The host app gains one extra responsibility: respect the global animation
disable signals. Default SwiftUI/AppKit do, so the cost is zero for most apps.
