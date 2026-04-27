import Foundation
import Darwin

// pry-mcp — Pry's out-of-process CLI and MCP server.
//
// Two modes:
//   - With no args (or `mcp`): stdio MCP server.
//   - With a subcommand: CLI mode for hand-driven testing. See `pry-mcp help`.

// Best-effort cleanup on SIGINT / SIGTERM. We don't track every spawned app
// here (the spec runner / Pry actor own those handles), but we DO know about
// any /tmp/pry-*.sock files this process touched. Leaving them behind would
// trip up the next run; gone-from-disk + lazy unbind on subsequent launch is
// cleaner than a long-lived registry.
signal(SIGINT) { _ in
    let tmp = "/tmp"
    if let entries = try? FileManager.default.contentsOfDirectory(atPath: tmp) {
        for entry in entries where entry.hasPrefix("pry-") && entry.hasSuffix(".sock") {
            unlink((tmp + "/" + entry))
        }
    }
    _exit(130) // 128 + SIGINT
}
signal(SIGTERM) { _ in
    let tmp = "/tmp"
    if let entries = try? FileManager.default.contentsOfDirectory(atPath: tmp) {
        for entry in entries where entry.hasPrefix("pry-") && entry.hasSuffix(".sock") {
            unlink((tmp + "/" + entry))
        }
    }
    _exit(143)
}

let argv = Array(CommandLine.arguments.dropFirst())

if argv.isEmpty {
    // Stdio MCP mode — the default when invoked by Claude Code.
    await MCPServer().run()
    exit(0)
} else {
    let code = await CLI.run(argv)
    exit(code)
}
