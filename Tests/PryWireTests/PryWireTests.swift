import XCTest
@testable import PryWire

final class PryWireTests: XCTestCase {
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()

    func testHelloRoundTrip() throws {
        let req = PryWire.Request(id: 1, method: "hello", params: PryWire.HelloParams(client: "pry-mcp", version: "0.1.0"))
        let data = try encoder.encode(req)
        let back = try decoder.decode(PryWire.Request<PryWire.HelloParams>.self, from: data)
        XCTAssertEqual(back.id, 1)
        XCTAssertEqual(back.method, "hello")
        XCTAssertEqual(back.params.client, "pry-mcp")
    }

    func testHelloResultSnakeCase() throws {
        let result = PryWire.HelloResult(harnessVersion: "0.1.0", appBundle: "fr.neimad.test", pid: 42)
        let data = try encoder.encode(result)
        let json = String(data: data, encoding: .utf8)!
        XCTAssertTrue(json.contains("\"harness_version\""))
        XCTAssertTrue(json.contains("\"app_bundle\""))
        XCTAssertTrue(json.contains("\"pid\":42"))
    }

    func testReadStateWithPathResult() throws {
        let result = PryWire.ReadStateResult(value: PryWire.AnyCodable(42))
        let data = try encoder.encode(result)
        let back = try decoder.decode(PryWire.ReadStateResult.self, from: data)
        XCTAssertNotNil(back.value)
        XCTAssertNil(back.keys)
        XCTAssertEqual(back.value?.value as? Int, 42)
    }

    func testReadStateKeysResult() throws {
        let result = PryWire.ReadStateResult(keys: [
            "documents.count": PryWire.AnyCodable(1),
            "verbose": PryWire.AnyCodable(false),
        ])
        let data = try encoder.encode(result)
        let back = try decoder.decode(PryWire.ReadStateResult.self, from: data)
        XCTAssertNil(back.value)
        XCTAssertEqual(back.keys?["documents.count"]?.value as? Int, 1)
        XCTAssertEqual(back.keys?["verbose"]?.value as? Bool, false)
    }

    func testErrorCodes() {
        // Sanity: the well-known codes are distinct and in the custom-negative range.
        let all = [
            PryWire.RPCError.viewmodelNotRegistered,
            PryWire.RPCError.pathNotFound,
            PryWire.RPCError.windowNotFound,
            PryWire.RPCError.snapshotFailed,
            PryWire.RPCError.logStoreUnavailable,
        ]
        XCTAssertEqual(Set(all).count, all.count)
        XCTAssertTrue(all.allSatisfy { $0 <= -32001 && $0 >= -32099 })
    }

    func testAnyCodableScalars() throws {
        let cases: [any Sendable] = [1, 3.14, true, "hello"]
        for c in cases {
            let data = try encoder.encode(PryWire.AnyCodable(c))
            let back = try decoder.decode(PryWire.AnyCodable.self, from: data)
            // We don't compare values directly (lossy via Sendable erasure) — just
            // verify round-trip emits valid JSON.
            XCTAssertFalse(data.isEmpty)
            XCTAssertNotNil(back.value)
        }
    }

    func testMethodCatalog() {
        XCTAssertEqual(PryWire.Method.hello.rawValue, "hello")
        XCTAssertEqual(PryWire.Method.readState.rawValue, "read_state")
        XCTAssertEqual(PryWire.Method.inspectTree.rawValue, "inspect_tree")
    }
}
