# Spikes

This directory holds the evidence for the five pre-implementation spikes listed in [PROJECT-BIBLE §11](../PROJECT-BIBLE.md#11-validated-assumptions).

Each spike:

- lives in its own numbered folder (`01-ax-frames/`, `02-cgevent-acceptance/`, …)
- contains one Swift file that asks **one binary question**
- ends with a `README.md` that records **PASS** or **FAIL** and the evidence (log output, screenshot, notes) that justifies the verdict
- does not get deleted after the spike concludes — future sessions revisit the evidence when rethinking a branch decision

## Template

```
spikes/NN-short-name/
├── README.md        # question, method, verdict, evidence
├── Main.swift       # the spike
└── evidence/        # logs, screenshots, trace files (optional)
```

## Branch decisions

Covered in [PROJECT-BIBLE §11](../PROJECT-BIBLE.md#branch-decisions). Once a spike resolves:

1. Update the `[ ]` checkbox in PROJECT-BIBLE §11 to `[x]` with PASS or FAIL.
2. Write the spike's `README.md` with the evidence.
3. If a branch decision triggers (e.g. "if 2 FAILS → fallback to AX actions"), write a new ADR that supersedes the affected one.

## Status

- `01-ax-frames/` — ✅ PASS (2026-04-22, 6/6 view types)
- `02-cgevent-acceptance/` — ✅ PASS (2026-04-22, macOS 26.4.1)
- `03-ax-identifier/` — ✅ PASS (2026-04-22, covered by 01-ax-frames driver)
- `04-oslog-streaming/` — ⏳ not started
- `05-mirror-introspection/` — ⏳ not started
