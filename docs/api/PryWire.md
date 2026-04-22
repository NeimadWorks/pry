# `PryWire` — shared wire types

`PryWire` is the SwiftPM module that both `PryHarness` and `pry-mcp` import. It contains **only** Codable message types for the Unix-socket JSON-RPC protocol. No logic. No dependencies beyond `Foundation`.

Its sole purpose: make the wire contract a compile-time concern on both sides of the socket.

---

## Wire protocol

- Transport: `AF_UNIX` stream socket at `/tmp/pry-<bundleID>.sock`.
- Encoding: length-prefixed JSON frames.
  - 4-byte big-endian unsigned integer: frame length in bytes.
  - N bytes: UTF-8 JSON payload.
- Protocol: JSON-RPC 2.0 subset.

Framing keeps `JSONDecoder.decode(_:from:)` simple — read N bytes, decode, done. No newline-delimited streaming, no chunk parsing.

---

## Message shapes

### Request

```json
{
  "jsonrpc": "2.0",
  "id": 42,
  "method": "read_state",
  "params": { "viewmodel": "DocumentListVM", "path": "documents.count" }
}
```

### Response (success)

```json
{
  "jsonrpc": "2.0",
  "id": 42,
  "result": { "value": 3 }
}
```

### Response (error)

```json
{
  "jsonrpc": "2.0",
  "id": 42,
  "error": {
    "code": -32001,
    "message": "viewmodel_not_registered",
    "data": { "known": ["DocumentListVM", "EditorVM"] }
  }
}
```

### Notification (no `id`)

Reserved for future streaming (e.g. log tails). Not used in v1.

---

## Method catalog

All methods PryHarness implements. One Swift `Codable` request/response pair per method.

| Method | Request params | Response |
|---|---|---|
| `hello` | `{ "client": "pry-mcp", "version": "0.1.0" }` | `{ "harness_version": "...", "app_bundle": "..." }` |
| `inspect_tree` | `{ "window": <predicate>? }` | `{ "yaml": "..." }` |
| `read_state` | `{ "viewmodel": "...", "path": "..."? }` | `{ "value": <any> }` or `{ "keys": { ... } }` |
| `read_logs` | `{ "since": "ISO8601"?, "subsystem": "..."? }` | `{ "lines": [...], "cursor": "ISO8601" }` |
| `snapshot` | `{ "window": <predicate>? }` | `{ "png_base64": "..." }` |
| `goodbye` | `{}` | `{}` |

Every new method requires a PR that adds types to `PryWire` **first** — the wire contract changes land before either side uses them.

---

## Error codes

Negative codes per JSON-RPC convention. Pry-specific error codes:

| Code | Name |
|---|---|
| `-32001` | `viewmodel_not_registered` |
| `-32002` | `path_not_found` |
| `-32003` | `window_not_found` |
| `-32004` | `snapshot_failed` |
| `-32005` | `log_store_unavailable` |
| `-32600` | `invalid_request` (JSON-RPC standard) |
| `-32601` | `method_not_found` (JSON-RPC standard) |
| `-32700` | `parse_error` (JSON-RPC standard) |

`pry-mcp` surfaces these as the `error.kind` values listed in [docs/api/pry-mcp-tools.md](pry-mcp-tools.md#error-contract) — the MCP layer does the translation so Claude Code sees stable string kinds, not wire codes.

---

## Versioning

The socket performs `hello` as its first exchange. If `harness_version` and `pry-mcp` version are incompatible, `pry-mcp` aborts with a clear error and a fix pointer (usually: update one or the other).

Compatibility policy: the wire protocol follows semver. Minor versions are additive only — never rename or remove a method or field within a major.
