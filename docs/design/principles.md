# Design principles

These are the rules the product bends to. When a proposed feature conflicts with one, the feature loses.

## 1. One tool call in, one verdict out

The 95% path for Claude Code is: write a Markdown spec, call `pry_run_spec`, read the verdict. Every other tool (`pry_click`, `pry_find`, `pry_state`, ...) exists for exceptional debugging, not routine flow. If a design makes the primary path require multiple tool calls to chain state, it's wrong.

## 2. No pixels in the default path

Screenshots are debug aids, attached to verdicts on failure. They are never the basis of an assertion. The verdict answers "what happened" with structured text (AX tree, ViewModel state, logs) — not a PNG for the LLM to interpret.

## 3. Declarative over procedural

Specs describe intent (`click: { label: "Save" }`), not operations (`move_mouse(x, y); mouse_down; mouse_up`). The runner compiles intent into operations. A UI rearrangement that preserves semantics must not break the test.

## 4. Zero effect on RELEASE

PryHarness is linked under `#if DEBUG`. Its public API is `#if DEBUG`-gated. A RELEASE build of the host app is byte-identical with or without the PryHarness dependency declared. No exceptions, no compile-time telemetry, no `#if PRY_ENABLED`.

## 5. Passive harness, active runner

PryHarness answers queries. `pry-mcp` drives. If a feature asks PryHarness to click a button or run a test step, redesign it. The split exists so event injection goes through the real system path ([ADR-005](../architecture/decisions/ADR-005-event-injection-strategy.md)).

## 6. Every failure is diagnosable

A failing verdict always contains: which step, expected, observed, AX tree snippet, registered state, recent logs. A verdict that says "failed" with no context is a bug in Pry, not a flaky test.

## 7. Zero dependencies

Foundation and system frameworks only. No SwiftPM dependencies across any target. If a library seems essential, write the equivalent ~200 lines or drop the feature. [Locked in PROJECT-BIBLE §5](../../PROJECT-BIBLE.md#5-tech-stack).

## 8. No flakiness tolerance

A passing test must pass for a reason the verdict can explain. A failing test must fail for the reason the verdict states. Timing issues are Pry bugs — we fix them by making waits explicit (`wait_for`), not by adding `sleep`s to specs.

## 9. Local-only by construction

`AF_UNIX` socket. Stdio MCP. No TCP. No HTTP. No cloud. The absence of network code is not a policy — it is the architecture ([ADR-002](../architecture/decisions/ADR-002-two-process-split.md)).

## 10. Explicit surface over reflection magic

The `PryInspectable` protocol forces ViewModels to declare what they expose. We do not auto-reflect into `@Published` properties, private fields, or storage-by-convention. A reader knows exactly what is queryable. ([ADR-004](../architecture/decisions/ADR-004-state-introspection-protocol.md))

## 11. Specs are versioned

Breaking changes to the spec grammar bump `pry_spec_version`. Old specs do not silently change behavior. Migration notes live under `docs/design/spec-format.md`.

## 12. The README is for persona C

The repo's front door addresses an external Swift developer — not Dom, not Claude Code. If an outsider can install Pry in under 5 minutes and test their own app, we've won. If they need to read PROJECT-BIBLE to get started, we've lost.
