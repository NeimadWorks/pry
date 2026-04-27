# Architecture Decision Records

Each ADR records a one-time choice with its context, the alternatives we
rejected, and the consequences we accept. Newer ADRs may **supersede** older
ones — that link is recorded both directions; nothing is ever deleted.

## Index

| # | Title | Status | Themes |
|---|---|---|---|
| [001](ADR-001-distribution-tier.md) | Distribution tier — direct / open source | Accepted | distribution, licensing |
| [002](ADR-002-two-process-split.md) | Two-process split (PryHarness ↔ runner) | Accepted | architecture |
| [003](ADR-003-markdown-spec-format.md) | Markdown test spec format | Accepted | grammar |
| [004](ADR-004-state-introspection-protocol.md) | `PryInspectable` state protocol | Accepted | introspection |
| [005](ADR-005-event-injection-strategy.md) | `CGEventPost` for event injection | Accepted (Spike 2 validated) | events |
| [006](ADR-006-log-observation-strategy.md) | Log observation — `OSLogStore` is best-effort | Accepted | logs |
| [007](ADR-007-virtual-clock.md) | `PryClock` virtual time | Accepted | time, scheduling |
| [008](ADR-008-push-state-and-events.md) | Push state notifications & async event handlers | Accepted | observation, async |
| [009](ADR-009-animation-gating.md) | Animation gating | Accepted | snapshots |
| [010](ADR-010-fixtures-and-network.md) | Fixtures (filesystem, defaults, network) | Accepted | fixtures |
| [011](ADR-011-verdict-richness.md) | Verdict richness, runner infra, a11y, visual | Accepted | reporting, infra |

## When to write a new ADR

- A choice that affects multiple files or future features.
- A choice that overrides what's locked elsewhere (in which case the new ADR
  must supersede the old, and both directions must be linked).
- An assumption that was implicit and now needs to be spelled out so the next
  agent doesn't relitigate it.

## Lifecycle states

- **Proposed** — under review.
- **Accepted** — current.
- **Superseded by ADR-NNN** — replaced; keep the file, link forward.
- **Withdrawn** — never accepted; documents the rejected path so we don't try
  it again.

## Format

Every ADR has these sections in order:

1. **Status** + **Date**
2. **Supersedes / Superseded by** (links, possibly empty)
3. **Context** — what's the situation, why does this need a decision
4. **Decision** — what we're doing
5. **Rationale** — why this and not the alternatives
6. **Alternatives considered** — explicit
7. **Consequences** — what we accept by doing this
