import SwiftUI
import AppKit
import Foundation

@main
struct DemoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var vm = DocumentListVM()

    var body: some Scene {
        WindowGroup("DemoApp") {
            ContentView()
                .environmentObject(vm)
                .frame(minWidth: 480, minHeight: 320)
        }
        .windowResizability(.contentSize)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@MainActor
final class DocumentListVM: ObservableObject {
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

    func createDocument() {
        clickCount += 1
        let name = draftName.isEmpty ? "Untitled \(documents.count + 1)" : draftName
        documents.append(name)
        draftName = ""
        SpikeMarker.write(event: "button_clicked", payload: ["clickCount": clickCount, "docsCount": documents.count])
    }

    func tapZone() {
        zoneTapCount += 1
        SpikeMarker.write(event: "zone_tapped", payload: ["count": zoneTapCount])
    }
}

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

enum SpikeMarker {
    static func write(event: String, payload: [String: Any] = [:]) {
        guard let path = ProcessInfo.processInfo.environment["PRY_MARKER_FILE"] else { return }
        let ts = ISO8601DateFormatter().string(from: Date())
        var line = "\(ts) \(event)"
        for (k, v) in payload.sorted(by: { $0.key < $1.key }) {
            line += " \(k)=\(v)"
        }
        line += "\n"
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
