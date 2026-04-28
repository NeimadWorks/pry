# CLAUDE.md — Pry session state

> Live handover file for AI coding sessions. This is NOT architecture — architecture lives in [PROJECT-BIBLE.md](PROJECT-BIBLE.md). This file records where the last session stopped and what the next one should do.

**Coding-agent quickstart:** start with [`docs/AGENTS.md`](docs/AGENTS.md). It indexes the entire doc tree by intent (writing specs, calling Pry from Swift, extending the runner) and contains a one-page cheat sheet for the grammar and the public API.

**For "what's next":** [`docs/ROADMAP.md`](docs/ROADMAP.md) is the source of truth — what's shipped, what's in flight, what's deferred (with rationale), what's been ruled out.

---

## How to use this file

**If you are a new Claude Code session picking up this repo:**

1. Read [`docs/AGENTS.md`](docs/AGENTS.md) — 5 min, navigation + cheat sheet.
2. Read [`README.md`](README.md) — 2 min, understand what Pry is.
3. Read [`PROJECT-BIBLE.md`](PROJECT-BIBLE.md) — 10 min, the source of truth. Do NOT re-litigate anything locked there.
4. Read the latest `## Session ...` block at the bottom of this file — that's where you pick up.
5. Check `spikes/` for PASS/FAIL results before writing any code that assumes them.
6. Start work. At the end of your session, append a new `## Session YYYY-MM-DD — Delta` block following the template below.

**If you are resuming your own session:** scan the "Current state" section below first. Relative dates in prompts should be resolved to absolute dates when you write them into this file (e.g. "Thursday" → `2026-04-23`).

---

## Current state

**Phase:** Original Phases 0-5 plus four "modern UX" waves **all delivered**. Wave 1 (PryClock virtual time + push state + animations + sheet helpers — ADRs 007/008/009), Wave 2 (variables, includes, setup/teardown, conditionals, loops, sub-flows — ADR-010 grammar piece), Wave 3 (modifier-clicks, marquee, magnify, type-with-delay, key-repeat, longpress, menu paths, pasteboard, multi-window/multi-app surface, async event handlers), Wave 4 (filesystem & defaults fixtures, parallel suite, retry, JUnit/TAP/markdown exporters, watch mode, image diff, accessibility audit — ADRs 010/011). 8 specs in `Fixtures/DemoApp/flows/` cover the new ground with PASS verdicts and the package builds clean across `PryHarness`, `PryWire`, `PryRunner` (public library), and `pry-mcp` (thin wrapper).

**What works today:**
- Spec runner: `pry-mcp run --spec flows/new-document.md` → verdict with full diagnostic context (AX tree snippet, registered VM state, auto-PNG on failure, step-by-step timings).
- `pry-mcp run-suite --dir flows [--tag smoke]` → aggregate across all `.md` specs under a dir.
- 25+ MCP tools — full reference in [`docs/api/pry-mcp-tools.md`](docs/api/pry-mcp-tools.md). Lifecycle, mouse/keyboard/gestures, observation, time control, pasteboard, animations, file panels, spec runner.
- CLI mirrors every tool one-to-one for hand-driven testing.
- DemoApp suite: 5 specs (`new-document`, `text-field`, `toggle`, `slider-drag`, `expect-change`) all passing in ~4.3s combined.
- CI workflow (`.github/workflows/ci.yml`), Homebrew formula template (`HomebrewFormula/pry-mcp.rb`), signing/notarization release script (`scripts/release.sh`).
- `pry_spec_version: 1` frozen.

**What remains (explicit hand-offs for the human operator):**
- **Phase 4 publication**: tag a release, run `./scripts/release.sh vX.Y.Z` with a Developer ID cert + notarization credentials, upload the archive to a GitHub release, create a `neimad/tap` repo, drop `HomebrewFormula/pry-mcp.rb` in it with updated `url` + `sha256`. None of this is code-writable by me — it needs Apple credentials and external repos.
- **Phase 5 dogfooding**: adopt Pry in Proof, Probe, Narrow, Harald. Each requires adding the `PryHarness` SwiftPM dep under `#if DEBUG`, registering their ViewModels, and writing `flows/` per app. Requires those codebases.
- **Flakiness audit** (Phase 5 principle 8): once real apps use Pry, any flaky spec is a Pry bug — track them in issues tagged `flakiness`. No flakes observed so far on DemoApp fixtures.

**State — pry-mcp side:**
- `Driver/HarnessClient.swift` — actor-isolated AF_UNIX socket client with PryWire Codables, serialized JSON-RPC ID matching.
- `Driver/AppDriver.swift` — launch-by-path (SwiftPM fixtures) + launch-by-bundle-ID (NSWorkspace) + attach + terminate. `waitForSocket` polls the socket file path.
- `Control/ElementResolver.swift` — resolves `Target` (id / role+label / label / label_matches / tree_path / point) to a single AXUIElement. Ambiguity is an error (never silent-picks).
- `Control/EventInjector.swift` — click / double_click / right_click / hover / type (unicode string API) / key (combo parsing + virtual key codes).
- `MCP/MCPServer.swift` — minimal stdio JSON-RPC 2.0 server handling `initialize`, `notifications/initialized`, `tools/list`, `tools/call`.
- `MCP/Tools.swift` — six tools implemented: `pry_launch`, `pry_terminate`, `pry_state`, `pry_click`, `pry_type`, `pry_key`. Each returns a structured Codable result; errors carry stable `kind` strings + optional `fix` hints.
- `CLI.swift` + rewritten `main.swift` — dual-mode binary: no args → stdio MCP; args → CLI subcommands mirroring the tools one-to-one.

**Validated:**
- `swift test` — 11/11 still passing.
- CLI end-to-end on DemoApp: launch → state (full + path) → click new_doc_button 3× → state shows count=3 → errors structured with kind. Clean shutdown via terminate.
- Stdio MCP end-to-end: Python driver sends initialize/tools/list/tools/call over stdin/stdout; all 6 tools respond; `isError: true` envelope for VM-not-registered error case.

**Known gaps (all intentional; roadmap's Phase 2 and beyond):**
- `pry_tree`, `pry_find`, `pry_wait_for`, `pry_assert`, `pry_expect_change`, `pry_logs`, `pry_snapshot`, `pry_run_spec`, `pry_run_suite`, `pry_list_specs` — not implemented yet.
- `inspect_tree`, `read_logs`, `snapshot` harness-side handlers still return methodNotFound — to be added alongside the MCP tools that need them.
- `tree_path` target form parses but never matches (never walked).

**Next single action:** begin Phase 2 — the spec runner. Write `Spec/SpecParser.swift` (Markdown + frontmatter → step tree), `Spec/SpecRunner.swift` (executes steps, collects a verdict), `Verdict/VerdictReporter.swift` (writes the Markdown verdict per `docs/design/verdict-format.md`), then expose `pry_run_spec` as the seventh MCP tool. After that, build the first real spec (`Fixtures/flows/new-document.md`) and run it end-to-end against DemoApp.

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

## Session 2026-04-24 — Phase 1 complete

**Worked on:** Built the entire pry-mcp side of Phase 1 and closed the Claude Code → stdio MCP → pry-mcp → socket → PryHarness → VM round-trip.
**Landed:**
  - `Sources/pry-mcp/Driver/{HarnessClient,AppDriver}.swift`
  - `Sources/pry-mcp/Control/{ElementResolver,EventInjector}.swift`
  - `Sources/pry-mcp/MCP/{MCPServer,Tools}.swift`
  - `Sources/pry-mcp/CLI.swift`
  - `Sources/pry-mcp/main.swift` rewritten as dual-mode (stdio MCP by default; CLI when subcommand given)
  - `Package.swift` updated: `pry-mcp` depends on both `PryWire` and `PryHarness` (to reuse `PryHarness.socketPath(for:)`)
**Decisions:**
  - `HarnessClient` as `actor` — serializes request/response so JSON-RPC `id` matching stays correct without explicit locking.
  - `PryTools.launch` uses a handshake-with-retry loop because `waitForSocket` returns after `bind()` but connect can race the `listen()` that follows. 2 s budget, 50 ms backoff — invisible in the happy path.
  - Errors from harness / resolver are translated at the MCP boundary into a closed set of `kind` strings (matches `docs/api/pry-mcp-tools.md` error contract). No raw RPC codes leak out.
  - `ToolCatalog.all` as computed property (not `static let`) to satisfy Swift 6 strict concurrency on `[String: Any]`. Minor cost, clean solution.
  - AX target resolution ports the precedence rule literally: `id > role+label > label > label_matches > tree_path > point`. Ambiguity raises `resolution_ambiguous` with candidate descriptors — matches verdict-quality diagnostic promise.
  - `tree_path` form parses but is a no-op match for now; documented gap.
**Tests / smoke:**
  - `swift test` — 11/11 passing, no new tests added yet (target for next pass: golden wire-protocol tests for the MCP server).
  - CLI end-to-end on DemoApp: launch → state(full/path) → click 3× → state shows count=3 → unknown-VM error / unknown-path error → terminate. All shapes correct.
  - Stdio MCP end-to-end via Python driver: initialize, tools/list (6 tools), tools/call for pry_state + pry_click + follow-up pry_state (proves mutation round-trip); unknown-VM call returns MCP `isError: true` envelope with structured `kind`+`message`+optional `fix`.
**Open questions discovered:** none new; §16 still stands.
**Blocked on:** nothing.
**Next single action:** begin Phase 2 — the spec runner. Write `Sources/pry-mcp/Spec/{SpecParser,SpecRunner}.swift` + `Sources/pry-mcp/Verdict/VerdictReporter.swift` per `docs/design/verdict-format.md`, then expose `pry_run_spec` as the seventh MCP tool. First real spec to target: `Fixtures/flows/new-document.md` driving DemoApp.

## Session 2026-04-24 — Phases 2-5 shipped

**Worked on:** Phases 2 (spec runner), 3 (observability completeness), 4 (distribution plumbing), 5 (grammar freeze + doc polish). The only remaining items are signed-binary publication and Phase 5 dogfooding across non-repo apps — hand-offs documented above.

**Landed (Phase 2):**
- `Sources/pry-mcp/Spec/YAMLFlow.swift` — minimal YAML-flow parser (tokenizer + recursive descent) for `{ key: value }`, arrays, durations, etc.
- `Sources/pry-mcp/Spec/{Step,Spec,SpecParser,SpecRunner}.swift` — Step AST, Spec value type, Markdown+frontmatter+fenced-block parser, actor-based runner with full step execution.
- `Sources/pry-mcp/Verdict/{Verdict,VerdictReporter}.swift` — Verdict shape + renderer producing the Markdown format documented in `docs/design/verdict-format.md` (pass/fail/errored shapes; auto-PNG on failure; AX snippet + registered state in failure context).
- `Sources/pry-mcp/Control/AXTreeWalker.swift` — out-of-process tree enumeration + YAML render + truncation for failure snippets.
- `Sources/pry-mcp/Control/WindowCapture.swift` — `CGWindowListCreateImage`-based snapshots (deprecated warning noted; ScreenCaptureKit is future work per Phase 5).
- New MCP tool `pry_run_spec` + CLI `run` subcommand.

**Landed (Phase 3):**
- `Sources/PryHarness/{PryLogTap,PryInspector}.swift`, `read_logs` wired in `PrySocketServer`.
- MCP tools: `pry_tree`, `pry_find`, `pry_snapshot`, `pry_logs`, `pry_run_suite`, `pry_list_specs` + CLI subcommands for each.
- Multi-window scoping (`WindowFilter` passed through tree + snapshot).
- AX permission fail-fast UX in the CLI with a concrete fix recipe.
- Cross-spec launch race fixed in `AppDriver.launchByPath` (unlink stale socket before spawning).

**Landed (Phase 4 — templates only):**
- `.github/workflows/ci.yml` — swift build + swift test on macos-14, release artifact packaging on version tags.
- `HomebrewFormula/pry-mcp.rb` — formula template for a `neimad/tap`, with post-install AX caveat.
- `scripts/release.sh` — Developer ID codesign + notarytool submission + archive + SHA256.

**Landed (Phase 5 — docs):**
- `pry_spec_version: 1` frozen in both `docs/design/spec-format.md` and PROJECT-BIBLE §14.
- README rewritten for persona C: CI badge, new quickstart with install paths (tap + from-source), `run` + `run-suite` usage, MCP server registration example, full tool list.

**Decisions during the marathon:**
- **`AppDriver.launchByPath` unlinks the stale socket before `Process.run()`.** Without this, `waitForSocket` could return on a leftover inode from the previous spec and the handshake would race the new app's `bind()`. Tri-spec suite went from 1/3 to 3/3 with this two-line fix.
- **`wait_for` state predicates need to catch `StepFailure` and rethrow as `PredicateFailure`** — without this the wait loop aborts on the first state mismatch instead of polling. Caught by the first real DemoApp run where the state mutation was still flushing from the CGEvent.
- **`OSLogStore` surfaces under `pry_logs` only** — per ADR-006, no assertion-grade log commands in v1 grammar. The best-effort latency note is in the MCP tool description.
- **`CGWindowListCreateImage` deprecation accepted** — ScreenCaptureKit would gate us on TCC Screen Recording permission with a modal prompt per app. Snapshots are debug aids; deprecated API works fine.

**Tests / smoke:**
- `swift test` — 11/11 pass.
- DemoApp suite via `pry-mcp run-suite --dir Fixtures/DemoApp/flows` — 3/3 pass, total ~2.6s.
- Individual specs: `new-document` (11 steps, 1.0s), `text-field` (9 steps, 0.8s), `toggle` (10 steps, 1.0s).
- CLI smoke: `tree`, `find`, `snapshot`, `logs`, `run`, `run-suite`, `list-specs` all functional against a live DemoApp.

**Open questions discovered:** none new; §16 Q5 (Tier 2 log tee) remains the biggest deferred piece.

**Blocked on:** nothing for code work. Phase 4 publication and Phase 5 dogfooding need human operator / external repos.

**Next single action (for the human):** tag `v0.1.0`, run `./scripts/release.sh v0.1.0` with Developer ID credentials, publish the tap, then start adopting Pry in Proof — the first real-world app. A new session can begin by reading `CLAUDE.md`, `PROJECT-BIBLE.md`, and the Phase 5 notes above.

## Session 2026-04-28 — v0.1.0 tagged + Narrow feedback iteration

**Worked on:** Three things in one session.
1. **Cut `v0.1.0`.** Cleaned the tracked tree (5093 transient files purged
   — `.build/`, `.swiftpm/`, `pry-verdicts/` were in the index from old
   auto-commits). Wrote a real Swift `.gitignore`, bumped version strings
   from `0.1.0-dev` → `0.1.0`, pushed two cleanup commits, tagged with an
   annotated note, pushed to `origin`.
2. **Addressed Narrow field feedback.** A real session driving Narrow
   (chess study, 13K-symbol explorer) surfaced 11 friction points; all
   landed in one commit:
     - Top 5 (numeric comparators, matches Int↔String coerce, key
       punctuation, `.pry/config.yaml`, SwiftUI gotchas docs)
     - Plus: `nth:` selector, `count: { gte }`, `panel:` predicate,
       auto-`.gitignore` in verdicts/, SIGINT cleanup, AX context fallback.
3. **Documentation overhaul.** New `docs/ROADMAP.md` is the single
   source-of-truth for shipped vs. next vs. backlog vs. out-of-scope.
   Updated `PryRunner.md`, `pry-mcp-tools.md`, `AGENTS.md`, README, and
   `PROJECT-BIBLE.md` to point at it.

**Landed:**
  - `Sources/PryRunner/PryConfig.swift` (new)
  - `Sources/PryRunner/Spec/{Step,SpecParser,SpecRunner}.swift` — numeric
    comparators, nth target, panel predicate, count NumOp
  - `Sources/PryRunner/Control/{ElementResolver,EventInjector}.swift` —
    `.nth` resolution + count(matching:in:), punctuation keycodes
  - `Sources/pry-mcp/{main.swift,MCP/Tools.swift}` — signal handlers,
    `nth` in TargetSpec
  - `docs/ROADMAP.md` (new)
  - Doc updates in README, AGENTS, spec-format, writing-specs,
    PryRunner.md, pry-mcp-tools.md, PROJECT-BIBLE §18 pointer

**Decisions:**
  - `.pry/config.yaml` chosen over per-spec workspace var because it's
    per-project rather than per-spec, and the lookup walks ancestor dirs
    so deeply nested fixtures work without copy-pasting the path.
  - `nth: N` as a wrapper case on `TargetRef` (`.nth(base, index)`) rather
    than a field on every TargetRef variant — keeps existing call sites
    untouched and makes the resolver path explicit.
  - `panelOpen` as a separate Predicate case rather than overloading
    `window:` — the matching semantics differ (sheets aren't windows) and
    a clean predicate produces clearer verdict text.

**Tests / smoke:**
  - `swift test` — 26/26 (3 new parser tests for the new comparators,
    nth, count-with-NumOp).
  - DemoApp suite — 9/9 PASS unchanged.

**Open questions discovered:**
  - Whether `.pry/config.yaml` should also carry `with_defaults`,
    `with_fs`, etc. defaults inheritable across specs. Punted; specs are
    self-contained today and that's a feature.

**Blocked on:** nothing.

**Next single action:** start Phase 5 dogfooding on Narrow (the field-feedback
app). The DX trail blazed by the post-v0.1 commit means the first
adoption flow should be cheap to write. After Narrow validates, pick the
next backlog item from [`docs/ROADMAP.md`](docs/ROADMAP.md) "Next" section
— likely `pry-mcp lint` or `assert.soft_state`.

## Session 2026-04-28 — v0.2 DX iteration

**Worked on:** Implemented every item from ROADMAP "Next — likely v0.2"
(spec authoring, runner/observation, verdict richness, distribution).
Plus a closure-type-inference bug from the Narrow run. All backward
compatible — `pry_spec_version: 1` still frozen.

**Landed (16 items, in roadmap rows 11–26):**

- **CLI** — `pry-mcp lint --dir <dir>` (parse-only validation, CI gate),
  `pry-mcp init --bundle-id ... --product ...` (`.pry/config.yaml`
  scaffold), `pry-mcp report --build <verdicts-dir>` (self-contained HTML
  dashboard, base64-embedded PNGs).
- **Spec language** — `assert_focus: TARGET`, `assert_eventually: PRED
  [timeout: 1s]`, `soft_assert_state: ...` (accumulates), `select_range`,
  `multi_select`, `with_retry: N + body`, `copy_to: { var, from }`
  (runtime variable capture).
- **Frontmatter knobs** — `slow_warn_ms`, `state_delta`, `ax_tree_diff`,
  `screenshots_embed`.
- **Verdict** — `axTreeDiff` + `stateDeltaTimeline` fields and renderer
  sections; embedded base64 PNGs when `screenshots_embed: true`.
- **CI** — tag-triggered release with conditional codesign+notarize when
  secrets are configured, fallback unsigned tarball, automatic Homebrew
  tap bump (gated on `HOMEBREW_TAP_TOKEN`). Lint of DemoApp specs runs
  on every PR.
- **Bug fix** — `SpecRunner.doLaunch` closure carries explicit
  `() -> String?` annotation (Narrow report).

**Decisions:**

- `with_retry: N + body` rather than per-step `@retry: N` — reuses
  existing block-with-body parsing infra and keeps the wrapping explicit.
- `soft_assert_state` as a separate command rather than a `soft:` flag
  on `assert_state` — keeps the per-command verdict label tidy
  ("⚠️ N soft failures" vs the regular "FAILED at step X").
- `assert_eventually` as an alias of `wait_for` with verdict-side
  reframing rather than a brand-new evaluation engine — same retry
  loop, different failure phrasing.
- HTML report is `--build`, not `--serve`. Self-contained file is
  better than a daemon. `--watch` lives in the v0.3 backlog.

**Tests / smoke:**
- `swift test` — 33/33 (7 new parser tests for the new step kinds /
  frontmatter fields).
- DemoApp suite — 9/9 PASS unchanged.
- `pry-mcp lint --dir Fixtures/DemoApp/flows` — `9/9 specs OK`, exit 0.
- `pry-mcp report --build pry-verdicts --out /tmp/pry-report.html` —
  generated 363 KB self-contained HTML with all verdicts inlined.

**Open questions:** None new. ROADMAP "Next — likely v0.3" carries the
follow-ups (`pry-mcp doctor`, per-step retry policy, watch-mode HTML,
fan-in suite report, multi-spec coverage).

**Blocked on:** nothing.

**Next single action:** real-world adoption on Narrow with the new toolset
(`pry-mcp init` → `.pry/config.yaml`, run-suite with `screenshots_embed:
true` for shareable verdicts, `lint` in CI). After that, tag `v0.2.0`
when the field signal validates the additions.

## Session 2026-04-29 — Canopy field-feedback wave + docs refresh

**Worked on:** Implemented 12 DX additions distilled from the Canopy
(file-manager dogfooding) bilan, then refreshed every public doc to
match. Also fixed a CI tag-trigger gap and a `swift test --parallel`
race on `PryRegistry.shared`.
**Landed:**
  - Code (commit `deebd0f`): `type_chars`, `wait_for_focus`, `dump_focus`,
    `assert_stable`, `not_equals` / `not_matches` state expectations,
    `expect_total:` companion to `nth:`, `sheet:` predicate, multi-line
    frontmatter blocks via `normalizeIndentedBlocksToInline`, `auto_build:
    true` in `.pry/config.yaml` (runs `swift build` from config dir before
    first launch), `View.pryRegister(_:)` SwiftUI sugar in `PryHarness`,
    `pry_menu_inspect` + `pry_focus` MCP tools, `pry_tree --compact` SwiftUI
    label stripper. 40 unit tests pass.
  - CI (commits `6d176c5`, `9bd7f38`): tag-push trigger added; runner pinned
    to `macos-15` + `setup-xcode latest-stable`; dropped `--parallel` from
    `swift test`.
  - Docs: `docs/ROADMAP.md` (Canopy wave table + 3 new backlog items —
    Inspector scaffolding/SwiftSyntax-ADR, multi-char type warning, verdict
    warnings layer); `docs/design/spec-format.md`; `docs/api/pry-mcp-tools.md`;
    `docs/api/PryRunner.md`; `docs/api/PryHarness.md`; `docs/AGENTS.md`;
    `docs/guides/writing-specs.md` (new "Patterns from the Canopy wave"
    section); `README.md` status line.
**Decisions:** Quote-on-conversion for YAMLFlow scalars containing
`~`, `${`, `{`, `}`, `/` rather than extending the tokenizer (would
conflict with object-delimiter `{`). Drop `--parallel` instead of
restructuring the registry singleton — suite is small, runs in <100ms.
"Ce qui manque vraiment" items from the bilan (Inspector scaffolding via
SwiftSyntax, multi-line type warning, verdict warnings layer) deferred
to backlog, not v0.2.x.
**Spike updates:** none.
**Open questions discovered:** Inspector scaffolding needs an ADR — does
Pry take a SwiftSyntax dep (breaks zero-dep) or ship a templated emitter?
**Blocked on:** nothing.
**Next single action:** continue Phase 5 dogfooding — pick up Narrow next
and exercise `wait_for_focus` / `assert_stable` / `expect_total` on its
move-input screens. Track remaining flakiness as Pry bugs per ROADMAP
principle 8.

## Session 2026-04-29 — Jig + Carnet field-feedback wave

**Worked on:** Two more dogfooding bilans (Jig + Carnet) converged on
the same first-run blockers. Implemented 8 P0/P1 items, verified 40
unit tests pass + 9/9 DemoApp specs pass.

**Landed (rows 39–46 in [`docs/ROADMAP.md`](docs/ROADMAP.md)):**

- **P0 — `NSRunningApplication.activate()` after every launch path** in
  `AppDriver` (`launchByPath`, `launchByBundleID`, `attach`). Clicks
  no longer go to whatever was foreground when `pry-mcp` ran. Both
  bilans flagged this as the most expensive bug.
- **P0 — `.app` bundle routing through `NSWorkspace.openApplication`**.
  `launchByPath` now async; detects `.app` bundle paths and routes them
  through LaunchServices so provisioning profile + entitlements load.
  Direct `Process.run()` reserved for raw-executable SwiftPM fixtures
  (DemoApp). Solves Jig F1 (HCI entitlement refused under execve).
- **P0 — `pry_right_click` MCP tool + `pry-mcp right-click` CLI**. The
  `right_click:` step was already in the grammar; the surface gap was
  external (no MCP tool, no CLI subcommand).
- **P0 — AXPress fast path on `click:`**. When the resolved role is
  `AXButton` and no modifiers are requested, `AXUIElementPerformAction(
  kAXPressAction)` runs first; CGEvent is the fallback. Wired in both
  `Tools.click` (with `via: auto|ax_press|cgevent` override) and
  `SpecRunner.injectClick`. Bypasses geometric hit-test — fixes
  SwiftUI `Button(.plain)` without `.contentShape(...)`, sub-pixel
  padding, and frontmost-app races.
- **P1 — `activate:` step + `pry_activate` MCP tool + `pry-mcp activate`
  CLI**. Mid-flow focus recovery for sheet dismissals returning focus
  to the parent app, parallel agents, OS dialogs.
- **P1 — `available_paths` / `registered` lists surfaced inline** in
  `path_not_found` and `viewmodel_not_registered` error messages. The
  harness already attached the data; the MCP boundary was dropping it.
  No more silent `selectedBP` vs `selectedBlueprint` typo (Jig M4 /
  Carnet "did you mean").
- **P2 — `expect_state_change:` flag on `pry_click`**. Snapshots the
  named view-model before+after; fails with `state_unchanged` if the
  action handler never ran. Catches Jig F7 ("click resolved AXButton
  ✓ — but action never fired") and Carnet `keyboardShortcut(.return)`
  routing bugs.
- **P2 — `summary.json` always written to verdicts dir** by `run-suite`.
  Sibling exports (`junit:`/`tap:`/`summary_md:`) remain opt-in.

**Decisions:**

- AXPress fast path is **automatic for AXButton + no modifiers**, not
  opt-in. Risk-free: AXPress returning non-success falls through to
  CGEvent, so any disabled/refused button still produces the
  deterministic "click did nothing" failure mode. The MCP tool keeps
  `via: cgevent` as an escape hatch for spec authors who need to test
  the literal hit-test path (rare).
- `expect_state_change:` is a **fail-fast canary**, not a replacement
  for `wait_for` / `assert_state`. It runs immediately after the click
  with a 60ms dwell — long enough to catch "nothing fired" but not long
  enough to wait out async work. Real assertions still belong in
  follow-up steps.
- Skipped Jig F4 (multi-line `for:` arrays) — the Canopy-wave
  `normalizeIndentedBlocksToInline` already handles this; verified by
  the existing parser tests. If it surfaces again the bug is
  `quoteScalarIfNeeded`, not the normalizer.
- Skipped Jig F3 (`wait_for: { target: ... }`) — `wait_for: { id: "..." }`
  already works via the parser's `.contains` fallback. The Jig run
  used `target:` as the wrapping key, which isn't a documented form;
  the existing bare-target syntax handles the use case.
- Skipped Carnet "dry-run mode" (resolve all `id:` upfront) — that's a
  v0.3 lint-side feature, not a v0.2.x patch.

**Tests / smoke:**
- `swift test` — 40/40 pass.
- `pry-mcp run-suite --dir Fixtures/DemoApp/flows` — 9/9 PASS in 19s,
  including the `.app`-bundle / AXPress paths (DemoApp uses raw
  executable so the AXPress fast path is the regression-relevant
  change).
- `summary.json` written, structurally valid (jq-parseable).

**Open questions discovered:** None. Inspector scaffolding ADR
(SwiftSyntax dep vs templated emitter) still pending from the Canopy
wave.

**Blocked on:** nothing.

**Next single action:** Continue Phase 5 dogfooding. Either (a) re-run
Jig with the new toolset and confirm F1/F6/M1 are unblocked, or (b)
tag `v0.2.1` and start the next field-app integration. The eight
items above represent the consolidated v0.2.x DX bar — anything new
from a fresh field run goes into a v0.3 pass.
