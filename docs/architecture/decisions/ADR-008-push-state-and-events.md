# ADR-008 — Push state notifications & async event handlers

**Status:** Accepted
**Date:** 2026-04-27

## Context

`assert_state` and `wait_for` poll over the socket. That's fine for stable
states but expensive for transient ones (toasts, sheets that auto-dismiss,
flicker assertions). The grammar is also strictly sequential — there's no way
to say "if a 'Replace?' sheet appears at any point during this flow, click
'Skip'".

## Decision

Two complementary additions:

### 1. Push notifications on the wire

The Unix socket gains a notification frame (JSON-RPC notification, no `id`).
Clients can subscribe to:

- `state_changed` — fires when any `prySnapshot()` value changes for a
  registered VM. Payload includes vm name, key, old & new values.
- `window_appeared` / `window_disappeared` — AX window lifecycle.
- `sheet_appeared` — child sheet on any window.

The harness fires these from the main actor at a debounced cadence
(coalescing within 50ms windows) so a flurry of `@Published` updates doesn't
flood the socket.

### 2. Async event handlers in spec grammar

Spec frontmatter (or a top-level `handlers:` block) declares parallel
handlers that fire whenever their predicate matches:

```pry
handlers:
  - when: { sheet_appeared: { title_matches: "Replace.*" } }
    do: { click: { label: "Skip" } }
```

Handlers run independently of the main step list. They consume events as
they arrive. Each handler can be `:once` (fires once then unbinds) or
`:always` (fires every time the predicate matches).

## Rationale

- Push notifications eliminate the polling overhead and tighten flicker
  assertions to a few ms instead of `wait_for` granularity (~80ms).
- Async handlers turn "spec is a script that may be interrupted by sheets"
  from a footgun into a first-class pattern.

## Alternatives considered

- Polling at faster cadence — would add load and miss transient events.
- Long-poll on a single endpoint — more complex to multiplex; less flexible.
- File-based event log — slower, worse failure modes.

## Consequences

- Wire protocol gains non-id'd notification frames. Clients that don't
  subscribe ignore them.
- The harness needs a publisher mechanism. We hook into Combine via VM
  conformance: `PryInspectable` gains an optional
  `prySubscribeStateChanges(_:) -> AnyCancellable` that the harness calls
  if implemented.
- Specs gain a top-level `handlers:` section.
