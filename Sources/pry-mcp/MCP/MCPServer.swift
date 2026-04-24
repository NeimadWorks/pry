import Foundation
import PryWire

/// Minimal stdio JSON-RPC 2.0 server that implements the subset of the Model
/// Context Protocol we need: `initialize`, `tools/list`, `tools/call`.
///
/// Transport: one JSON document per line on stdin/stdout. `stderr` is reserved
/// for logs.
actor MCPServer {
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.withoutEscapingSlashes]
        return e
    }()
    private let decoder = JSONDecoder()

    func run() async {
        logStderr("pry-mcp \(PryMCP.version) — stdio MCP server started, pid=\(getpid())")
        while let line = readLineFromStdin() {
            if line.isEmpty { continue }
            guard let data = line.data(using: .utf8) else { continue }
            await handleLine(data)
        }
        logStderr("pry-mcp — stdin closed, exiting")
    }

    // MARK: - Request handling

    private func handleLine(_ data: Data) async {
        guard let raw = try? decoder.decode(PryWire.RawRequest.self, from: data) else {
            // Could be a notification (no id) or malformed. Best-effort parse.
            if let notif = try? decoder.decode(MCPNotification.self, from: data) {
                logStderr("notification: \(notif.method)")
                return
            }
            writeError(id: 0, code: PryWire.RPCError.parseError, message: "invalid JSON-RPC")
            return
        }

        switch raw.method {
        case "initialize":
            handleInitialize(id: raw.id)
        case "notifications/initialized":
            return // no response to notifications
        case "tools/list":
            handleToolsList(id: raw.id)
        case "tools/call":
            await handleToolsCall(id: raw.id, params: raw.params)
        case "ping":
            writeRaw(id: raw.id, result: [:])
        default:
            writeError(id: raw.id, code: PryWire.RPCError.methodNotFound,
                       message: "unknown method: \(raw.method)")
        }
    }

    // MARK: - Standard MCP methods

    private func handleInitialize(id: Int) {
        let result: [String: Any] = [
            "protocolVersion": "2024-11-05",
            "serverInfo": [
                "name": "pry-mcp",
                "version": PryMCP.version,
            ],
            "capabilities": [
                "tools": [:] as [String: Any],
            ],
        ]
        writeRaw(id: id, result: result)
    }

    private func handleToolsList(id: Int) {
        writeRaw(id: id, result: ["tools": ToolCatalog.all])
    }

    private func handleToolsCall(id: Int, params: PryWire.AnyCodable) async {
        // params: { name: String, arguments: {...} }
        guard let obj = params.value as? [String: any Sendable],
              let name = obj["name"] as? String else {
            writeError(id: id, code: PryWire.RPCError.invalidParams,
                       message: "tools/call requires { name, arguments }")
            return
        }
        let argsValue = obj["arguments"] ?? [String: any Sendable]()
        let argsData: Data
        do {
            argsData = try encoder.encode(PryWire.AnyCodable(argsValue))
        } catch {
            writeError(id: id, code: PryWire.RPCError.invalidParams,
                       message: "could not encode arguments: \(error)")
            return
        }

        do {
            let text = try await dispatch(tool: name, arguments: argsData)
            let result: [String: Any] = [
                "content": [
                    ["type": "text", "text": text]
                ] as [Any]
            ]
            writeRaw(id: id, result: result)
        } catch let e as PryTools.ToolError {
            // Surface as MCP "isError" tool result with structured content.
            var errorDict: [String: Any] = [
                "kind": e.kind,
                "message": e.message,
            ]
            if let fix = e.fix { errorDict["fix"] = fix }

            let text: String
            if let data = try? JSONSerialization.data(withJSONObject: errorDict, options: [.prettyPrinted, .sortedKeys]),
               let s = String(data: data, encoding: .utf8) {
                text = s
            } else {
                text = "\(e.kind): \(e.message)"
            }
            let result: [String: Any] = [
                "content": [["type": "text", "text": text]] as [Any],
                "isError": true,
            ]
            writeRaw(id: id, result: result)
        } catch {
            writeError(id: id, code: PryWire.RPCError.internalError, message: "\(error)")
        }
    }

    // MARK: - Dispatch

    private func dispatch(tool: String, arguments: Data) async throws -> String {
        switch tool {
        case "pry_launch":
            let input = try decoder.decode(PryTools.LaunchInput.self, from: arguments)
            let out = try await PryTools.launch(input)
            return try jsonString(out)

        case "pry_terminate":
            let input = try decoder.decode(PryTools.TerminateInput.self, from: arguments)
            let out = try await PryTools.terminate(input)
            return try jsonString(out)

        case "pry_state":
            let input = try decoder.decode(PryTools.StateInput.self, from: arguments)
            let out = try await PryTools.state(input)
            return try jsonString(out)

        case "pry_click":
            let input = try decoder.decode(PryTools.ClickInput.self, from: arguments)
            let out = try await PryTools.click(input)
            return try jsonString(out)

        case "pry_type":
            let input = try decoder.decode(PryTools.TypeInput.self, from: arguments)
            let out = try await PryTools.typeText(input)
            return try jsonString(out)

        case "pry_key":
            let input = try decoder.decode(PryTools.KeyInput.self, from: arguments)
            let out = try await PryTools.key(input)
            return try jsonString(out)

        default:
            throw PryTools.ToolError.kinded(kind: "method_not_found", message: "no such tool: \(tool)")
        }
    }

    private func jsonString<T: Codable>(_ v: T) throws -> String {
        let data = try encoder.encode(v)
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    // MARK: - IO

    private func writeRaw(id: Int, result: Any) {
        var envelope: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id,
            "result": result,
        ]
        write(envelope: &envelope)
    }

    private func writeError(id: Int, code: Int, message: String) {
        var envelope: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id,
            "error": [
                "code": code,
                "message": message,
            ],
        ]
        write(envelope: &envelope)
    }

    private func write(envelope: inout [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: envelope, options: []),
              let s = String(data: data, encoding: .utf8) else { return }
        FileHandle.standardOutput.write(Data((s + "\n").utf8))
    }

    private func logStderr(_ s: String) {
        FileHandle.standardError.write(Data("[pry-mcp] \(s)\n".utf8))
    }
}

private func readLineFromStdin() -> String? {
    readLine(strippingNewline: true)
}

private struct MCPNotification: Codable {
    var jsonrpc: String
    var method: String
}

// MARK: - Tool catalog

enum ToolCatalog {
    static var all: [[String: Any]] { [
        [
            "name": "pry_launch",
            "description": "Launch the target macOS app and connect to its PryHarness socket.",
            "inputSchema": objectSchema(
                required: ["app"],
                properties: [
                    "app": ["type": "string", "description": "Bundle identifier of the target app."],
                    "executable_path": ["type": "string", "description": "Optional absolute path to a SwiftPM-built executable (used for fixtures like DemoApp that are not bundled .apps)."],
                    "args": ["type": "array", "items": ["type": "string"]],
                    "env": ["type": "object", "additionalProperties": ["type": "string"]],
                ]
            ),
        ],
        [
            "name": "pry_terminate",
            "description": "Send SIGTERM to the target app.",
            "inputSchema": objectSchema(required: ["app"], properties: [
                "app": ["type": "string"]
            ]),
        ],
        [
            "name": "pry_state",
            "description": "Read state from a registered ViewModel in the target app. Omit `path` to get the full snapshot.",
            "inputSchema": objectSchema(required: ["app", "viewmodel"], properties: [
                "app": ["type": "string"],
                "viewmodel": ["type": "string", "description": "The ViewModel's pryName (default: the Swift type name)."],
                "path": ["type": "string", "description": "Key of the value to return. Omit for full snapshot."],
            ]),
        ],
        [
            "name": "pry_click",
            "description": "Resolve a target AX element and inject a left-click at its center.",
            "inputSchema": objectSchema(required: ["app", "target"], properties: [
                "app": ["type": "string"],
                "target": targetSchema,
            ]),
        ],
        [
            "name": "pry_type",
            "description": "Type text into the currently focused element.",
            "inputSchema": objectSchema(required: ["app", "text"], properties: [
                "app": ["type": "string"],
                "text": ["type": "string"],
            ]),
        ],
        [
            "name": "pry_key",
            "description": "Post a keyboard shortcut (e.g. 'cmd+s', 'escape', 'return').",
            "inputSchema": objectSchema(required: ["app", "combo"], properties: [
                "app": ["type": "string"],
                "combo": ["type": "string"],
            ]),
        ],
    ] }

    private static func objectSchema(required: [String], properties: [String: Any]) -> [String: Any] {
        [
            "type": "object",
            "required": required,
            "properties": properties,
        ]
    }

    private static var targetSchema: [String: Any] { [
        "type": "object",
        "description": "AX target — provide exactly one of: id, role+label, label, label_matches, tree_path, point.",
        "properties": [
            "id": ["type": "string"],
            "role": ["type": "string"],
            "label": ["type": "string"],
            "label_matches": ["type": "string"],
            "tree_path": ["type": "string"],
            "point": ["type": "object", "properties": [
                "x": ["type": "number"], "y": ["type": "number"]
            ]],
        ],
    ] }
}
