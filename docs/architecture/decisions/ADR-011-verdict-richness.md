# ADR-011 — Verdict richness, runner infra, a11y audit, visual diff

**Status:** Accepted
**Date:** 2026-04-27

## Context

Verdicts in v0.1 contain step-by-step results, AX tree snippet, registered
state, and an auto-snapshot on failure. For a mature test runner this is a
floor, not a ceiling. We want:

- Per-step screenshots (timeline)
- State delta between steps
- AX tree diff (launch → failure)
- Image diff for visual regression
- A11y audit pass (missing labels, contrast checks)
- Parallel suite execution
- JUnit / TAP output
- Watch mode
- Test-result aggregation across runs

## Decision

Each capability is implemented as a separate concern, gated by spec
frontmatter or runner CLI flags. Defaults stay minimal so existing specs
keep their compact verdicts.

- `screenshots: every_step | failure | always` (default `failure`)
- `state_delta: on | off` (default `on`) — captures snapshot of all VMs
  referenced in `assert_state` between each step
- `assert_snapshot: { name, tolerance: 1% }` step (visual diff vs golden PNG
  in `Tests/Snapshots/`)
- `audit_a11y` step + `--audit-a11y` runner flag — runs heuristic checks
- Runner: `--parallel N`, `--retry-failed M`, `--junit out.xml`,
  `--tap out.tap`, `--watch`

## Rationale

Each addition is independent and additive. Doc-driven design: each comes
with grammar in `spec-format.md` and a CLI flag in `pry-mcp`.

## Consequences

- Verdict files grow when richness is enabled. Mitigated by per-spec opt-in.
- Visual diff requires a built-in image comparator (no external dep —
  ~150 lines on top of `CoreImage`).
- A11y audit ships with a small built-in rule set; further rules added over
  time. Documented as best-effort.
