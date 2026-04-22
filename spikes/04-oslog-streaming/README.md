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
[x] FAIL
```

Date: 2026-04-22. Reflected in [PROJECT-BIBLE §11](../../PROJECT-BIBLE.md#11-validated-assumptions). Triggers the "p95 > 500 ms" branch → `assert_logs` / `assert_no_errors` removed from v1 spec grammar. See [ADR-006](../../docs/architecture/decisions/ADR-006-log-observation-strategy.md).

### Run history

**Run 1 — discarded (measurement bug).** `store.position(date: t0 - 0.1s)` was called inside the `t0 → t1` window. `position(date:)` walks the store (hundreds of ms), which inflated the reported latency. Fix: moved capture outside the window and switched to `position(timeIntervalSinceEnd:)`.

**Run 2 — final.** Fix verified via instrumented breakdown: `position` is now ~0 ms, and the full latency is inside the single `getEntries()` call. Result reproducible and diagnostic is clear.

### Evidence (run 2)

```
macOS version:  26.4.1 (build 25E253)
Swift version:  6.3.1 (swiftlang-6.3.1.1.2)
Run count:      1/1 (FAIL, stable)
iterations:     10
timeouts:       0
p50:            1205.7 ms
p95:            3558.9 ms   (first sample cold-start)
max:            3558.9 ms
threshold:      p95 < 200 ms, 0 timeouts
```

Per-iteration breakdown:

```
  #    latency  position  1st-getEntries  polls
  0     3558.9       0.0          3558.6      1
  1     1269.1       0.0          1268.8      1
  2     1264.4       0.0          1264.1      1
  3     1205.7       0.0          1205.3      1
  4     1204.6       0.0          1204.0      1
  5     1200.0       0.0          1199.4      1
  6     1211.3       0.0          1210.7      1
  7     1197.2       0.0          1196.6      1
  8     1198.7       0.0          1198.0      1
  9     1200.9       0.0          1200.1      1
```

### Interpretation

- `position()` cost is effectively 0 after the fix. The bookkeeping lie is eliminated.
- `poll_count == 1` on every iteration: the first `getEntries` call already sees the tag. There is no "poll-and-wait" component.
- The ~1.2 s is entirely inside one `getEntries` call. Two possible causes, practically indistinguishable:
  - **H1** — `getEntries` itself is IPC-heavy (query to `logd`, `tracev3` decompression).
  - **H2** — `getEntries` blocks until the unified log flushes recent entries.

The product decision is the same regardless: `OSLogStore` is **not** a real-time observation channel on macOS. It is an audit/post-hoc query tool. That matches Apple's stated design intent for the unified logging system.

### Decision branch activated

`p95 > 500 ms or timeouts > 0` branch ([see below](#decision-branches-reference)) is now live:

- `pry_logs` MCP tool **stays** in the surface — `OSLogStore` is good for collecting the relevant-logs section at the end of a verdict (post-hoc, by then the flush has happened).
- `assert_logs`, `assert_no_errors`, `assert_logs since: <step_ref>` — **removed from the v1 spec grammar**. They would race unflushed entries and produce flakes.
- A future version can reintroduce real-time log assertions behind a `PryHarness`-side log tee. [ADR-006](../../docs/architecture/decisions/ADR-006-log-observation-strategy.md) captures the design.

### Decision branches (reference)

- **PASS** → `assert_logs` / `assert_no_errors` behaviors in [docs/design/spec-format.md](../../docs/design/spec-format.md) are supported as primary capabilities.
- **p95 ∈ [200, 500] ms** → keep the capability but document the latency; `assert_logs` defaults gain a `timeout: 1s` built-in.
- **p95 > 500 ms or timeouts > 0** → log capability is marked experimental in the MCP tool reference; `pry_logs` still ships for manual inspection but `assert_logs` is removed from v1 spec grammar. **← ACTIVATED**

### Decision branches

- **PASS** → `assert_logs` / `assert_no_errors` behaviors in [docs/design/spec-format.md](../../docs/design/spec-format.md) are supported as primary capabilities.
- **p95 ∈ [200, 500] ms** → keep the capability but document the latency; `assert_logs` defaults gain a `timeout: 1s` built-in.
- **p95 > 500 ms or timeouts > 0** → log capability is marked experimental in the MCP tool reference; `pry_logs` still ships for manual inspection but `assert_logs` is removed from v1 spec grammar. [PROJECT-BIBLE §11 branch decision](../../PROJECT-BIBLE.md#branch-decisions).
