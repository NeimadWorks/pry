# Contributing to Pry

Thanks for the interest. A few things will make your PR land faster.

---

## Before you open an issue or PR

1. Read [PROJECT-BIBLE.md](PROJECT-BIBLE.md). It is the source of truth. The non-negotiables (§13) and non-goals (§15) are closed — they exist specifically to end scope debates.
2. Check [docs/architecture/decisions/](docs/architecture/decisions/). Some questions are already answered with rationale.
3. Skim [CLAUDE.md](CLAUDE.md) to see what phase the project is in. An API PR during the spike phase is unlikely to land.

If your change conflicts with PROJECT-BIBLE, your PR should include an ADR proposal, not just a code diff.

---

## Kinds of contributions

### ✅ Welcome

- Spike work that fills a `[ ] PASS [ ] FAIL` row in [§11](PROJECT-BIBLE.md#11-validated-assumptions). One focused Swift file per spike, with a written PASS/FAIL and evidence.
- Bug reports with a minimal reproducing spec and verdict file attached.
- Doc improvements that preserve meaning.
- Tests covering existing behavior.
- Additional `Fixtures/DemoApp` surface that exercises scenarios Pry needs to support.

### ❓ Let's discuss first (open an issue)

- New MCP tools.
- Changes to the spec grammar.
- New public API on `PryHarness`.
- New ADRs (supersede existing ones if needed).

### ❌ Will be closed

- iOS / cross-platform support.
- Features from [§15 non-goals](PROJECT-BIBLE.md#15-non-goals).
- Added dependencies.
- Changes that weaken an invariant (§14) without superseding the relevant ADR.
- Telemetry of any kind, even opt-in.

---

## Code style

- Swift 6, strict concurrency on.
- Zero dependencies across all targets. Foundation + system frameworks only.
- No Combine. No `async` on the socket wire — plain `Data` + `JSONDecoder`.
- Public API on `PryHarness` is `#if DEBUG`-gated, always.
- Comments explain *why*, not *what*. Most code needs none.

Run `swift build` and `swift test` before pushing. CI runs both on macOS-latest.

---

## Commit messages

Short imperative summary. Link to an issue or ADR when relevant. Example:

```
harness: clean up orphaned sockets on start

Fixes a crash-after-crash scenario where the second launch would
fail to bind. Covered by new test in PryHarnessTests.
```

---

## ADR workflow

1. Pick the next free ADR number.
2. Copy the format of an existing ADR (e.g. [ADR-002](docs/architecture/decisions/ADR-002-two-process-split.md)).
3. If superseding an existing ADR, set **Superseded by** on the old one and **Supersedes** on the new one. Never delete old ADRs.
4. Open a PR titled `docs(adr): ADR-NNN — <title>`.

---

## Releasing

Release cadence is slow. Semver.

- **0.x.y** — pre-1.0. Breaking changes allowed on minor bumps. Wire protocol bumps require either a backward-compatible path or a migration note in the release.
- **≥1.0.0** — breaking changes only on major.

Release artifacts:
- GitHub release with signed `pry-mcp` binary for macOS 14+.
- Homebrew tap update.
- Tagged SwiftPM version for `PryHarness`.

No NPM, no CocoaPods, no other channels.
