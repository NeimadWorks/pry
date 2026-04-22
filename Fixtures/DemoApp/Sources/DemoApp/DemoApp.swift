import SwiftUI
import AppKit
import Foundation
import OSLog
import PryHarness

@main
struct DemoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var vm = DocumentListVM()

    var body: some Scene {
        WindowGroup("DemoApp") {
            ContentView()
                .environmentObject(vm)
                .frame(minWidth: 480, minHeight: 320)
                .task {
                    PryRegistry.shared.register(vm)
                    // Spike-support marker so spike05 can observe that registration happened.
                    SpikeMarker.writeJSON(event: "pry_registered", object: [
                        "viewmodel": type(of: vm).pryName,
                        "keys": Array(vm.prySnapshot().keys).sorted(),
                    ])
                }
        }
        .windowResizability(.contentSize)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        // Start the real PryHarness. #if DEBUG-gated in a real app; here DemoApp
        // is always a fixture, so start unconditionally.
        PryHarness.start(bundleID: "fr.neimad.pry.demoapp")

        if ProcessInfo.processInfo.environment["PRY_SPIKE_LOG_LATENCY"] == "1" {
            Task.detached(priority: .userInitiated) {
                await LogLatencyHarness.run()
            }
        }
    }
}

// MARK: - VM

@MainActor
final class DocumentListVM: ObservableObject, PryInspectable {
    static var pryName: String { "DocumentListVM" }

    @Published var documents: [String] = []
    @Published var draftName: String = ""
    @Published var clickCount: Int = 0
    @Published var zoneTapCount: Int = 0
    @Published var verbose: Bool = false {
        didSet {
            guard oldValue != verbose else { return }
            SpikeMarker.write(event: "toggle_changed", payload: ["verbose": verbose])
        }
    }

    func prySnapshot() -> [String: any Sendable] {
        [
            "documents.count": documents.count,
            "draftName": draftName,
            "clickCount": clickCount,
            "zoneTapCount": zoneTapCount,
            "verbose": verbose,
        ]
    }

    func createDocument() {
        clickCount += 1
        let name = draftName.isEmpty ? "Untitled \(documents.count + 1)" : draftName
        documents.append(name)
        draftName = ""
        SpikeMarker.write(event: "button_clicked", payload: ["clickCount": clickCount, "docsCount": documents.count])
        SpikeMarker.writeJSON(event: "state_snapshot", object: [
            "viewmodel": Self.pryName,
            "keys": snapshotAsJSON(),
        ])
    }

    func tapZone() {
        zoneTapCount += 1
        SpikeMarker.write(event: "zone_tapped", payload: ["count": zoneTapCount])
    }

    /// Returns the snapshot with values coerced to JSON-representable types.
    private func snapshotAsJSON() -> [String: Any] {
        var out: [String: Any] = [:]
        for (k, v) in prySnapshot() {
            switch v {
            case let x as Int:    out[k] = x
            case let x as Bool:   out[k] = x
            case let x as String: out[k] = x
            case let x as Double: out[k] = x
            default:              out[k] = String(describing: v)
            }
        }
        return out
    }
}

// MARK: - Content

struct ContentView: View {
    @EnvironmentObject var vm: DocumentListVM

    var body: some View {
        VStack(spacing: 12) {
            Text("DemoApp").font(.largeTitle)

            HStack {
                TextField("Document name", text: $vm.draftName)
                    .accessibilityIdentifier("doc_name_field")
                    .textFieldStyle(.roundedBorder)

                Button("New Document") {
                    vm.createDocument()
                }
                .accessibilityIdentifier("new_doc_button")
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal)

            Toggle("Verbose", isOn: $vm.verbose)
                .accessibilityIdentifier("verbose_toggle")
                .padding(.horizontal)

            Rectangle()
                .fill(Color.blue.opacity(0.15))
                .frame(height: 32)
                .overlay(Text("Tap zone (\(vm.zoneTapCount))").font(.caption))
                .accessibilityIdentifier("tap_zone")
                .accessibilityAddTraits(.isButton)
                .contentShape(Rectangle())
                .onTapGesture { vm.tapZone() }
                .padding(.horizontal)

            List(vm.documents, id: \.self) { name in
                Text(name).accessibilityIdentifier("doc_row")
            }
            .accessibilityIdentifier("doc_list")

            Text("Clicks: \(vm.clickCount)")
                .accessibilityIdentifier("click_counter")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

// MARK: - OSLog latency harness (Spike 4)

enum LogLatencyHarness {
    static let subsystem = "fr.neimad.pry.demoapp"
    static let category = "spike4"
    static let iterations = 10
    static let perIterationTimeout: TimeInterval = 2.0

    static func run() async {
        let logger = Logger(subsystem: subsystem, category: category)
        SpikeMarker.write(event: "log_latency_start", payload: ["iterations": iterations])

        let store: OSLogStore
        do {
            store = try OSLogStore(scope: .currentProcessIdentifier)
        } catch {
            SpikeMarker.write(event: "log_latency_error", payload: ["stage": "open_store", "error": String(describing: error)])
            return
        }

        struct Sample {
            let latencyMs: Double        // t0 → tag visible in store
            let positionMs: Double       // cost of store.position(...) call
            let pollCount: Int           // getEntries() iterations until found
            let firstGetEntriesMs: Double // cost of the very first getEntries call
            let timedOut: Bool
        }
        var samples: [Sample] = []

        for i in 0..<iterations {
            let tag = "spike4-\(i)-\(UUID().uuidString)"

            // Measure cost of position() separately. Move it OUTSIDE the t0 window so its
            // cost does not inflate the reported latency — prior revision had this bug.
            let posStart = Date()
            let priorPos = store.position(timeIntervalSinceEnd: -0.05)
            let positionMs = Date().timeIntervalSince(posStart) * 1000

            let t0 = Date()
            logger.info("\(tag, privacy: .public)")
            let result = await pollForTag(tag, in: store, from: priorPos, timeout: perIterationTimeout)

            let latencyMs = (result.seen ?? Date()).timeIntervalSince(t0) * 1000
            samples.append(Sample(
                latencyMs: result.seen == nil ? perIterationTimeout * 1000 : latencyMs,
                positionMs: positionMs,
                pollCount: result.pollCount,
                firstGetEntriesMs: result.firstGetEntriesMs,
                timedOut: result.seen == nil
            ))

            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms between iterations
        }

        let latencies = samples.map(\.latencyMs)
        let sorted = latencies.sorted()
        let p50 = sorted[sorted.count / 2]
        let p95Index = min(sorted.count - 1, Int(Double(sorted.count) * 0.95))
        let p95 = sorted[p95Index]
        let maxV = sorted.last ?? 0

        SpikeMarker.writeJSON(event: "log_latency_complete", object: [
            "iterations": iterations,
            "timeouts": samples.filter(\.timedOut).count,
            "p50_ms": p50,
            "p95_ms": p95,
            "max_ms": maxV,
            "samples_ms": latencies,
            "position_ms": samples.map(\.positionMs),
            "first_get_entries_ms": samples.map(\.firstGetEntriesMs),
            "poll_count": samples.map(\.pollCount),
        ])

        try? await Task.sleep(nanoseconds: 200_000_000)
        await MainActor.run {
            NSApp.terminate(nil)
        }
    }

    struct PollResult {
        let seen: Date?
        let pollCount: Int
        let firstGetEntriesMs: Double
    }

    /// Polls the OSLogStore for an entry containing `tag`. Reports observation time,
    /// number of polls, and cost of the first getEntries call (for diagnostics).
    private static func pollForTag(_ tag: String, in store: OSLogStore, from position: OSLogPosition, timeout: TimeInterval) async -> PollResult {
        let deadline = Date().addingTimeInterval(timeout)
        let predicate = NSPredicate(format: "subsystem == %@ AND category == %@", subsystem, category)
        var pollCount = 0
        var firstGetEntriesMs: Double = 0
        while Date() < deadline {
            pollCount += 1
            let callStart = Date()
            do {
                let entries = try store.getEntries(at: position, matching: predicate)
                let callDurMs = Date().timeIntervalSince(callStart) * 1000
                if pollCount == 1 { firstGetEntriesMs = callDurMs }
                for entry in entries {
                    guard let logEntry = entry as? OSLogEntryLog else { continue }
                    if logEntry.composedMessage.contains(tag) {
                        return PollResult(seen: Date(), pollCount: pollCount, firstGetEntriesMs: firstGetEntriesMs)
                    }
                }
            } catch {
                // Continue polling; transient store errors are tolerable for the measurement.
            }
            try? await Task.sleep(nanoseconds: 5_000_000) // 5ms
        }
        return PollResult(seen: nil, pollCount: pollCount, firstGetEntriesMs: firstGetEntriesMs)
    }
}

// MARK: - Marker IO

enum SpikeMarker {
    static func write(event: String, payload: [String: Any] = [:]) {
        let ts = ISO8601DateFormatter().string(from: Date())
        var line = "\(ts) \(event)"
        for (k, v) in payload.sorted(by: { $0.key < $1.key }) {
            line += " \(k)=\(v)"
        }
        line += "\n"
        append(line)
    }

    static func writeJSON(event: String, object: [String: Any]) {
        let ts = ISO8601DateFormatter().string(from: Date())
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
        let json = String(data: data, encoding: .utf8) ?? "{}"
        append("\(ts) \(event) \(json)\n")
    }

    private static func append(_ line: String) {
        guard let path = ProcessInfo.processInfo.environment["PRY_MARKER_FILE"] else { return }
        guard let data = line.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: path),
           let handle = try? FileHandle(forWritingTo: URL(fileURLWithPath: path)) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: URL(fileURLWithPath: path))
        }
    }
}
