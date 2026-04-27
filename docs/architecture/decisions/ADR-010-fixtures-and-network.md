# ADR-010 — Fixtures (filesystem, defaults, network)

**Status:** Accepted
**Date:** 2026-04-27

## Context

File-manager apps demand a known on-disk tree before each test. Mail clients
demand controlled network responses. i18n tests demand a specific locale.
Without first-class fixtures, every test recreates this scaffolding by hand
and leaks state between runs.

## Decision

Three fixture surfaces, all opt-in via spec frontmatter:

### `with_fs:`

```yaml
with_fs:
  base: ~/.pry-tmp/canopy-tests/<spec-id>
  layout:
    - file: report.txt, content: "hello"
    - dir: assets
    - file: assets/img.png, source: ./fixtures/img.png
```

The runner creates the base directory before launch, populates it, and
deletes it after teardown. The base path is exported as `${fixture_dir}` in
spec variables so steps can reference it.

### `with_defaults:`

```yaml
with_defaults:
  AppleLanguages: [fr, en]
  AppleLocale: fr_FR
  CFBundleAllowMixedLocalizations: true
```

Written to the target app's `~/Library/Preferences/<bundle>.plist` before
launch via `defaults write`. Restored after teardown.

### `with_network:` (separate ADR — see ADR-011)

Provided by a `URLProtocol`-based stub installed by the host app at startup
when an env var is set. Pry passes a JSON map of (path → response) through
the env, the host app's `PryNetworkStub` reads and routes it.

## Rationale

- All three fit the existing "harness opt-in" pattern: app or runner does the
  setup, the spec just declares intent.
- Cleanup is automatic — failures in the test do not leave dirty state.
- No daemon. No sidecar processes. Everything happens in setup/teardown.

## Consequences

- The runner gains responsibility for creating/cleaning fixture directories.
- Apps that want network mocking need to add `PryNetworkStub.install()` under
  `#if DEBUG`. Documented as a `PryHarness` extension.
- Per-spec sandboxing implies a temp dir convention: `~/.pry-tmp/<bundle>/<id>`.
