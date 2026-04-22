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

**Phase:** pre-spike. Architecture locked. No source code yet.

**Open blockers:** five spikes in [PROJECT-BIBLE §11](PROJECT-BIBLE.md#11-validated-assumptions) must return PASS/FAIL before any implementation. The branch decisions depend on their results.

**Next single action:** run **Spike 2 — Synthetic CGEvent acceptance** first. It has the highest blast radius: if it fails, the entire event-injection strategy changes and §6 needs amending via a new ADR superseding ADR-005.

**Not blockers:**
- Repo scaffolding (`Package.swift`, source tree stubs) — can be done in parallel with spikes.
- `Fixtures/DemoApp` — needed to run spikes 1, 2, 3. Build it minimal: one `Button`, one `TextField`, one `List` bound to a VM.

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
