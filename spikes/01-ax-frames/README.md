# Spike 01 — AX frames reliability across SwiftUI view types

**Also answers Spike 03** (AXIdentifier propagation). One driver, two verdicts. See [`../03-ax-identifier/README.md`](../03-ax-identifier/README.md) for the pointer.

## Binary questions

- **Spike 1** — Does `AXUIElementCopyAttributeValue(.frame)` on SwiftUI views return screen coordinates matching the actual hit-test region, across view types (Button, Toggle, custom `.onTapGesture`, TextField, Text, List)?
- **Spike 3** — Does `.accessibilityIdentifier("foo")` on a SwiftUI view reliably surface as `AXIdentifier` queryable from an external process, across the same view types?

## Why together

Both are structural properties of the SwiftUI → AX bridge. They test the same fixture the same way — enumerating the tree once, inspecting attributes, doing one click per clickable element. Splitting into two separate runners would duplicate code without adding signal.

## Method

1. Launch `Fixtures/DemoApp` with `PRY_MARKER_FILE` set to a temp path.
2. Wait up to 5s for the main window to appear; wait an extra 400 ms for layout to settle.
3. Walk the AX tree once; index every element that has `AXIdentifier`.
4. For each expected identifier, record: **present**, **role**, **frame**, **frame sane** (non-zero, intersects window).
5. For each clickable target (`new_doc_button`, `verbose_toggle`, `tap_zone`), inject a click at the frame's center and check whether the expected marker event lands in the marker file within 1.5s.
6. Emit a single PASS/FAIL per spike.

## Prerequisites

- macOS 14+.
- Parent process (Terminal / IDE) trusted for Accessibility (same prerequisite as Spike 2).

## How to run

```sh
cd Fixtures/DemoApp && swift build && cd -
cd spikes/01-ax-frames
DEMO=$(cd ../../Fixtures/DemoApp && pwd)/.build/debug/DemoApp
swift run spike01 "$DEMO"
echo "exit: $?"
```

Exit code `0` = both spikes PASS. `1` = at least one FAIL. `2` = bad invocation.

## Verdict

```
Spike 1 — AX frames reliability:     [ ] PASS [ ] FAIL
Spike 3 — AXIdentifier propagation:  [ ] PASS [ ] FAIL
```

Once concluded, copy results into [PROJECT-BIBLE §11](../../PROJECT-BIBLE.md#11-validated-assumptions).

### Evidence

```
macOS version:
Swift version:
Run count (N/N):
Observations:
```

### Decision branches

- **Both PASS** → `id`-first resolution (`.accessibilityIdentifier` → `AXIdentifier`) stays as the highest-precedence strategy in [docs/design/spec-format.md §4](../../docs/design/spec-format.md#4-target-grammar). No change to any ADR.
- **Spike 3 FAILS on any view type** → document the affected types in the spec-format reference; on those types, fall back to `role+label`. If failure is systemic, promote the `.pryTagged("id")` modifier (PryHarness-side registry) per [PROJECT-BIBLE §11 branch decisions](../../PROJECT-BIBLE.md#branch-decisions).
- **Spike 1 FAILS on any view type** → require `accessibilityIdentifier` for the affected types (best-practice docs), and note that raw AX frames are unreliable for those shapes. Click resolution will need a frame correction pass.
- **Both FAIL** → write an ADR superseding ADR-005 before any further work. The control strategy needs rethinking.
