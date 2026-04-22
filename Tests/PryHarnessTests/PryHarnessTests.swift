import XCTest
@testable import PryHarness

@MainActor
final class FakeVM: PryInspectable {
    static var pryName: String { "FakeVM" }
    var count: Int = 0
    func prySnapshot() -> [String: any Sendable] {
        ["count": count, "label": "hello"]
    }
}

@MainActor
final class PryRegistryTests: XCTestCase {
    func testRegisterAndSnapshot() {
        PryRegistry.shared.unregister(name: "FakeVM")
        let vm = FakeVM()
        vm.count = 7
        PryRegistry.shared.register(vm)

        let snap = PryRegistry.shared.snapshot(of: "FakeVM")
        XCTAssertNotNil(snap)
        XCTAssertEqual(snap?["count"] as? Int, 7)
        XCTAssertEqual(snap?["label"] as? String, "hello")

        XCTAssertTrue(PryRegistry.shared.registeredNames().contains("FakeVM"))
    }

    func testSnapshotReflectsMutation() {
        PryRegistry.shared.unregister(name: "FakeVM")
        let vm = FakeVM()
        PryRegistry.shared.register(vm)

        vm.count = 1
        XCTAssertEqual(PryRegistry.shared.snapshot(of: "FakeVM")?["count"] as? Int, 1)
        vm.count = 99
        XCTAssertEqual(PryRegistry.shared.snapshot(of: "FakeVM")?["count"] as? Int, 99)
    }

    func testUnknownVMReturnsNil() {
        XCTAssertNil(PryRegistry.shared.snapshot(of: "NotRegisteredVM"))
    }

    func testSocketPathConvention() {
        XCTAssertEqual(PryHarness.socketPath(for: "fr.neimad.foo"), "/tmp/pry-fr.neimad.foo.sock")
    }
}
