# Spike 05 — Mirror + `PryInspectable` under Swift 6 strict concurrency

## Binary question

Does the `PryInspectable` pattern correctly expose `@Published` values from a `@MainActor ObservableObject` via `prySnapshot()`? Any Sendable gotchas under Swift 6 strict concurrency?

## Why it matters

[ADR-004](../../docs/architecture/decisions/ADR-004-state-introspection-protocol.md) commits to an explicit opt-in protocol returning `[String: any Sendable]`. If Swift 6 rejects the shape, or if runtime values disagree with main-actor state, the whole state-introspection design needs to change. The fallback would be PryHarness-side coordinate registry or macro-based snapshot generation — both much heavier.

## Method

Two validation stages:

1. **Compile-time** — build `Fixtures/DemoApp` with `StrictConcurrency` upcoming feature enabled. DemoApp contains a prototype `PryInspectable` protocol (`@MainActor`-constrained, class-bound), a `PryRegistry` actor-like holder, and a real `@MainActor ObservableObject` (`DocumentListVM`) conforming to it. **If this compiles warning-free, half the PASS condition is met.** No Sendable violations means the shape works.

2. **Runtime** — launch DemoApp, verify:
   - At startup, `PryRegistry.shared.register(vm)` fires and writes a `pry_registered` marker event listing the snapshot keys. This proves the generic constraint and the `[weak instance]` closure compile and execute.
   - After clicking `new_doc_button` (which mutates main-actor state: `documents`, `clickCount`), the VM's `createDocument` writes a `state_snapshot` marker event carrying the JSON-ified snapshot. Runner parses it and checks expected values: `documents.count == 1`, `clickCount == 1`, `zoneTapCount == 0`, `verbose == false`, `draftName == ""`.

PASS if both stages clear with no Sendable warnings and all expected values match.

## Prerequisites

- macOS 14+.
- Accessibility permission on the parent process (same as spike 2, used to click the button).

## How to run

```sh
cd Fixtures/DemoApp && swift build && cd -
cd spikes/05-mirror-introspection
DEMO=$(cd ../../Fixtures/DemoApp && pwd)/.build/debug/DemoApp
swift run spike05 "$DEMO"
echo "exit: $?"
```

Exit `0` = PASS, `1` = FAIL, `2` = bad invocation.

## Verdict

```
[x] PASS
[ ] FAIL
```

Date: 2026-04-22. Reflected in [PROJECT-BIBLE §11](../../PROJECT-BIBLE.md#11-validated-assumptions).

### Evidence

```
macOS version:    26.4.1 (build 25E253)
Swift version:    6.3.1 (swiftlang-6.3.1.1.2)
Compile warnings: none related to Sendable or strict concurrency
Run count:        1/1 PASS
```

Registered keys (at startup, from `pry_registered` marker):

```json
{"keys":["clickCount","documents.count","draftName","verbose","zoneTapCount"],"viewmodel":"DocumentListVM"}
```

Observed snapshot (after `click → createDocument`):

```json
{
  "viewmodel": "DocumentListVM",
  "keys": {
    "clickCount": 1,
    "documents.count": 1,
    "draftName": "",
    "verbose": false,
    "zoneTapCount": 0
  }
}
```

All five expected values matched exactly. MainActor mutation propagated through `prySnapshot()` with no race or ordering issue.

### Observations worth keeping

- `@MainActor protocol PryInspectable` with `func prySnapshot() -> [String: any Sendable]` compiles clean under Swift 6 strict concurrency.
- `PryRegistry.register<T: PryInspectable>(_ instance: T)` with a `[weak instance]` closure capture works as expected — the generic constraint, weak reference, and `@MainActor` isolation compose correctly.
- `[String: any Sendable]` is comfortably convertible to JSON via a minimal type-switch (Int / Bool / String / Double passthrough, everything else stringified). That small coercion helper is part of what moves from DemoApp into the `PryHarness` package in Phase 1.

### Decision implied

[ADR-004](../../docs/architecture/decisions/ADR-004-state-introspection-protocol.md) stands. Phase 1 lifts the prototype out of DemoApp into the `PryHarness` Swift package unchanged.

### Decision branches

- **PASS** → [ADR-004](../../docs/architecture/decisions/ADR-004-state-introspection-protocol.md) stands. The PryHarness implementation in Phase 1 moves the prototype from DemoApp into the `PryHarness` package as-is.
- **FAIL on compile** → the `[String: any Sendable]` shape doesn't survive strict concurrency; an ADR supersedes ADR-004 moving to `@Sendable` closure-returning or NSCoding-like alternatives.
- **FAIL on runtime** (registered but snapshot values wrong or missing) → ADR-004 still stands but the snapshot call site may need main-actor hopping — document in PryHarness API.
