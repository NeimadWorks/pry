import Foundation
import ApplicationServices
import CoreGraphics
import PryWire
import PryRunner

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
                let out = try await PryTools.tree(.init(
                    app: required(rest, "--app"),
                    window: nil,
                    compact: rest.contains("--compact") ? true : nil
                ))
                print(out.yaml)

            case "menu":
                // pry-mcp menu --app <app> [--path "View > View Mode"]
                let pathArg = optional(rest, "--path") ?? ""
                let path = pathArg.isEmpty ? [] : pathArg.components(separatedBy: ">").map {
                    $0.trimmingCharacters(in: .whitespaces)
                }
                let out = try await PryTools.menuInspect(.init(
                    app: required(rest, "--app"),
                    path: path
                ))
                if rest.contains("--json") {
                    print(try jsonPretty(out))
                } else {
                    print("Path: \(out.path.joined(separator: " > "))")
                    print("Children (\(out.children.count)):")
                    for c in out.children { print("  - \(c)") }
                }

            case "focus":
                let out = try await PryTools.focusDump(.init(app: required(rest, "--app")))
                print(try jsonPretty(out))

            case "find":
                let target = try parseTargetArgs(rest)
                let out = try await PryTools.find(.init(app: required(rest, "--app"), target: target))
                print(try jsonPretty(out))

            case "snapshot":
                let out = try await PryTools.snapshot(.init(app: required(rest, "--app"),
                                                             path: optional(rest, "--out")))
                print(try jsonPretty(out))

            case "drag":
                // CLI form: pry-mcp drag --app <app> --from-id <id> --to-id <id>
                var from = PryTools.TargetSpec()
                from.id = optional(rest, "--from-id")
                from.label = optional(rest, "--from-label")
                var to = PryTools.TargetSpec()
                to.id = optional(rest, "--to-id")
                to.label = optional(rest, "--to-label")
                let steps = optional(rest, "--steps").flatMap(Int.init)
                let out = try await PryTools.drag(.init(
                    app: required(rest, "--app"), from: from, to: to, steps: steps
                ))
                print(try jsonPretty(out))

            case "scroll":
                let target = try parseTargetArgs(rest)
                let direction = optional(rest, "--direction") ?? "down"
                let amount = optional(rest, "--amount").flatMap(Int.init)
                let out = try await PryTools.scroll(.init(
                    app: required(rest, "--app"), target: target,
                    direction: direction, amount: amount
                ))
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
                    verdicts_dir: optional(rest, "--verdicts-dir"),
                    parallel: optional(rest, "--parallel").flatMap(Int.init),
                    retry_failed: optional(rest, "--retry-failed").flatMap(Int.init),
                    junit: optional(rest, "--junit"),
                    tap: optional(rest, "--tap"),
                    summary_md: optional(rest, "--summary-md")
                ))
                print(try jsonPretty(out))
                return out.failed == 0 && out.errored == 0 ? 0 : 1

            case "watch":
                // Naive watch: poll every 1.5s for mtime changes under --dir,
                // re-run the suite on change. Useful for local TDD.
                let dir = try required(rest, "--dir")
                FileHandle.standardError.write(Data("[pry] watching \(dir)\n".utf8))
                var lastFingerprint = ""
                while true {
                    let fp = directoryFingerprint(dir)
                    if fp != lastFingerprint {
                        if !lastFingerprint.isEmpty {
                            FileHandle.standardError.write(Data("[pry] change detected, running suite...\n".utf8))
                            let out = try await PryTools.runSuite(.init(
                                path: dir, tag: optional(rest, "--tag"),
                                verdicts_dir: optional(rest, "--verdicts-dir"),
                                parallel: optional(rest, "--parallel").flatMap(Int.init),
                                retry_failed: nil, junit: nil, tap: nil, summary_md: nil
                            ))
                            print(try jsonPretty(out))
                        }
                        lastFingerprint = fp
                    }
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                }

            case "list-specs":
                let out = try await PryTools.listSpecs(.init(path: required(rest, "--dir")))
                print(try jsonPretty(out))

            case "lint":
                let out = try await PryTools.lint(.init(
                    path: required(rest, "--dir"),
                    verbose: rest.contains("--verbose") ? true : nil
                ))
                if rest.contains("--json") {
                    print(try jsonPretty(out))
                } else {
                    if out.failed == 0 {
                        FileHandle.standardError.write(Data("\(out.ok)/\(out.total) specs OK\n".utf8))
                    } else {
                        FileHandle.standardError.write(Data("\(out.failed)/\(out.total) specs FAILED:\n\n".utf8))
                        for issue in out.issues {
                            let lineStr = issue.line.map { ":\($0)" } ?? ""
                            print("\(issue.spec)\(lineStr): \(issue.kind): \(issue.message)")
                        }
                    }
                }
                return out.failed == 0 ? 0 : 1

            case "init":
                let out = try await PryTools.initConfig(.init(
                    bundleID: try required(rest, "--bundle-id"),
                    product: try required(rest, "--product"),
                    directory: optional(rest, "--directory"),
                    force: rest.contains("--force") ? true : nil
                ))
                if out.written {
                    FileHandle.standardError.write(Data("Wrote \(out.configPath)\n".utf8))
                } else {
                    FileHandle.standardError.write(Data("\(out.configPath) already maps that bundle (use --force to override)\n".utf8))
                }
                print(out.contents)

            case "report":
                // pry-mcp report --build <verdicts-dir> [--out <html-file>]
                let dir = try required(rest, "--build")
                let outFile = optional(rest, "--out") ?? "\(dir)/index.html"
                let html = try generateVerdictsReport(dir: dir)
                try html.write(toFile: outFile, atomically: true, encoding: .utf8)
                FileHandle.standardError.write(Data("Wrote \(outFile)\n".utf8))

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

    /// Build a self-contained HTML dashboard from a verdicts directory.
    /// Each subdirectory of the form `<spec-id>-<timestamp>/` becomes one
    /// row in a table; the verdict.md is inlined and any PNG attachments are
    /// base64-embedded so the resulting file works without a web server.
    private static func generateVerdictsReport(dir: String) throws -> String {
        let url = URL(fileURLWithPath: dir).standardizedFileURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw NSError(domain: "PryReport", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "no such directory: \(url.path)"])
        }
        var rows: [(spec: String, status: String, when: String, html: String)] = []

        let entries = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
        for entry in entries.sorted(by: { $0.lastPathComponent > $1.lastPathComponent }) {
            let verdictMd = entry.appendingPathComponent("verdict.md")
            guard let body = try? String(contentsOf: verdictMd, encoding: .utf8) else { continue }
            let (status, specID, finishedAt) = parseVerdictFrontmatter(body)
            // Convert markdown to a minimal HTML — for v1 we keep it as <pre>
            // wrapped in a details/summary so the report stays compact.
            // Inline images by replacing PNG attachment refs with base64.
            var inlined = body
            for imgURL in (try? FileManager.default.contentsOfDirectory(at: entry, includingPropertiesForKeys: nil)) ?? [] {
                guard imgURL.pathExtension.lowercased() == "png",
                      let data = try? Data(contentsOf: imgURL) else { continue }
                let b64 = data.base64EncodedString()
                let mention = imgURL.lastPathComponent
                inlined = inlined.replacingOccurrences(
                    of: "- `\(imgURL.path)`",
                    with: "- `\(imgURL.path)`\n\n  ![\(mention)](data:image/png;base64,\(b64))\n"
                )
            }
            let escaped = inlined
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
            let detailHTML = "<pre style=\"white-space: pre-wrap;\">\(escaped)</pre>"
            rows.append((spec: specID, status: status, when: finishedAt, html: detailHTML))
        }

        var out = """
        <!DOCTYPE html>
        <html lang="en">
        <head>
          <meta charset="UTF-8">
          <title>Pry verdicts</title>
          <style>
            body { font-family: -apple-system, system-ui, sans-serif; margin: 2em auto; max-width: 1100px; padding: 0 1em; color: #1d1d1f; }
            h1 { margin-bottom: 0.2em; }
            .summary { color: #6e6e73; margin-bottom: 1.5em; }
            table { border-collapse: collapse; width: 100%; margin-bottom: 1em; }
            th, td { padding: 0.5em 0.7em; border-bottom: 1px solid #e0e0e0; text-align: left; }
            th { background: #f5f5f7; font-weight: 600; }
            .pass { color: #1f9b3a; }
            .fail { color: #d80027; }
            .errored { color: #b97500; }
            details { margin-bottom: 1em; padding: 0.6em 0.9em; background: #f7f7f7; border-radius: 6px; }
            summary { cursor: pointer; font-weight: 500; }
            summary .meta { color: #6e6e73; font-weight: 400; margin-left: 0.6em; }
            pre { font-size: 12px; line-height: 1.5; }
            img { max-width: 100%; border: 1px solid #e0e0e0; border-radius: 4px; margin: 0.4em 0; }
          </style>
        </head>
        <body>
          <h1>Pry verdicts</h1>
        """
        let total = rows.count
        let passed = rows.filter { $0.status == "passed" }.count
        let failed = rows.filter { $0.status == "failed" }.count
        let errored = rows.filter { $0.status == "errored" || $0.status == "timed_out" }.count
        out += "  <div class=\"summary\"><b>\(passed)</b> passed · <b>\(failed)</b> failed · <b>\(errored)</b> errored — \(total) total runs</div>\n"

        for r in rows {
            let cls: String
            switch r.status {
            case "passed": cls = "pass"
            case "failed": cls = "fail"
            default: cls = "errored"
            }
            out += """
              <details>
                <summary><span class="\(cls)">\(r.status.uppercased())</span>
                <code>\(r.spec)</code><span class="meta">— \(r.when)</span></summary>
                \(r.html)
              </details>
            """
        }
        out += "</body></html>\n"
        return out
    }

    private static func parseVerdictFrontmatter(_ md: String) -> (status: String, specID: String, finishedAt: String) {
        var status = "?", specID = "?", finished = ""
        guard md.hasPrefix("---") else { return (status, specID, finished) }
        let lines = md.components(separatedBy: "\n")
        for line in lines.dropFirst() {
            if line.trimmingCharacters(in: .whitespaces) == "---" { break }
            if let colon = line.firstIndex(of: ":") {
                let k = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
                let v = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                if k == "status" { status = v }
                if k == "id" { specID = v }
                if k == "finished_at" { finished = v }
            }
        }
        return (status, specID, finished)
    }

    private static func directoryFingerprint(_ path: String) -> String {
        var fp = ""
        let url = URL(fileURLWithPath: path)
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.contentModificationDateKey]) else { return "" }
        var entries: [(String, TimeInterval)] = []
        while let item = enumerator.nextObject() as? URL {
            guard item.pathExtension.lowercased() == "md" else { continue }
            if let attrs = try? item.resourceValues(forKeys: [.contentModificationDateKey]),
               let mod = attrs.contentModificationDate {
                entries.append((item.path, mod.timeIntervalSinceReferenceDate))
            }
        }
        entries.sort { $0.0 < $1.0 }
        for (p, t) in entries { fp += "\(p):\(t);" }
        return fp
    }

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
