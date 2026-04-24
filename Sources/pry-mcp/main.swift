import Foundation

// pry-mcp — Pry's out-of-process CLI and MCP server.
//
// Two modes:
//   - With no args (or `mcp`): stdio MCP server.
//   - With a subcommand: CLI mode for hand-driven testing. See `pry-mcp help`.

let argv = Array(CommandLine.arguments.dropFirst())

if argv.isEmpty {
    // Stdio MCP mode — the default when invoked by Claude Code.
    await MCPServer().run()
    exit(0)
} else {
    let code = await CLI.run(argv)
    exit(code)
}
