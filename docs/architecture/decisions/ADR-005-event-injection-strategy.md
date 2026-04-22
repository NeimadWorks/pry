# ADR-005 — Event injection strategy

**Status:** Accepted (Spike 2 validated 2026-04-22)
**Date:** 2026-04-22
**Supersedes:** —
**Superseded by:** —

## Context

Pry must drive the target app the way a user would — clicks, types, keyboard shortcuts, scrolls. The implementation choices are:

1. `CGEventPost(.cgSessionEventTap, ...)` — low-level event injection at the session tap.
2. AX actions — `AXUIElementPerformAction(_: kAXPressAction)`, `AXUIElementSetAttributeValue(_:, kAXValueAttribute, ...)`.
3. In-process dispatch — call the action handler directly via reflection.

## Decision

**Primary:** `CGEventPost(.cgSessionEventTap, ...)` at AX-resolved screen coordinates.

**Fallback:** AX actions (`AXPress`, `AXSetValue`) for cases where Spike 2 reveals synthetic-event filtering on specific element types.

**Rejected:** In-process dispatch. Violates [Invariant 3](../../../PROJECT-BIBLE.md#14-invariants) — "event injection goes through the real system event path."

## Rationale

- **CGEvent goes through the full path.** The OS → WindowServer → AppKit → SwiftUI chain is the user's path. Gestures, focus changes, first-responder promotion, hover effects — all exercised identically to a human run.
- **AX actions skip steps.** `AXPress` on a button calls its action handler but bypasses hit-testing, mouse move, focus changes. Useful as a fallback; not a substitute.
- **In-process dispatch is a lie.** If we call `button.action` directly we are not testing the button — we are testing our ability to find and call its closure. Tests pass that should fail.

## Conditional on Spike 2

This ADR is the canonical decision **if** [Spike 2](../../../PROJECT-BIBLE.md#11-validated-assumptions) passes: synthetic `CGEvent`s at AX-resolved coordinates reliably trigger SwiftUI `Button` actions and `.onTapGesture` modifiers on macOS 14 and 15.

If Spike 2 fails:
- Write ADR-00N superseding this one.
- Promote AX-action-based injection to primary.
- Accept reduced coverage on custom gestures; document the gap in [docs/design/spec-format.md](../../design/spec-format.md).

If Spike 1 (AX frames reliability) fails on some SwiftUI views:
- This ADR stands, but `accessibilityIdentifier` becomes the required default resolution strategy. See [docs/design/spec-format.md](../../design/spec-format.md) for the resolution order.

## Consequences

- `pry-mcp` requires Accessibility permission (System Settings → Privacy & Security → Accessibility). First-run UX must explain this clearly.
- We own coordinate resolution from AX frames to screen coordinates (accounting for `NSScreen` geometry and multiple displays).
- Event timing matters: a `mouseDown` / `mouseUp` pair needs a small deliberate gap (~20 ms) to register as a click on some elements. Exact value pinned by Spike 2 evidence.
