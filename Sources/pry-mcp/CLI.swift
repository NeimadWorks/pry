import Foundation
import ApplicationServices
import CoreGraphics
import PryWire

/// CLI mode for hand-driven testing. Mirrors the MCP tools one-to-one.
///
///   pry-mcp version
///   pry-mcp launch --app <bundle> [--path <exe>] [--arg a --arg b] [--env K=V]
///   pry-mcp terminate --app <bundle>
///   pry-mcp state --app <bundle> --viewmodel <name> [--path <path>]
///   pry-mcp click --app <bundle> --id <ax-id> | --label <label> | --role-label <role>:<label>
///   pry-mcp type --app <bundle> --text <text>
///   pry-mcp key --app <bundle> --combo <combo>
enum CLI {

    static func run(_ args: [String]) async -> Int32 {
        guard let sub = args.first else {
            printUsage()
            return 2
        }
        let rest = Array(args.dropFirst())

        // Fail-fast AX permission check for subcommands that need it. Gives a
        // clean error before we waste time launching the target app.
        let needsAX = ["click", "type", "key", "tree", "find", "snapshot", "run", "run-suite"]
        if needsAX.contains(sub) {
            if !AXIsProcessTrusted() {
                FileHandle.standardError.write(Data("""
                pry-mcp needs Accessibility permission to drive other apps.

                How to fix:
                  1. Open  System Settings → Privacy & Security → Accessibility
                  2. Grant access to the process that spawned this shell (Terminal, iTerm, etc.),
                     since pry-mcp inherits the permission from its parent.
                  3. Fully quit and relaunch that terminal so the grant takes effect.

                Verify with:
                  osascript -e 'tell application "System Events" to get name of every process' >/dev/null && echo "AX OK" || echo "AX KO"


                """.utf8))
                return 3
            }
        }

        do {
            switch sub {
            case "version":
                print("pry-mcp \(PryMCP.version)")
                return 0

            case "launch":
                let out = try await PryTools.launch(.init(
                    app: required(rest, "--app"),
                    executable_path: optional(rest, "--path"),
                    args: repeating(rest, "--arg"),
                    env: envMap(repeating(rest, "--env"))
                ))
                print(try jsonPretty(out))

            case "terminate":
                let out = try await PryTools.terminate(.init(app: required(rest, "--app")))
                print(try jsonPretty(out))

            case "state":
                let out = try await PryTools.state(.init(
                    app: required(rest, "--app"),
                    viewmodel: required(rest, "--viewmodel"),
                    path: optional(rest, "--path")
                ))
                print(try jsonPretty(out))

            case "click":
                let target = try parseTargetArgs(rest)
                let out = try await PryTools.click(.init(app: required(rest, "--app"), target: target))
                print(try jsonPretty(out))

            case "type":
                let out = try await PryTools.typeText(.init(
                    app: required(rest, "--app"),
                    text: required(rest, "--text")
                ))
                print(try jsonPretty(out))

            case "key":
                let out = try await PryTools.key(.init(
                    app: required(rest, "--app"),
                    combo: required(rest, "--combo")
                ))
                print(try jsonPretty(out))

            case "tree":
                let out = try await PryTools.tree(.init(app: required(rest, "--app"), window: nil))
                print(out.yaml)

            case "find":
                let target = try parseTargetArgs(rest)
                let out = try await PryTools.find(.init(app: required(rest, "--app"), target: target))
                print(try jsonPretty(out))

            case "snapshot":
                let out = try await PryTools.snapshot(.init(app: required(rest, "--app"),
                                                             path: optional(rest, "--out")))
                print(try jsonPretty(out))

            case "run":
                let out = try await PryTools.runSpec(.init(
                    source: nil,
                    path: required(rest, "--spec"),
                    markdown: nil,
                    verdicts_dir: optional(rest, "--verdicts-dir"),
                    snapshots: optional(rest, "--snapshots")
                ))
                // Write verdict to stdout (Markdown). Exit code reflects status.
                print(out.verdict_markdown)
                return out.status == "passed" ? 0 : 1

            case "run-suite":
                let out = try await PryTools.runSuite(.init(
                    path: required(rest, "--dir"),
                    tag: optional(rest, "--tag"),
                    verdicts_dir: optional(rest, "--verdicts-dir")
                ))
                print(try jsonPretty(out))
                return out.failed == 0 && out.errored == 0 ? 0 : 1

            case "list-specs":
                let out = try await PryTools.listSpecs(.init(path: required(rest, "--dir")))
                print(try jsonPretty(out))

            case "logs":
                let out = try await PryTools.logs(.init(
                    app: required(rest, "--app"),
                    since: optional(rest, "--since"),
                    subsystem: optional(rest, "--subsystem")
                ))
                print(try jsonPretty(out))

            case "mcp":
                // Explicit stdio MCP mode, same as bare invocation.
                await MCPServer().run()

            case "help", "--help", "-h":
                printUsage()
                return 0

            default:
                FileHandle.standardError.write(Data("unknown subcommand: \(sub)\n\n".utf8))
                printUsage()
                return 2
            }
        } catch let e as PryTools.ToolError {
            var dict: [String: Any] = [
                "kind": e.kind,
                "message": e.message,
            ]
            if let fix = e.fix { dict["fix"] = fix }
            if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]),
               let s = String(data: data, encoding: .utf8) {
                FileHandle.standardError.write(Data((s + "\n").utf8))
            } else {
                FileHandle.standardError.write(Data("error: \(e.kind): \(e.message)\n".utf8))
            }
            return 1
        } catch {
            FileHandle.standardError.write(Data("error: \(error)\n".utf8))
            return 1
        }

        return 0
    }

    // MARK: - Arg helpers

    private static func required(_ args: [String], _ flag: String) throws -> String {
        guard let v = optional(args, flag) else {
            throw PryTools.ToolError.kinded(kind: "invalid_params", message: "missing \(flag)")
        }
        return v
    }

    private static func optional(_ args: [String], _ flag: String) -> String? {
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    private static func repeating(_ args: [String], _ flag: String) -> [String]? {
        var out: [String] = []
        var i = 0
        while i < args.count {
            if args[i] == flag, i + 1 < args.count {
                out.append(args[i + 1]); i += 2
            } else { i += 1 }
        }
        return out.isEmpty ? nil : out
    }

    private static func envMap(_ pairs: [String]?) -> [String: String]? {
        guard let pairs, !pairs.isEmpty else { return nil }
        var out: [String: String] = [:]
        for p in pairs {
            guard let eq = p.firstIndex(of: "=") else { continue }
            let k = String(p[..<eq])
            let v = String(p[p.index(after: eq)...])
            out[k] = v
        }
        return out.isEmpty ? nil : out
    }

    private static func parseTargetArgs(_ args: [String]) throws -> PryTools.TargetSpec {
        var spec = PryTools.TargetSpec()
        if let id = optional(args, "--id") { spec.id = id }
        if let label = optional(args, "--label") { spec.label = label }
        if let lm = optional(args, "--label-matches") { spec.label_matches = lm }
        if let rl = optional(args, "--role-label") {
            let parts = rl.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2 else {
                throw PryTools.ToolError.kinded(kind: "invalid_params",
                    message: "--role-label format is 'Role:Label' (e.g. 'AXButton:Save')")
            }
            spec.role = parts[0]; spec.label = parts[1]
        }
        if let tp = optional(args, "--tree-path") { spec.tree_path = tp }
        if let pt = optional(args, "--point") {
            let parts = pt.split(separator: ",").compactMap { Double($0) }
            guard parts.count == 2 else {
                throw PryTools.ToolError.kinded(kind: "invalid_params",
                    message: "--point format is 'x,y' (e.g. '120.5,340')")
            }
            spec.point = .init(x: parts[0], y: parts[1])
        }
        return spec
    }

    private static func jsonPretty<T: Codable>(_ v: T) throws -> String {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try e.encode(v)
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    // MARK: - Usage

    private static func printUsage() {
        let help = """
        pry-mcp \(PryMCP.version)

        Usage:
          pry-mcp <subcommand> [args...]
          pry-mcp                     # start stdio MCP server (no args)

        Subcommands:
          version
          mcp                         # explicit stdio MCP mode
          launch      --app <bundle> [--path <exe>] [--arg <a>]... [--env K=V]...
          terminate   --app <bundle>
          state       --app <bundle> --viewmodel <name> [--path <path>]
          click       --app <bundle> <target>
          type        --app <bundle> --text <text>
          key         --app <bundle> --combo <combo>
          tree        --app <bundle>                         # AX tree as YAML
          find        --app <bundle> <target>                # all matches for a target
          snapshot    --app <bundle> [--out <path>]          # front window PNG
          run         --spec <file.md> [--verdicts-dir <d>]  # run one spec; exit reflects status
          run-suite   --dir <dir> [--tag <tag>] [--verdicts-dir <d>]
          list-specs  --dir <dir>

        Target for `click`: one of
          --id <ax-identifier>
          --label <label>
          --role-label <Role:Label>
          --label-matches <regex>
          --tree-path <Window[0]/Group/Button[2]>
          --point <x,y>

        Examples:
          pry-mcp launch --app fr.neimad.pry.demoapp --path $PWD/DemoApp
          pry-mcp state  --app fr.neimad.pry.demoapp --viewmodel DocumentListVM --path documents.count
          pry-mcp click  --app fr.neimad.pry.demoapp --id new_doc_button
          pry-mcp type   --app fr.neimad.pry.demoapp --text "Ma composition"
          pry-mcp key    --app fr.neimad.pry.demoapp --combo return

        """
        FileHandle.standardError.write(Data(help.utf8))
    }
}
