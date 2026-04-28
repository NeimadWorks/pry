# Pry — Roadmap

This document is the **single source of truth** for what's shipped, what's
in flight, and what's been considered but deferred. It complements
[`PROJECT-BIBLE.md`](../PROJECT-BIBLE.md) (which holds invariants and
non-goals) and [`docs/architecture/decisions/`](architecture/decisions/)
(which captures the architectural choices that make these features
possible or out of reach).

When opening this repo, agents should:

1. Skim "Shipped" to understand what's available today.
2. Read "Now" / "Next" to see active work.
3. Check "Backlog" before proposing new features — chances are it's there.
4. Respect "Out of scope" — those have been ruled out with rationale.

---

## Shipped

### `v0.1.0` (2026-04-27)

First tagged release. Architecture, four products, full grammar v1,
9 DemoApp specs.

**Components**
- `PryHarness` — in-process socket server, `PryInspectable`, `PryRegistry`,
  `PryStateBroadcaster`, `PryClock`, `PryAnimations`, `PryEventBus`,
  `PryLogTap`.
- `PryWire` — shared Codable JSON-RPC types incl. notifications.
- `PryRunner` — public Swift library: `Pry` actor, `SpecParser`,
  `SpecRunner`, `VerdictReporter`, `AXTreeWalker`, `ElementResolver`,
  `EventInjector`, `WindowCapture`, `AppDriver`, `HarnessClient`,
  `FilesystemFixtures`, `DefaultsFixtures`, `ImageDiff`,
  `AccessibilityAudit`, `VerdictExporters`.
- `pry-mcp` — stdio MCP wrapper + CLI mirroring 25+ tools.

**Grammar (`pry_spec_version: 1` — frozen)**

Lifecycle, mouse / drag / scroll / magnify / long-press / marquee with
modifier keys, type with delay, key with repeat, predicates, assertions,
`expect_change`, control flow (`if` / `for` / `repeat` / `call`),
variables / includes / setup / teardown, async event handlers, time
control (`clock.advance` / `set` / `set_animations`), sheet / menu /
pasteboard helpers, file panels (`open_file` / `save_file` /
`panel_accept` / `panel_cancel`), filesystem & defaults fixtures,
screenshot policies.

**Architecture pinned by 11 ADRs.** See [`decisions/README.md`](architecture/decisions/README.md).

### Post-`v0.1.0` DX iteration (on `main`, 2026-04-28)

Triggered by a real-app feedback session on Narrow (chess study, 13K-symbol
explorer). Backward-compatible, additive only — no version bump on the
spec grammar.

| # | Improvement | Where |
|---|---|---|
| 1 | Numeric comparators (`gt`, `gte`, `lt`, `lte`, `between`) for `assert_state` and `count:` | [spec-format §6](design/spec-format.md#6-predicates) |
| 2 | `matches:` auto-coerces Int / Double / Bool to string | [spec-format §6](design/spec-format.md#6-predicates) |
| 3 | `key:` accepts punctuation (`[`, `]`, `;`, `,`, `.`, `/`, `'`, `\`, `` ` ``, `=`, `-`), digit row, F1–F12, forwarddelete | [spec-format §4 keyboard](design/spec-format.md#4-step-commands) |
| 4 | `.pry/config.yaml` for per-project `executable_path` (with env-var override) | [spec-format §9](design/spec-format.md#9-project-config-pryconfigyaml) |
| 5 | `nth: N` disambiguator on any target | [spec-format §5](design/spec-format.md#5-targets) |
| 6 | `panel: any` and `panel: { title_matches }` predicates | [spec-format §6](design/spec-format.md#6-predicates) |
| 7 | Auto-`.gitignore` inside the verdicts root | runtime |
| 8 | SIGINT/SIGTERM cleanup of stale `/tmp/pry-*.sock` | `pry-mcp` |
| 9 | AX context fallback when `AXTreeWalker.snapshot` is empty | verdict |
| 10 | "SwiftUI gotchas" section (accessibilityIdentifier propagation, AX role map, custom tap-zone traits) | [writing-specs](guides/writing-specs.md#swiftui-gotchas) |

### `v0.2`-track DX additions (on `main`, 2026-04-28)

Targets the entirety of the previous "Next" section. Backward-compatible,
all opt-in. Pre-v0.2 tag.

| # | Improvement | Where |
|---|---|---|
| 11 | `pry-mcp lint --dir flows` — parse-only validation, CI gate | [pry-mcp-tools](api/pry-mcp-tools.md#pry_lint) |
| 12 | `pry-mcp init --bundle-id ... --product ...` — scaffold `.pry/config.yaml` | [pry-mcp-tools](api/pry-mcp-tools.md#pry_init) |
| 13 | `pry-mcp report --build <verdicts-dir>` — self-contained HTML dashboard with embedded PNGs | [pry-mcp-tools](api/pry-mcp-tools.md#cli-mirror) |
| 14 | `assert_focus: <target>` first-class step | [spec-format](design/spec-format.md#assertions) |
| 15 | `assert_eventually: PRED [timeout: 1s]` (assertion-framed wait) | [spec-format](design/spec-format.md#assertions) |
| 16 | `soft_assert_state: ...` accumulates failures, reported at the end | [spec-format](design/spec-format.md#assertions) |
| 17 | `select_range: { from, to }` and `multi_select: [...]` selection helpers | [spec-format](design/spec-format.md#selection-helpers) |
| 18 | `with_retry: N` + body — retry-on-failure block with backoff | [spec-format](design/spec-format.md#control-flow-wave-2) |
| 19 | `copy_to: { var, from: pasteboard \| { viewmodel, path } }` — runtime variables | [spec-format](design/spec-format.md#capturing-into-runtime-variables) |
| 20 | `slow_warn_ms` frontmatter — flags slow steps in verdict | [spec-format §2](design/spec-format.md#2-frontmatter) |
| 21 | `state_delta: every_step` — multi-step VM snapshot timeline | [spec-format §2](design/spec-format.md#2-frontmatter) |
| 22 | `ax_tree_diff: on_failure` — diff vs launch-time tree | [spec-format §2](design/spec-format.md#2-frontmatter) |
| 23 | `screenshots_embed: true` — base64-inline PNGs in `verdict.md` | [spec-format §2](design/spec-format.md#2-frontmatter) |
| 24 | Closure-type-inference fix in `SpecRunner.doLaunch` (Narrow report) | bug |
| 25 | CI: tag-trigger release + Homebrew tap auto-bump (gated on secrets) | [.github/workflows/ci.yml](../.github/workflows/ci.yml) |
| 26 | CI: `pry-mcp lint` runs against `Fixtures/DemoApp/flows` on every PR | [.github/workflows/ci.yml](../.github/workflows/ci.yml) |

### Canopy field-feedback wave (on `main`, 2026-04-28)

Triggered by a real run on Canopy (file manager, AppState + sheet-heavy UI).
Twelve concrete frictions and one parser bug. All backward-compatible.
Bumps the suite to 40 unit tests + 9 specs PASS.

| # | Improvement | Where |
|---|---|---|
| 27 | Multi-line indented frontmatter for object-valued keys (`with_fs`, `with_defaults`, `vars`). Previously silently dropped. | [spec-format §2](design/spec-format.md#2-frontmatter) |
| 28 | `not_matches:` and `not_equals:` state expectations | [spec-format §6](design/spec-format.md#6-predicates) |
| 29 | `sheet: any` / `sheet: { title_matches }` predicate (distinct from `panel:`) | [spec-format §6](design/spec-format.md#6-predicates) |
| 30 | `expect_total: N` companion to `nth:` — fails if match-count drifts | [spec-format §5](design/spec-format.md#5-targets) |
| 31 | `assert_stable: PRED for: 1s` — anti-flicker continuous predicate | [spec-format](design/spec-format.md#assertions) |
| 32 | `type_chars: "saf"` (per-char typing for `key.count == 1` filters) | [spec-format](design/spec-format.md#keyboard) |
| 33 | `dump_focus: "name"` step + `pry-mcp focus --app X` CLI | [spec-format](design/spec-format.md#debug-aids) |
| 34 | `wait_for_focus: <target>` step — replaces empirical `sleep:` | [spec-format](design/spec-format.md#waits) |
| 35 | `pry-mcp menu --app X --path "View > View Mode"` — open menu and dump children without closing | [pry-mcp-tools](api/pry-mcp-tools.md#pry_menu_inspect) |
| 36 | `pry-mcp tree --compact` — strip SwiftUI generic-modifier-chain labels >200 chars | [pry-mcp-tools](api/pry-mcp-tools.md#pry_tree) |
| 37 | `auto_build: true` in `.pry/config.yaml` — runs `swift build` before launch | [spec-format §9](design/spec-format.md#9-project-config-pryconfigyaml) |
| 38 | `View.pryRegister(_:)` SwiftUI modifier — auto-(un)register `@StateObject` VMs | [PryHarness](api/PryHarness.md#auto-registration-with-pryregister) |

### Jig + Carnet field-feedback wave (on `main`, 2026-04-29)

Two more dogfooding sessions converged on the same first-run blockers
("CGEvents go to the wrong app", "right-click missing", "click passes but
nothing happens"). Eight items, all P0/P1 in the source bilans.

| # | Improvement | Where |
|---|---|---|
| 39 | `NSRunningApplication.activate()` after `launchByPath`, `launchByBundleID`, and `attach` — the launched app is now guaranteed frontmost before the first event is injected. Solves "clicks go to Claude Code / Terminal". | [Driver/AppDriver.swift](../Sources/PryRunner/Driver/AppDriver.swift) |
| 40 | `.app` bundle paths in `executable_path:` route through `NSWorkspace.openApplication` (loads provisioning profile + entitlements). Direct `Process.run()` is reserved for raw-executable SwiftPM fixtures. | [AppDriver.launchByPath](../Sources/PryRunner/Driver/AppDriver.swift) |
| 41 | `right_click:` step was already in the grammar; now also exposed as `pry_right_click` MCP tool and `pry-mcp right-click --app X --id Y` CLI subcommand. | [pry-mcp-tools](api/pry-mcp-tools.md#pry_right_click) |
| 42 | `activate:` step + `pry_activate` MCP tool + `pry-mcp activate --app X` CLI — recovery hook for mid-flow focus theft. | [spec-format §3](design/spec-format.md#lifecycle), [pry-mcp-tools](api/pry-mcp-tools.md#pry_activate) |
| 43 | AXPress fast-path on `click:` — when the resolved target is an `AXButton` and no modifier keys are requested, `AXUIElementPerformAction(kAXPressAction)` runs first; CGEvent is the fallback. Bypasses geometric hit-test (SwiftUI `Button(.plain)` without `.contentShape`, sub-pixel padding, frontmost-app races). | [SpecRunner.injectClick](../Sources/PryRunner/Spec/SpecRunner.swift), [Tools.click](../Sources/pry-mcp/MCP/Tools.swift) |
| 44 | `expect_state_change:` flag on `pry_click` — snapshots the named view-model before+after and fails with `state_unchanged` if the action handler never ran. Catches `keyboardShortcut(.return)` routing bugs and "AXPress succeeds but nothing fires" silently. | [pry-mcp-tools](api/pry-mcp-tools.md#pry_click) |
| 45 | `path_not_found` and `viewmodel_not_registered` errors now surface the `available_paths` / `registered` lists inline in the message — no more silent `selectedBP` vs `selectedBlueprint` typo. | [Tools.translate](../Sources/pry-mcp/MCP/Tools.swift) |
| 46 | `summary.json` is always written to the verdicts directory after `run-suite` (alongside opt-in `junit:` / `tap:` / `summary_md:`). Stable consumption point for CI / dashboards. | [Tools.runSuite](../Sources/pry-mcp/MCP/Tools.swift) |

---

## Now

Nothing in flight. The previous "Next" bucket has been delivered (rows
11–46 in the table above). Next field run will produce the next priority
signal.

---

## Next — likely v0.3

Pending field validation, the "ready-but-not-yet-pulled" items live here.
Each follows naturally from current architecture; none requires an ADR.

- **Multi-spec coverage report** — coverage of `prySnapshot()` keys hit
  during a suite. "Are we asserting on every key our VMs expose, or are
  some never observed?"
- **`pry-mcp doctor`** — environment self-test: AX permission status,
  socket cleanliness, harness handshake against any registered app.
- **Per-step retry policy in frontmatter** — `retry: { steps: ["click *", "wait_for *"], count: 2 }`
  to apply `with_retry` semantics to whole categories of steps without
  wrapping each one.
- **Watch-mode HTML dashboard** — `pry-mcp report --watch` rebuilds the
  HTML on verdict-dir changes. Killer for local TDD.
- **Fan-in suite report** — combine multiple `pry-mcp run-suite` outputs
  into one aggregate dashboard (matrix CI: macOS 14 vs 15, debug vs
  release).

---

## Backlog — considered, deferred

Each entry has a rationale for the delay (size, dependency, design
uncertainty). Pick from here when planning the next iteration.

### Real-time log tee — Tier 2 logs (PROJECT-BIBLE Q5)

Reintroduce `assert_logs` / `assert_no_errors` in v2 grammar. Requires
a `PryLog` host-app wrapper around `Logger` that tees to an mmap'd file
or socket so the runner can read in real time. ADR-006 deferred this
to post-v0.1; still right call.

**Effort:** moderate (~300 lines incl. wrapper, file/socket tail, parser
changes). **Prerequisite:** a clear story on whether the wrapper is
opt-in per call site or globally swapped via `OSLog.subsystem`.

### Multi-instance per bundle ID

Currently the harness socket path is `/tmp/pry-<bundleID>.sock`, so two
instances of the same app collide. Cases that need this: testing
inter-app IPC inside a single app's container, sandbox isolation tests.

**Effort:** moderate. Wire protocol gains an instance suffix; spec grammar
gains an `instance:` field. **Prerequisite:** spec writers have a way to
disambiguate which instance a step targets.

### Network mocking (`with_http:`)

App-side opt-in via a `PryNetworkStub` `URLProtocol`. Spec frontmatter
declares `(path → response)` pairs. Critical for mail clients (Vessel),
useful for any cloud-sync app.

**Effort:** moderate (host-side wrapper + protocol install + spec hooks).
**Prerequisite:** ADR for the boundary between host adoption and runner
control. Cf. ADR-010 which already mentions this pathway.

### Database fixtures (`with_db:`)

For apps with a SQLite/Core Data layer (Carnet PGN store, Narrow symbol
DB, mail message store). Spec frontmatter declares either a seed file
path or an inline schema + rows. Runner copies-then-points the app at
the seeded DB before launch, restores after teardown.

**Effort:** light if the app exposes a "DB path" env var or launch arg
already; moderate otherwise (need a `PryDB` indirection).
**Prerequisite:** decide on the seed format (SQL, JSON, dump file).

### Multi-app driving

Drive App A while observing App B (or vice versa). Specifically:
inter-app drag-and-drop (Finder → Canopy, Carnet ↔ external PGN viewer),
notification handoff (Vessel → Calendar), service interactions.

**Effort:** moderate. `Pry.attach(to:)` already exists; need spec
support for multiple apps in one flow + a way to scope steps by app.
**Grammar sketch:** `in_app "fr.neimad.canopy": { click: ... }`.

### Keypath assertions on arrays / dicts

`assert_state: { path: "documents[0].title", equals: "untitled.txt" }`.
Currently only top-level dict keys work — VMs have to flatten or expose
helper booleans.

**Effort:** light on the parser, moderate on the host-app side
(`prySnapshot()` returns `[String: any Sendable]` — paths into nested
structures need a syntax in PryHarness for "yes I expose a sub-path
into this Sendable").

### Multi-value `expect_change`

`expect_change: { action: ..., to: { count: 3, isLoading: false }, ... }`
to assert several state slots in one go.

**Effort:** light. Just a parser + runner extension.

### Visual regression — `assert_snapshot`

Spec gains `assert_snapshot: { name: "x", tolerance: 1% }`. Runner
compares against `Tests/Snapshots/x.png` using `ImageDiff` (already
shipped in v0.1). Provides golden-file workflow with optional region
masking for dynamic content.

**Effort:** light at the runner; the work is in the workflow (record
mode, accept-new mode, masking syntax).

### Layout-aware AX tree diff

"The Save button moved from position 2 to position 4 in the toolbar."
Structural diff between two AX tree snapshots, hierarchy-preserving.
Useful for accessibility regression and component reordering.

**Effort:** moderate. Tree differ + report renderer.

### A11y audit expansion

`AccessibilityAudit` ships with 4 rules (missing label, textfield no
identifier, zero-frame interactive, nested button). Add: VoiceOver
reachability, color-contrast on snapshots, dynamic-type behavior, RTL
mirroring sanity.

**Effort:** continuous. Each rule is small; the bulk is the
heuristics-vs-false-positive tuning.

### Editor integration

VS Code / Cursor / Xcode plugin: status of last run in the sidebar,
click-to-jump on failed steps, run-on-save.

**Effort:** large (it's a separate codebase). Out of this repo.

### Record-and-replay

Watch a manual session, emit a draft spec. Killer feature for
bootstrapping. Big design space (which clicks to capture, how to
generalize selectors, how to detect waits).

**Effort:** large. Out of v1 scope per spec-format §8.

### Coverage / source linkage

"Persona-04 exercised `disassembleSymbol()` and 80 % of
`ControlFlowGraph.build()`." Couples Pry verdicts to LLVM coverage
output. Big architectural question (what coverage tool, where the
mapping lives).

**Effort:** large. Worth a separate ADR.

### Snapshot drift tracking

"This test passed but `historyCount` is 3 today vs 2 yesterday."
Required infra: persistent verdict store across runs (DB or filesystem),
diff renderer, threshold rules.

**Effort:** moderate. Could be a separate `pry-mcp trends` subcommand.

### True 2-finger HID pinch

Currently `magnify` uses Option+scroll which works for SwiftUI's
`MagnificationGesture` and many AppKit pinch handlers, but not all
custom recognizers. Real 2-finger HID pinch via private
`IOHIDEvent` is fragile and undocumented; deferred. (PROJECT-BIBLE Q6.)

**Effort:** moderate. **Risk:** private API, App Review concerns even
for pry-mcp itself (though pry-mcp isn't App Store anyway).

### Inspector scaffolding (`pry-mcp scaffold-inspector`)

Generate a `PrySupport.swift` boilerplate from a Swift source file by
parsing `@Published` properties. Writing 10 inspectors by hand for an
app with 10 sheets / drawers / dialogs is tedious — this is the
multiplier from the Canopy report.

**Effort:** moderate. Swift source parsing via SwiftSyntax (which we'd
have to depend on) or via heuristic regex (fragile but no dep). The
clean implementation requires SwiftSyntax which violates Pry's
zero-dep policy — **needs an ADR** that either carves out an exception
("dev-only tool, not shipped in the binary") or chooses regex.

### Multi-char `type:` warning detection

Detect when a bulk `type:` step lands while the focused field rejects
multi-char Unicode events (legitimate SwiftUI `.onKeyPress` /
IME-aware filter). Approach: monitor a related VM key for change after
`type:` and emit a verdict warning if nothing moved. Heuristic, easy
to false-positive.

**Effort:** light. **Risk:** false-positive rate on fields whose
mutation isn't reflected in a registered VM. Documented workaround
(`type_chars:`) ships in v0.2-track row #32. Land this only if the
Narrow / Canopy / Carnet runs report the gotcha re-occurs despite
the doc note.

### Verdict warnings layer ("30% diagnostic time")

Emit verdict-time warnings for suspicious patterns:

  - `type:` after click on TextField but VM didn't mutate
  - `with_fs:` declared but no fixture file reads observed
  - Multi-step delta where a registered VM key never moves
  - Step that depends on focus but no preceding `wait_for_focus`

**Effort:** moderate. **Prerequisite:** stable VM access trace from the
runner. **Risk:** noise. The right form is opt-in `--strict` flag, not
a default.

### Phase 5 dogfooding

Adopt Pry on Proof / Probe / Narrow / Harald / Carnet. Each is a real
app outside this repo. Per-app:

- Add `PryHarness` SwiftPM dep `#if DEBUG`
- Register VMs
- Write `flows/`
- Add to CI

**Effort:** per-app, ranges from light (Narrow already has the field
report — most of the legwork is done) to moderate. Out of this repo's
direct scope.

---

## Out of scope

These have been **explicitly ruled out** in [PROJECT-BIBLE §15](../PROJECT-BIBLE.md#15-non-goals).
Listed here so they don't get re-proposed.

- iOS / Catalyst support
- Visual regression testing as a *primary* feature (it remains a
  *capability* via `ImageDiff` — but specs don't lead with pixel asserts)
- Performance benchmarking (Instruments owns that)
- Unit-test replacement (Swift Testing owns that)
- Cross-platform (Windows/Linux)
- Cloud / remote execution
- Telemetry, even opt-in
- Test recorder GUI (deliberately — see record-and-replay backlog entry
  for the agent-friendly alternative)
- LLM-driven test generation *inside Pry* (Claude Code writes specs from
  outside; Pry runs them)

---

## Versioning

- Additive grammar changes ship within `pry_spec_version: 1` and are
  documented under "Shipped".
- A v2 grammar will require a migration note in [`spec-format.md`](design/spec-format.md)
  and bump the version. None planned for v0.x.
- Wire protocol breaking changes require an ADR + version bump on
  `PryHarness.version` / `harness_version` in the `hello` exchange.

---

## Contributing to the roadmap

If you want to advocate for an item in the backlog or propose something
new:

1. Check [`PROJECT-BIBLE §13`](../PROJECT-BIBLE.md#13-non-negotiables)
   and [`§15`](../PROJECT-BIBLE.md#15-non-goals) — those don't move.
2. Open an issue or write an ADR draft in
   [`docs/architecture/decisions/`](architecture/decisions/).
3. Reference the relevant backlog entry here in the discussion.

The roadmap is updated at the end of every session that ships visible
work.
