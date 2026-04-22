# ADR-004 — State introspection protocol (`PryInspectable`)

**Status:** Accepted
**Date:** 2026-04-22
**Supersedes:** —
**Superseded by:** —

## Context

Tests need to assert on app state — counts, flags, selections, loading indicators — not just pixels. The mechanism must:

- Require minimal code changes in the target app.
- Have no effect on RELEASE builds.
- Expose an explicit surface Claude Code can discover without guessing.
- Survive Swift 6 strict concurrency.

## Decision

ViewModels opt in via a single protocol:

```swift
public protocol PryInspectable: AnyObject {
    static var pryName: String { get }
    func prySnapshot() -> [String: any Sendable]
}
```

Registration is explicit:

```swift
#if DEBUG
PryRegistry.shared.register(DocumentListVM.self) { vm in
    [
        "documents.count": vm.documents.count,
        "isLoading": vm.isLoading,
    ]
}
#endif
```

Test specs address fields by **string key** from `prySnapshot()`:

```yaml
assert_state:
  viewmodel: DocumentListVM
  path: documents.count
  equals: 1
```

## Rationale

- **Explicit surface over reflection magic.** A reader — human or LLM — can know exactly what is queryable by reading `prySnapshot()`. No keypath spelunking, no private-field surprises.
- **`Sendable` values across the socket.** JSON-RPC is the wire protocol; `prySnapshot()` values must be JSON-representable. Typing them as `any Sendable` keeps Swift 6 happy while leaving room for nested dictionaries.
- **`#if DEBUG` gates the entire surface.** PryHarness has zero effect in RELEASE ([PROJECT-BIBLE §13](../../../PROJECT-BIBLE.md#13-non-negotiables), Invariant 1).
- **No per-view accessibility identifiers required.** Persona C (external developers) must not need to annotate every view. State-level introspection is the escape hatch for when AX label/role resolution is not enough.

## Alternatives considered

- **Full `Mirror` reflection, unopt-in.** Rejected: noisy, exposes private state, no stable surface, breaks under property wrappers.
- **Codable-based `@Published` scraping.** Rejected: fragile against non-Codable state; requires every VM to be `Codable`.
- **Macro-generated snapshot.** Rejected: adds compile-time dep and proc-macro churn. Revisit if registration boilerplate becomes a pain.

## Consequences

- The target app must write a small registration block per ViewModel it wants exposed. This is acceptable — opt-in is a feature.
- If a ViewModel's state structure changes, the registration block needs updating. The verdict's "Registered state at failure" section will show the actual keys present, making mismatches self-diagnosing.
- Nested structures need flattening into string keys (e.g. `"selection.id"`) rather than deep JSON. This is deliberate: explicit, greppable, survives refactors.
