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

        case "pry_right_click":
            let input = try decoder.decode(PryTools.RightClickInput.self, from: arguments)
            return try jsonString(try await PryTools.rightClick(input))

        case "pry_activate":
            let input = try decoder.decode(PryTools.ActivateInput.self, from: arguments)
            return try jsonString(try await PryTools.activate(input))

        case "pry_type":
            let input = try decoder.decode(PryTools.TypeInput.self, from: arguments)
            let out = try await PryTools.typeText(input)
            return try jsonString(out)

        case "pry_key":
            let input = try decoder.decode(PryTools.KeyInput.self, from: arguments)
            let out = try await PryTools.key(input)
            return try jsonString(out)

        case "pry_tree":
            let input = try decoder.decode(PryTools.TreeInput.self, from: arguments)
            let out = try await PryTools.tree(input)
            return try jsonString(out)

        case "pry_find":
            let input = try decoder.decode(PryTools.FindInput.self, from: arguments)
            let out = try await PryTools.find(input)
            return try jsonString(out)

        case "pry_snapshot":
            let input = try decoder.decode(PryTools.SnapshotInput.self, from: arguments)
            let out = try await PryTools.snapshot(input)
            return try jsonString(out)

        case "pry_run_spec":
            let input = try decoder.decode(PryTools.RunSpecInput.self, from: arguments)
            let out = try await PryTools.runSpec(input)
            return try jsonString(out)

        case "pry_run_suite":
            let input = try decoder.decode(PryTools.RunSuiteInput.self, from: arguments)
            let out = try await PryTools.runSuite(input)
            return try jsonString(out)

        case "pry_list_specs":
            let input = try decoder.decode(PryTools.ListSpecsInput.self, from: arguments)
            let out = try await PryTools.listSpecs(input)
            return try jsonString(out)

        case "pry_lint":
            let input = try decoder.decode(PryTools.LintInput.self, from: arguments)
            return try jsonString(try await PryTools.lint(input))
        case "pry_init":
            let input = try decoder.decode(PryTools.InitInput.self, from: arguments)
            return try jsonString(try await PryTools.initConfig(input))

        case "pry_menu_inspect":
            let input = try decoder.decode(PryTools.MenuInspectInput.self, from: arguments)
            return try jsonString(try await PryTools.menuInspect(input))
        case "pry_focus":
            let input = try decoder.decode(PryTools.FocusInput.self, from: arguments)
            return try jsonString(try await PryTools.focusDump(input))

        case "pry_logs":
            let input = try decoder.decode(PryTools.LogsInput.self, from: arguments)
            let out = try await PryTools.logs(input)
            return try jsonString(out)

        case "pry_drag":
            let input = try decoder.decode(PryTools.DragInput.self, from: arguments)
            let out = try await PryTools.drag(input)
            return try jsonString(out)

        case "pry_scroll":
            let input = try decoder.decode(PryTools.ScrollInput.self, from: arguments)
            let out = try await PryTools.scroll(input)
            return try jsonString(out)

        case "pry_clock_get":
            let input = try decoder.decode(PryTools.ClockGetInput.self, from: arguments)
            return try jsonString(try await PryTools.clockGet(input))
        case "pry_clock_set":
            let input = try decoder.decode(PryTools.ClockSetInput.self, from: arguments)
            return try jsonString(try await PryTools.clockSet(input))
        case "pry_clock_advance":
            let input = try decoder.decode(PryTools.ClockAdvanceInput.self, from: arguments)
            return try jsonString(try await PryTools.clockAdvance(input))
        case "pry_set_animations":
            let input = try decoder.decode(PryTools.AnimationsInput.self, from: arguments)
            return try jsonString(try await PryTools.setAnimations(input))
        case "pry_pasteboard_read":
            let input = try decoder.decode(PryTools.PasteboardReadInput.self, from: arguments)
            return try jsonString(try await PryTools.pasteboardRead(input))
        case "pry_pasteboard_write":
            let input = try decoder.decode(PryTools.PasteboardWriteInput.self, from: arguments)
            return try jsonString(try await PryTools.pasteboardWrite(input))

        case "pry_long_press":
            let input = try decoder.decode(PryTools.LongPressInput.self, from: arguments)
            return try jsonString(try await PryTools.longPress(input))
        case "pry_magnify":
            let input = try decoder.decode(PryTools.MagnifyInput.self, from: arguments)
            return try jsonString(try await PryTools.magnify(input))
        case "pry_select_menu":
            let input = try decoder.decode(PryTools.SelectMenuInput.self, from: arguments)
            return try jsonString(try await PryTools.selectMenu(input))

        case "pry_open_file":
            let input = try decoder.decode(PryTools.OpenFileInput.self, from: arguments)
            return try jsonString(try await PryTools.openFile(input))
        case "pry_save_file":
            let input = try decoder.decode(PryTools.SaveFileInput.self, from: arguments)
            return try jsonString(try await PryTools.saveFile(input))
        case "pry_panel_accept":
            let input = try decoder.decode(PryTools.PanelAcceptInput.self, from: arguments)
            return try jsonString(try await PryTools.panelAccept(input))
        case "pry_panel_cancel":
            let input = try decoder.decode(PryTools.PanelCancelInput.self, from: arguments)
            return try jsonString(try await PryTools.panelCancel(input))

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
            "description": "Resolve a target AX element and click it. Default strategy `via: auto` performs an AXPress on AXButton targets (bypasses geometric hit-test, robust against SwiftUI Button(.plain) padding traps), otherwise injects a CGEvent left-click at the frame center. Override with `via: cgevent` to force the event path or `via: ax_press` to require it.",
            "inputSchema": objectSchema(required: ["app", "target"], properties: [
                "app": ["type": "string"],
                "target": targetSchema,
                "modifiers": ["type": "array", "items": ["type": "string", "enum": ["cmd", "shift", "opt", "ctrl", "fn"]]],
                "via": ["type": "string", "enum": ["auto", "ax_press", "cgevent"], "description": "Click strategy. Default `auto`."],
                "expect_state_change": ["type": ["object", "boolean"], "description": "If set, snapshot the named view-model before+after and fail with `state_unchanged` if nothing mutated. Catches SwiftUI shortcut/keyboardShortcut routing bugs that pass an AX click but never run the action handler. Provide `{ viewmodel: NAME }`."],
            ]),
        ],
        [
            "name": "pry_right_click",
            "description": "Resolve a target AX element and inject a right-click (mouseDown.right + mouseUp.right) at its center. Use this for context menus that only attach to right-button events; left-clicks won't open them.",
            "inputSchema": objectSchema(required: ["app", "target"], properties: [
                "app": ["type": "string"],
                "target": targetSchema,
                "modifiers": ["type": "array", "items": ["type": "string"]],
            ]),
        ],
        [
            "name": "pry_activate",
            "description": "Bring the target app to the foreground (NSRunningApplication.activate). Recovery hook for when another process steals focus mid-run — without an active app, CGEvents are dispatched to whatever is frontmost, not your target.",
            "inputSchema": objectSchema(required: ["app"], properties: [
                "app": ["type": "string"],
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
        [
            "name": "pry_tree",
            "description": "Dump the AX tree of the target app (optionally scoped to a window) as YAML.",
            "inputSchema": objectSchema(required: ["app"], properties: [
                "app": ["type": "string"],
                "window": ["type": "object", "properties": [
                    "title": ["type": "string"],
                    "title_matches": ["type": "string"],
                ]],
            ]),
        ],
        [
            "name": "pry_find",
            "description": "Resolve a target to zero, one, or many AX elements (returns all matches without the usual ambiguity check).",
            "inputSchema": objectSchema(required: ["app", "target"], properties: [
                "app": ["type": "string"],
                "target": targetSchema,
            ]),
        ],
        [
            "name": "pry_snapshot",
            "description": "Capture a PNG of the target app's front window.",
            "inputSchema": objectSchema(required: ["app"], properties: [
                "app": ["type": "string"],
                "path": ["type": "string", "description": "Optional absolute path. Defaults to a unique temp path."],
            ]),
        ],
        [
            "name": "pry_run_spec",
            "description": "Execute a Markdown test spec end-to-end and return a structured verdict. The primary entry point for driven runs.",
            "inputSchema": objectSchema(required: [], properties: [
                "path": ["type": "string", "description": "Filesystem path to a .md spec file. Use either `path` or `markdown`."],
                "markdown": ["type": "string", "description": "Inline spec content (alternative to path)."],
                "verdicts_dir": ["type": "string", "description": "Directory to write verdict.md and attachments into. Defaults to ./pry-verdicts."],
                "snapshots": ["type": "string", "enum": ["on_failure", "always"], "description": "When to save snapshot: steps to disk."],
            ]),
        ],
        [
            "name": "pry_run_suite",
            "description": "Execute every .md spec in a directory and aggregate results.",
            "inputSchema": objectSchema(required: ["path"], properties: [
                "path": ["type": "string"],
                "tag": ["type": "string", "description": "Only run specs whose frontmatter `tags` include this tag."],
                "verdicts_dir": ["type": "string"],
            ]),
        ],
        [
            "name": "pry_list_specs",
            "description": "Discover .md spec files under a directory.",
            "inputSchema": objectSchema(required: ["path"], properties: [
                "path": ["type": "string"],
            ]),
        ],
        [
            "name": "pry_logs",
            "description": "Read OSLog lines from the target app. Best-effort ~1s latency — useful for post-hoc diagnostics, not race-sensitive assertions (ADR-006).",
            "inputSchema": objectSchema(required: ["app"], properties: [
                "app": ["type": "string"],
                "since": ["type": "string", "description": "ISO 8601 timestamp."],
                "subsystem": ["type": "string"],
            ]),
        ],
        [
            "name": "pry_drag",
            "description": "Drag from the center of one resolved target to the center of another. Real CGEvent sequence (mouseDown + interpolated drags + mouseUp).",
            "inputSchema": objectSchema(required: ["app", "from", "to"], properties: [
                "app": ["type": "string"],
                "from": targetSchema,
                "to": targetSchema,
                "steps": ["type": "integer", "description": "Number of intermediate mouseDragged events. Default 12."],
            ]),
        ],
        [
            "name": "pry_scroll",
            "description": "Scroll wheel events at the center of a resolved target.",
            "inputSchema": objectSchema(required: ["app", "target", "direction"], properties: [
                "app": ["type": "string"],
                "target": targetSchema,
                "direction": ["type": "string", "enum": ["up", "down", "left", "right"]],
                "amount": ["type": "integer", "description": "Number of line units. Default 3."],
            ]),
        ],
        [
            "name": "pry_clock_advance",
            "description": "Advance the harness virtual clock by N seconds, firing all scheduled work whose deadline falls within the window. Requires the app to use PryClock for its time-dependent logic. (ADR-007)",
            "inputSchema": objectSchema(required: ["app", "seconds"], properties: [
                "app": ["type": "string"],
                "seconds": ["type": "number"],
            ]),
        ],
        [
            "name": "pry_clock_set",
            "description": "Set the virtual clock to an absolute ISO 8601 timestamp.",
            "inputSchema": objectSchema(required: ["app", "iso8601"], properties: [
                "app": ["type": "string"],
                "iso8601": ["type": "string"],
                "paused": ["type": "boolean"],
            ]),
        ],
        [
            "name": "pry_clock_get",
            "description": "Read the virtual clock.",
            "inputSchema": objectSchema(required: ["app"], properties: ["app": ["type": "string"]]),
        ],
        [
            "name": "pry_set_animations",
            "description": "Enable or disable app-wide animations. Use `enabled: false` for deterministic snapshots and to remove transition flake. (ADR-009)",
            "inputSchema": objectSchema(required: ["app", "enabled"], properties: [
                "app": ["type": "string"],
                "enabled": ["type": "boolean"],
            ]),
        ],
        [
            "name": "pry_pasteboard_read",
            "description": "Read the system pasteboard via the harness.",
            "inputSchema": objectSchema(required: ["app"], properties: ["app": ["type": "string"]]),
        ],
        [
            "name": "pry_pasteboard_write",
            "description": "Write a string to the system pasteboard via the harness.",
            "inputSchema": objectSchema(required: ["app", "string"], properties: [
                "app": ["type": "string"],
                "string": ["type": "string"],
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
