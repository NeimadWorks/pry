# CLAUDE.md — Pry session state

> Live handover file for AI coding sessions. This is NOT architecture — architecture lives in [PROJECT-BIBLE.md](PROJECT-BIBLE.md). This file records where the last session stopped and what the next one should do.

---

## How to use this file

**If you are a new Claude Code session picking up this repo:**

1. Read [README.md](README.md) — 2 min, understand what Pry is.
2. Read [PROJECT-BIBLE.md](PROJECT-BIBLE.md) — 10 min, the source of truth. Do NOT re-litigate anything locked there.
3. Read the latest `## Session ...` block at the bottom of this file — that's where you pick up.
4. Check `spikes/` for PASS/FAIL results before writing any code that assumes them.
5. Start work. At the end of your session, append a new `## Session YYYY-MM-DD — Delta` block following the template below.

**If you are resuming your own session:** scan the "Current state" section below first. Relative dates in prompts should be resolved to absolute dates when you write them into this file (e.g. "Thursday" → `2026-04-23`).

---

## Current state

**Phase:** Phase 1 — skeleton. PryHarness side **complete and live**. pry-mcp side is a stub.

**State:**
- Root `Package.swift` declares `PryHarness`, `PryWire`, `pry-mcp`.
- `PryWire` — full wire contract: JSON-RPC envelope, `AnyCodable`, all 6 methods' param/result types, error codes.
- `PryHarness` — `PryInspectable` protocol, `PryRegistry` (lifted from DemoApp), `PryHarness.start()`, `PrySocketServer` with length-prefixed JSON-RPC framing, `hello` and `read_state` handlers wired. `inspect_tree` / `read_logs` / `snapshot` return methodNotFound until implemented.
- `pry-mcp` — version stub only. No MCP server, no AppDriver, no event injection, no spec runner.
- `Fixtures/DemoApp` — migrated off the local prototype; depends on `PryHarness` via `.package(path: "../..")`.
- **End-to-end smoke test verified**: external client opens the Unix socket, calls `hello` + `read_state` (full snapshot, path-scoped, unknown VM, unknown path), gets correctly-shaped responses with diagnostic `data` payloads.
- **Tests**: 11/11 passing (PryWire roundtrips, PryRegistry lifecycle).

**Next single action:** build the pry-mcp side of the socket — a `HarnessClient` that wraps the Unix socket with PryWire Codables and exposes async methods (`hello()`, `readState(viewmodel:path:)`, etc.). After that, `AppDriver` (NSWorkspace launch + wait for socket) and a first MCP tool `pry_state` so Claude Code can call through the full chain.

---

## Don't do list (session hygiene)

- **Do not re-open locked decisions.** §13 non-negotiables and §15 non-goals in PROJECT-BIBLE are closed. If a constraint seems wrong, write an ADR proposal; don't just edit code around it.
- **Do not add dependencies.** Zero-dep is enforced ([PROJECT-BIBLE §5](PROJECT-BIBLE.md#5-tech-stack)). If you reach for a package, stop and write the ~200 lines yourself or flag it.
- **Do not implement features beyond the current phase's scope.** Spike phase = prove assumptions, nothing else.
- **Do not write a spec parser before spikes return.** Grammar may shift based on spike 3's result.
- **Do not touch `PROJECT-BIBLE.md` §1-§10, §12-§17 without an explicit delta request.** §11 (spike results) is the one block you will edit as spikes complete.

---

## Where to write things

| Kind of change | Goes in |
|---|---|
| Architectural decision | New ADR in `docs/architecture/decisions/ADR-NNN-...md` |
| Spike result | `spikes/NN-name/README.md` + update PROJECT-BIBLE §11 checkbox |
| Spec format change | `docs/design/spec-format.md` (and bump `pry_spec_version`) |
| MCP tool surface change | `docs/api/pry-mcp-tools.md` |
| New public API in PryHarness | `docs/api/PryHarness.md` |
| Session end-state | New `## Session` block at the bottom of this file |

---

## Session delta template

Append one block per session. Keep each to ~15 lines. Don't rewrite previous sessions — superseded facts go in the new block with a pointer.

```markdown
## Session YYYY-MM-DD — <short title>

**Worked on:** <one line>
**Landed:** <files/commits>
**Decisions:** <links to any new ADRs; inline micro-decisions with rationale>
**Spike updates:** <which spike advanced, PASS/FAIL if concluded>
**Open questions discovered:** <new entries for PROJECT-BIBLE §16 if any>
**Blocked on:** <external dep, user input, other spike>
**Next single action:** <literal next thing to do, no more than one sentence>
```

---

## Session log

## Session 2026-04-22 — Project bible + repo docs

**Worked on:** Authored `PROJECT-BIBLE.md` from the initial spec dump. Scaffolded the public documentation tree (README, ADRs, design notes, API refs, contributor guide).
**Landed:** `PROJECT-BIBLE.md`, `README.md`, `CLAUDE.md`, `docs/architecture/overview.md`, `docs/architecture/decisions/ADR-001..005`, `docs/design/{principles,spec-format,verdict-format}.md`, `docs/api/{pry-mcp-tools,PryHarness,PryWire}.md`, `docs/guides/writing-specs.md`, `CONTRIBUTING.md`, `LICENSE`.
**Decisions:** Split architecture rationale from spec by promoting the five locked decisions into ADRs. README is persona-C-facing (external dev); PROJECT-BIBLE is persona-A/B-facing.
**Spike updates:** None. All five still `[ ] PASS [ ] FAIL`.
**Open questions discovered:** None beyond PROJECT-BIBLE §16.
**Blocked on:** Nothing — spike work can now begin.
**Next single action:** Create `Fixtures/DemoApp` (minimal SwiftUI app: one Button, one TextField, one VM) to serve as the spike harness, then implement Spike 2 (synthetic CGEvent acceptance).

## Session 2026-04-22 — Phase 0 kickoff

**Worked on:** Scaffolded `Fixtures/DemoApp` (SwiftPM executable, SwiftUI, zero deps) and `spikes/02-cgevent-acceptance` (driver that launches DemoApp, resolves button via AX, injects CGEvent click, checks marker file).
**Landed:** `Fixtures/DemoApp/{Package.swift, Sources/DemoApp/DemoApp.swift}`, `spikes/02-cgevent-acceptance/{Package.swift, Sources/Spike02/main.swift, README.md}`. Both `swift build` green.
**Decisions:** Inter-process signal from DemoApp to spike runner via a marker file path passed through `PRY_MARKER_FILE` env var — simpler and more reliable than stdout parsing. DemoApp uses `accessibilityIdentifier("new_doc_button")` so Spike 2 and Spike 3 (AXIdentifier propagation) share the same fixture.
**Spike updates:** Spike 2 ready to run; no PASS/FAIL yet. Still `[ ] PASS [ ] FAIL` in PROJECT-BIBLE §11.
**Open questions discovered:** None new. Noted in Spike 2 README that an AX-identifier-not-found failure is really data for Spike 3, not a Spike 2 fail.
**Blocked on:** Accessibility permission on the shell/IDE that runs the spike. One-time user grant.
**Next single action:** `swift run spike02 ../../Fixtures/DemoApp/.build/debug/DemoApp` from `spikes/02-cgevent-acceptance/` after Accessibility is granted; record evidence in the spike README; update §11 checkbox.

## Session 2026-04-22 — Spike 2 PASS

**Worked on:** Ran Spike 2 successfully after granting Terminal AX permission. Fixed `Process.executableURL` relative-path bug (resolves against CWD, not repo root) — now requires absolute path and validates executable exists up-front.
**Landed:** Evidence captured in `spikes/02-cgevent-acceptance/README.md`, PROJECT-BIBLE §11 checkbox flipped for Spike 2. Minor doc update to spike invocation example.
**Decisions:** ADR-005 stands — `CGEventPost(.cgSessionEventTap)` at AX-resolved coordinates is the canonical event-injection path. No new ADR needed.
**Spike updates:**
  - Spike 2 — PASS (macOS 26.4.1, Swift 6.3.1, 1/1 run, 30 ms gap sufficient, no synthetic-event filtering).
  - Spike 1 — partial-positive signal (Button frame landed accurately). Formal verdict still pending dedicated run across view types.
  - Spike 3 — partial-positive signal (`accessibilityIdentifier` propagated as `AXIdentifier` on a Button). Formal verdict pending.
**Open questions discovered:** Validated only on macOS 26.4.1; PROJECT-BIBLE §11 phrases the question as "14 and 15." Noted in spike README as a caveat — will re-run only if a user reports regression on an older OS.
**Blocked on:** Nothing.
**Next single action:** write Spike 3 driver that extends DemoApp or reuses it, enumerating `AXIdentifier` across Button, TextField, List, and StaticText — record which view types propagate. Spike 1 (frame accuracy) can reuse the same enumeration pass.

## Session 2026-04-22 — Spikes 1 + 3 PASS

**Worked on:** Extended DemoApp with Toggle and custom `.onTapGesture` Rectangle. Built combined `spike01` driver that enumerates AX tree, verifies AXIdentifier presence + frame sanity + click-to-marker for 6 SwiftUI view types. Fixed one `String(format:"%s", ...)` crash — Swift `String(format:)` does not accept Swift strings via `%s`; replaced with manual padding helper.
**Landed:** `Fixtures/DemoApp/Sources/DemoApp/DemoApp.swift` (Toggle + tap zone), `spikes/01-ax-frames/{Package.swift, Sources, README.md}`, `spikes/03-ax-identifier/README.md` (pointer), evidence captured, PROJECT-BIBLE §11 checkboxes flipped for Spikes 1 and 3, ADR-005 status updated (no longer "pending Spike 2").
**Decisions:** Combined Spike 1 + Spike 3 into one driver in `01-ax-frames/`, with `03-ax-identifier/` reduced to a formal pointer. Justified by shared fixture + shared AX walk.
**Spike updates:**
  - Spike 1 — PASS. AX frames accurate for Button/Toggle/Text/TextField/List/custom onTap.
  - Spike 3 — PASS. `.accessibilityIdentifier` propagates to `AXIdentifier` for all 6 types.
  - Noted: `List` on macOS 26 surfaces as `AXOutline` (not `AXList`) — future spec-format doc will warn about this when role-constraint predicates are added.
  - Noted: custom tap views need `.accessibilityAddTraits(.isButton)` + `.contentShape(Rectangle())` to surface as `AXButton` rather than `AXGroup` — worth including in the external-dev quickstart.
**Open questions discovered:** None new; role-map quirks captured as docs-todo, not blockers.
**Blocked on:** Nothing.
**Next single action:** write Spike 5 — `PryRegistry` prototype that registers a `DocumentListVM` instance and reads its snapshot from the socket server. Verify no `Sendable` warnings under Swift 6 strict concurrency. Can live at `spikes/05-mirror-introspection/`, using DemoApp's existing VM.

## Session 2026-04-22 — Spikes 4 & 5; Phase 0 closed

**Worked on:** Extended DemoApp with `PryInspectable` prototype, `PryRegistry`, and an OSLogStore latency harness. Wrote and ran Spike 5 (PASS) and Spike 4 (FAIL after fixing a measurement bug in the first run).
**Landed:** Spike 5 evidence, Spike 4 evidence (with run history noting the discarded first measurement), ADR-006 (log observation strategy), removal of `assert_logs` / `assert_no_errors` from `docs/design/spec-format.md`, best-effort latency note on `pry_logs` in `docs/api/pry-mcp-tools.md`, new Q5 in PROJECT-BIBLE §16.
**Decisions:**
  - ADR-004 stands — `PryInspectable` + `[String: any Sendable]` compiles and round-trips correctly under Swift 6 strict concurrency.
  - ADR-006 new — `OSLogStore` is not a real-time channel. Pry v1 uses it best-effort for post-hoc verdict attachments only. Assertion-grade log checks wait for a Tier 2 `PryLog` tee (not v1).
**Spike updates:**
  - Spike 5 — PASS. Runtime values from a `@MainActor ObservableObject` match exactly after a mutation; no Sendable warnings during compilation.
  - Spike 4 — FAIL. First run had a measurement bug (`position(date:)` inside the timing window); second run with instrumented breakdown confirmed the 1.2 s floor is inside `getEntries()` itself, not in the bookkeeping. Product decision unchanged regardless of H1-vs-H2 root cause.
**Open questions discovered:** Q5 in §16 — when to build the Tier 2 log tee.
**Blocked on:** Nothing. Phase 0 is done.
**Next single action:** begin Phase 1 skeleton. Create root `Package.swift` with three products and stub the module map from `docs/architecture/overview.md`. Lift `PryInspectable` / `PryRegistry` from DemoApp into the `PryHarness` target.

## Session 2026-04-23 — Phase 1 skeleton, harness side live

**Worked on:** Set up the SwiftPM workspace and implemented the full PryHarness in-process side. Wrote the wire contract, the socket server with length-prefixed JSON-RPC framing, the registry, and smoke-tested everything end-to-end against DemoApp.
**Landed:**
  - `Package.swift` (root, 3 products + 2 test targets)
  - `Sources/PryWire/Messages.swift` — complete Codable contract for hello/read_state/inspect_tree/read_logs/snapshot/goodbye, `AnyCodable`, error codes
  - `Sources/PryHarness/{PryInspectable,PryRegistry,PryHarness,PrySocketServer}.swift`
  - `Sources/pry-mcp/main.swift` — version-stub placeholder only
  - `Tests/{PryWireTests,PryHarnessTests}/*.swift` — 11 passing tests
  - `Fixtures/DemoApp/Package.swift` now depends on the root package via path
  - DemoApp strips local PryInspectable prototype, imports PryHarness, calls `PryHarness.start(bundleID:)` from AppDelegate
**Decisions:**
  - `DispatchQueue.main.sync { MainActor.assumeIsolated { PryRegistry.shared.snapshot(...) } }` is the pattern for cross-thread reads of main-actor state. Validated end-to-end; no Sendable complaints under Swift 6 strict concurrency.
  - Error responses carry a `data` payload with diagnostic hints (`registered: [...]`, `available_paths: [...]`). This directly supports Invariant 4 (no `failed` without context) and shapes the verdict's diagnostic sections later.
  - Kept the `pry_registered` SpikeMarker emission in DemoApp's `.task` so spike05 remains reproducible; registry code itself is clean.
**Tests / smoke:**
  - `swift test` — 11/11 pass.
  - Live socket against DemoApp: hello + read_state (full + path + unknown VM + unknown path + unimplemented method) — all shapes correct.
**Open questions discovered:** none new.
**Blocked on:** nothing.
**Next single action:** implement `pry-mcp/Driver/HarnessClient.swift` — an async wrapper around a connecting `AF_UNIX` socket using PryWire Codables (`func hello() async throws -> HelloResult`, etc.). Then `AppDriver` (NSWorkspace launch + socket-appears wait), then a first MCP tool `pry_state` routed through a minimal stdio JSON-RPC server. That closes the loop: Claude Code → stdio MCP → pry-mcp → AF_UNIX socket → PryHarness → VM snapshot.
