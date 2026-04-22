# ADR-003 — Markdown test spec format

**Status:** Accepted
**Date:** 2026-04-22
**Supersedes:** —
**Superseded by:** —

## Context

Claude Code is good at writing Markdown. It is less good at writing DSLs, Swift test cases, or JSON graphs with deep nesting. Test specs must be something Claude can author correctly on the first try, and a human can read at a glance.

## Decision

Pry test specs are **Markdown files** with:

- YAML frontmatter for metadata (id, app bundle, tags, timeout).
- Body prose (explains intent to human readers).
- Fenced ` ```pry ` blocks containing one declarative step per line.

Steps are declarative YAML-flavored commands, not Swift, not JSON, not a recording. See [docs/design/spec-format.md](../../design/spec-format.md) for the full grammar.

## Rationale

- **Writable by LLMs.** Markdown + YAML is the lingua franca of documentation; every LLM handles it.
- **Readable by humans.** A Dom skim can tell what a test is doing without running it.
- **Diffable.** Pull request reviews are plain text diffs, which is the whole point.
- **Declarative.** Steps express intent (`click: { label: "Save" }`) rather than coordinates. This survives layout changes that would break pixel-based tests.
- **Executable.** The fenced ` ```pry ` blocks keep the DSL fenced off from surrounding prose so a parser can extract them cleanly.

## Alternatives considered

- **Swift-based test cases (XCUITest-style).** Rejected: ceremony, compile-run loop, LLMs write them worse than they write Markdown, not human-skim-friendly.
- **Pure YAML files.** Rejected: lose the ability to intersperse prose explanation; less readable.
- **JSON test definitions.** Rejected: unreadable, hostile to diffs, poor LLM authoring ergonomics.
- **Custom DSL with its own extension.** Rejected: LLMs have never seen it, tools don't syntax-highlight it.

## Consequences

- We own a parser for a Markdown subset with YAML frontmatter and ` ```pry ` blocks.
- The spec format must be versioned. Breaking changes bump `pry_spec_version` and require a migration note. Invariant locked in [PROJECT-BIBLE §14](../../../PROJECT-BIBLE.md#14-invariants).
- The grammar sits between "free-form natural language" and "strictly typed DSL." We commit to the tradeoff: mild ambiguity on the input side, strictness enforced at parse time with precise error messages.
