# Spike 02 — Synthetic CGEvent acceptance

## Binary question

Does `CGEventPost(.cgSessionEventTap, ...)` with a mouseDown/mouseUp pair at AX-resolved coordinates actually trigger a SwiftUI `Button` action on macOS 14+? Are events ever filtered as "synthetic"?

## Why it matters (blast radius)

This spike drives [ADR-005](../../docs/architecture/decisions/ADR-005-event-injection-strategy.md). If it fails, the entire event-injection strategy changes:

- PASS → canonical architecture ships; `CGEventPost` is the primary event path.
- FAIL → ADR-005 is superseded; fallback to `AXUIElementPerformAction(kAXPressAction)` for buttons and `AXUIElementSetAttributeValue(kAXValueAttribute, ...)` for text fields. Lower coverage on custom gestures.

## Method

1. Build `Fixtures/DemoApp`. DemoApp has a `Button` with `accessibilityIdentifier("new_doc_button")` whose handler writes a line `<timestamp> button_clicked ...` to the path in `$PRY_MARKER_FILE`.
2. Spike runner (`spike02`) launches DemoApp as a subprocess with `PRY_MARKER_FILE` set to a temp file.
3. Polls the application's AX tree until a node with `AXIdentifier == "new_doc_button"` appears.
4. Reads its `AXPosition` + `AXSize`, computes center.
5. Posts a `leftMouseDown` + `leftMouseUp` pair at the center via `CGEventPost(.cgSessionEventTap, ...)` with a 30 ms gap.
6. Polls the marker file for up to 2 s.
7. PASS if the marker contains `button_clicked`. FAIL otherwise.

## Prerequisites

- macOS 14 or later.
- **The process running the spike must be trusted for Accessibility.** On first run you'll get a permission prompt; in practice you grant Terminal (or the IDE running `swift run`).
- No other app must have keyboard/mouse focus during the run — `CGEventPost` targets the session event tap globally.

## How to run

```sh
# 1. Build DemoApp (produces Fixtures/DemoApp/.build/debug/DemoApp)
cd Fixtures/DemoApp && swift build && cd -

# 2. Build and run the spike, passing the DemoApp binary path.
#    Use an absolute path — Process.executableURL resolves relative paths
#    against CWD, which is the spike dir once swift run is active.
cd spikes/02-cgevent-acceptance
DEMO=$(cd ../../Fixtures/DemoApp && pwd)/.build/debug/DemoApp
swift run spike02 "$DEMO"
echo "exit: $?"
```

Exit code `0` = PASS, `1` = FAIL, `2` = bad invocation.

All spike logs go to stderr with `[spike02]` prefix.

## Expected output shape

### PASS

```
[spike02] launched DemoApp pid=12345
[spike02] marker file: /var/folders/.../pry-spike02-....marker
[spike02] resolved button frame: (350.0, 72.0, 130.0, 24.0)
[spike02] clicking at (415.0, 84.0)
[spike02] marker observed: 2026-04-22T... button_clicked clickCount=1 docsCount=1
[spike02] PASS — CGEventPost(.cgSessionEventTap) at AX-resolved coords triggered the SwiftUI Button action
```

### FAIL modes worth distinguishing

- **"this process is not trusted for Accessibility"** — grant permission, retry.
- **"did not find AX element with AXIdentifier=new_doc_button within 5s"** — AX tree did not expose the identifier. This is actually data for [Spike 3](../03-ax-identifier/) (and forces a change to the default resolution strategy). For Spike 2's purposes, treat as ERROR-not-FAIL and note in evidence.
- **"no button_clicked marker observed within 2s"** — the event was delivered to the system but did not reach the SwiftUI Button. This is the true FAIL for Spike 2.

## Verdict

```
[ ] PASS
[ ] FAIL  — evidence: <path to log, screenshot if relevant>
```

Update this section with the result and copy the corresponding `[x]` into [PROJECT-BIBLE §11](../../PROJECT-BIBLE.md#11-validated-assumptions) once concluded.

### Evidence

*To be filled when spike is run. Paste stderr output, note macOS version, note whether retry behavior matters.*

```
macOS version:
Xcode / Swift version:
Run count (N/N pass):
Observations:
```
