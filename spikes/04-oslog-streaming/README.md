# Spike 04 — `OSLogStore` streaming latency

## Binary question

Can an in-process `OSLogStore` tail pick up a freshly emitted log entry in under 200 ms end-to-end? Is subsystem filtering stable?

## Why it matters

PryHarness streams the target app's logs into verdicts (`assert_logs`, `assert_no_errors`, step-level log attachments). If latency is routinely hundreds of milliseconds, assertions racing a log line will flake, and the "relevant logs" diagnostic section in verdicts will lag behind the failure.

## Method

In-process measurement. When launched with `PRY_SPIKE_LOG_LATENCY=1`, DemoApp:

1. Opens `OSLogStore(scope: .currentProcessIdentifier)`.
2. Runs 10 iterations:
   - Marks a tag `spike4-<i>-<uuid>`.
   - Logs `tag` at `.info` level via `Logger(subsystem: "fr.neimad.pry.demoapp", category: "spike4")`.
   - Polls `store.getEntries(at:matching:)` with `NSPredicate(subsystem == X AND category == Y)` until the tag is seen or 2 s elapse.
   - Records the observation latency in milliseconds.
3. Writes `log_latency_complete` to the marker file with `p50_ms`, `p95_ms`, `max_ms`, `timeouts`, `samples_ms`.
4. Terminates.

Runner (`spike04`) launches DemoApp with the env flag, reads the marker line, and verdicts:

- **PASS** iff `p95_ms < 200` **AND** `timeouts == 0`.
- **FAIL** otherwise.

### Why in-process

`OSLogStore(scope: .system)` requires the `com.apple.developer.system-log` entitlement — not a path Pry wants to take. PryHarness will always tail its own process's logs (which is exactly `scope: .currentProcessIdentifier`), so the measurement here matches production behavior.

## Prerequisites

- macOS 14+.
- No Accessibility permission required for this spike (no event injection).

## How to run

```sh
cd Fixtures/DemoApp && swift build && cd -
cd spikes/04-oslog-streaming
DEMO=$(cd ../../Fixtures/DemoApp && pwd)/.build/debug/DemoApp
swift run spike04 "$DEMO"
echo "exit: $?"
```

Takes up to ~25 s (10 iterations × up-to-2 s each plus 50 ms gaps). Typically completes much faster.

## Verdict

```
[ ] PASS
[ ] FAIL
```

### Prior run discarded (2026-04-22)

First run reported p50 ~1.2 s and p95 ~3.7 s. **Measurement bug:** `store.position(date: t0 - 0.1s)` was called between `t0 = Date()` and `logger.info(tag)`. `position(date:)` walks the store and can cost several hundred ms, which fell inside the timing window. The latency number was dominated by that bookkeeping call, not by actual log flush latency.

Fix: move position capture **outside** the `t0 → t1` window and use `position(timeIntervalSinceEnd:)` (O(1)) instead of `position(date:)`. Awaiting re-run.

### Evidence

```
macOS version:
Swift version:
Run count:
p50 / p95 / max (ms):
Timeouts:
Notes:
```

### Decision branches

- **PASS** → `assert_logs` / `assert_no_errors` behaviors in [docs/design/spec-format.md](../../docs/design/spec-format.md) are supported as primary capabilities.
- **p95 ∈ [200, 500] ms** → keep the capability but document the latency; `assert_logs` defaults gain a `timeout: 1s` built-in.
- **p95 > 500 ms or timeouts > 0** → log capability is marked experimental in the MCP tool reference; `pry_logs` still ships for manual inspection but `assert_logs` is removed from v1 spec grammar. [PROJECT-BIBLE §11 branch decision](../../PROJECT-BIBLE.md#branch-decisions).
