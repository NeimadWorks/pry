import Foundation
import PryWire

// pry-mcp — Pry's out-of-process CLI and MCP server.
//
// Phase 1 skeleton: this executable compiles and links PryWire so the wire
// contract is enforced across both sides. Real functionality (app lifecycle,
// AX resolution, event injection, MCP stdio server, spec runner) lands in
// subsequent Phase 1 steps.

let version = "0.1.0-dev"

if CommandLine.arguments.contains("--version") {
    print("pry-mcp \(version)")
    print("PryWire methods: \(PryWire.Method.allCases.map(\.rawValue).joined(separator: ", "))")
    exit(0)
}

FileHandle.standardError.write(Data("""
pry-mcp \(version) — not yet functional.
This is a Phase 1 skeleton; the MCP server, AppDriver, and event injection land in later commits.
Run `pry-mcp --version` for a build check.

""".utf8))
exit(1)
