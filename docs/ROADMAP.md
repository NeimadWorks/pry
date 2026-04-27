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

---

## Now

Nothing in flight. Waiting for the next field run to produce the next
priority signal. If you're working on this and pick something up, set its
status here.

---

## Next — likely v0.2

These are the items most likely to land next. They follow naturally from
the v0.1 architecture and have at least one validated demand from a real
user / real app.

### Spec authoring

- **Mode `pry-mcp lint specs/`** — validate syntax (frontmatter, fenced
  blocks, target shapes, predicate forms) without launching any app.
  Cheap CI gate.
- **`pry-mcp init`** — scaffold a `.pry/config.yaml` from a SwiftPM
  manifest by inspecting `swift package describe --type json` for the
  bundle ID and binary path.
- **`assert_focus: <target>`** as a first-class step (currently only via
  `focused:` predicate inside `wait_for`/`assert_tree`).
- **`select_range: { from, to }`** and **`multi_select: [<target>, ...]`**
  — sugar for the `cmd+click` chain.
- **`copy_to: var_name`** — capture pasteboard / state into a variable
  for later assertion.

### Runner / observation

- **Soft assertions** — `assert.soft_state: ...` accumulates failures
  instead of bailing. The verdict reports all of them at the end.
- **`@retry: N` on a single step** — narrower than `--retry-failed M`
  at the suite level. Useful for known-flaky animation-bound steps.
- **`assert_eventually: PRED within: 1s`** — explicit "predicate must
  hold within window, also captures the time it took". Conceptually
  distinct from `wait_for` (waiting until) and `assert` (must hold now).
- **Step-level annotations**: `@warn_if_slower: 500ms` to flag perf
  regressions without failing.

### Verdict richness

- **Inline-embedded screenshots** (base64) so the `verdict.md` is fully
  self-contained for sharing in PR comments / chat.
- **State delta between steps**, not just at failure — useful timeline.
- **AX tree diff** between launch and failure (requires snapshotting at
  launch, currently only done on failure).
- **`pry-mcp report --serve`** — serve a small HTML dashboard over the
  verdicts directory: per-spec timeline with screenshots + state.

### Distribution

- **Tagged release pipeline** — `./scripts/release.sh v0.1.0` works
  locally with Apple Developer ID + notarytool but the CI workflow
  doesn't run it yet (no automated signing). Worth wiring once the cert
  + secrets story is settled.
- **Homebrew tap** — formula template ready; need the separate
  `NeimadWorks/homebrew-tap` repo, the URL + sha256 update.

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
