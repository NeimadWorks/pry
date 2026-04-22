# Spike 03 — `accessibilityIdentifier` propagation

**Answered by [`../01-ax-frames/`](../01-ax-frames/)** — the combined driver enumerates AX identifiers across every view type in `Fixtures/DemoApp` as part of its single pass. Running `spike01` produces the Spike 3 verdict alongside Spike 1's.

Kept as a separate folder to preserve the formal §11 tracking.

## Binary question

Does `.accessibilityIdentifier("foo")` on a SwiftUI view reliably surface as `AXIdentifier` queryable from an external process, across `Button`, `Toggle`, `TextField`, `Text`, `List`, and custom `.onTapGesture` views?

## How to run

See [`../01-ax-frames/README.md`](../01-ax-frames/README.md).

## Verdict

Copied from the Spike 1 run. Update both checkboxes in [PROJECT-BIBLE §11](../../PROJECT-BIBLE.md#11-validated-assumptions) from the same evidence.
