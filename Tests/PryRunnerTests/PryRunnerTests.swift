import XCTest
@testable import PryRunner

/// These tests prove the library is usable end-to-end without going through
/// the MCP layer. The integration cases (live AX, real DemoApp) are gated by
/// `PRY_INTEGRATION=1` because GitHub runners don't have Accessibility
/// permission. Default `swift test` runs only pure parser/render checks.

final class SpecParserTests: XCTestCase {

    func testParseMinimalSpec() throws {
        let src = """
        ---
        id: hello
        app: fr.neimad.demo
        ---

        # Hello

        ```pry
        launch
        click: { id: "go" }
        ```
        """
        let spec = try SpecParser.parse(source: src)
        XCTAssertEqual(spec.id, "hello")
        XCTAssertEqual(spec.app, "fr.neimad.demo")
        XCTAssertEqual(spec.steps.count, 2)
        if case .launch(let args, let env) = spec.steps[0] {
            XCTAssertTrue(args.isEmpty); XCTAssertTrue(env.isEmpty)
        } else { XCTFail("step 0 not launch") }
        if case .click(let target, _) = spec.steps[1], case .id(let s) = target {
            XCTAssertEqual(s, "go")
        } else { XCTFail("step 1 not click(id:go)") }
    }

    func testParseFrontmatterTags() throws {
        let src = """
        ---
        id: tagged
        app: fr.neimad.demo
        tags: [smoke, regression]
        timeout: 10s
        ---

        ```pry
        launch
        ```
        """
        let spec = try SpecParser.parse(source: src)
        XCTAssertEqual(spec.tags, ["smoke", "regression"])
        XCTAssertEqual(spec.timeout.seconds, 10)
    }

    func testParseAssertStateMultiform() throws {
        let src = """
        ---
        id: t
        app: x
        ---

        ```pry
        assert_state: { viewmodel: BoardVM, path: "ply", equals: 5 }
        assert_state: { viewmodel: BoardVM, path: "fen", matches: ".*Q.*" }
        assert_state: { viewmodel: BoardVM, path: "result", any_of: ["1-0", "0-1", "1/2-1/2"] }
        ```
        """
        let spec = try SpecParser.parse(source: src)
        XCTAssertEqual(spec.steps.count, 3)
        if case .assertState(_, _, let e) = spec.steps[0], case .equals(let v) = e {
            XCTAssertEqual(v.asInt, 5)
        } else { XCTFail("step 0 not equals") }
        if case .assertState(_, _, let e) = spec.steps[1], case .matches(let p) = e {
            XCTAssertEqual(p, ".*Q.*")
        } else { XCTFail("step 1 not matches") }
        if case .assertState(_, _, let e) = spec.steps[2], case .anyOf(let arr) = e {
            XCTAssertEqual(arr.count, 3)
        } else { XCTFail("step 2 not any_of") }
    }

    func testParseDragAndScroll() throws {
        let src = """
        ---
        id: t
        app: x
        ---

        ```pry
        drag: { from: { id: "a" }, to: { id: "b" }, steps: 20 }
        scroll: { target: { id: "list" }, direction: down, amount: 5 }
        ```
        """
        let spec = try SpecParser.parse(source: src)
        XCTAssertEqual(spec.steps.count, 2)
        if case .drag(_, _, let n, _) = spec.steps[0] { XCTAssertEqual(n, 20) }
        else { XCTFail("step 0 not drag") }
        if case .scroll(_, let dir, let amt) = spec.steps[1] {
            XCTAssertEqual(dir, .down)
            XCTAssertEqual(amt, 5)
        } else { XCTFail("step 1 not scroll") }
    }

    func testParseNumericComparators() throws {
        let src = """
        ---
        id: t
        app: x
        ---

        ```pry
        assert_state: { viewmodel: VM, path: n, gt: 0 }
        assert_state: { viewmodel: VM, path: n, gte: 1 }
        assert_state: { viewmodel: VM, path: n, lt: 100 }
        assert_state: { viewmodel: VM, path: n, lte: 99 }
        assert_state: { viewmodel: VM, path: n, between: [10, 20] }
        ```
        """
        let spec = try SpecParser.parse(source: src)
        XCTAssertEqual(spec.steps.count, 5)
        if case .assertState(_, _, let e) = spec.steps[0], case .gt(let v) = e { XCTAssertEqual(v, 0) }
        else { XCTFail("not gt") }
        if case .assertState(_, _, let e) = spec.steps[1], case .gte(let v) = e { XCTAssertEqual(v, 1) }
        else { XCTFail("not gte") }
        if case .assertState(_, _, let e) = spec.steps[4], case .between(let lo, let hi) = e {
            XCTAssertEqual(lo, 10); XCTAssertEqual(hi, 20)
        } else { XCTFail("not between") }
    }

    func testParseNthSelector() throws {
        let src = """
        ---
        id: t
        app: x
        ---

        ```pry
        click: { id: "row", nth: 2 }
        ```
        """
        let spec = try SpecParser.parse(source: src)
        if case .click(let target, _) = spec.steps[0],
           case .nth(let base, let i) = target,
           case .id(let s) = base {
            XCTAssertEqual(s, "row")
            XCTAssertEqual(i, 2)
        } else { XCTFail("not nth-wrapped click") }
    }

    func testParseCountWithNumOp() throws {
        let src = """
        ---
        id: t
        app: x
        ---

        ```pry
        assert_tree: { count: { of: { id: "row" }, gte: 1 } }
        ```
        """
        let spec = try SpecParser.parse(source: src)
        if case .assertTree(let p) = spec.steps[0],
           case .countOf(_, let op) = p,
           case .gte(let n) = op {
            XCTAssertEqual(n, 1)
        } else { XCTFail("not count gte") }
    }

    func testParseSoftAssert() throws {
        let src = """
        ---
        id: t
        app: x
        ---

        ```pry
        soft_assert_state: { viewmodel: VM, path: x, equals: 1 }
        ```
        """
        let spec = try SpecParser.parse(source: src)
        if case .softAssertState = spec.steps[0] {} else { XCTFail("not softAssertState") }
    }

    func testParseAssertFocus() throws {
        let src = """
        ---
        id: t
        app: x
        ---

        ```pry
        assert_focus: { id: "name_field" }
        ```
        """
        let spec = try SpecParser.parse(source: src)
        if case .assertFocus(let t) = spec.steps[0], case .id(let s) = t {
            XCTAssertEqual(s, "name_field")
        } else { XCTFail("not assertFocus") }
    }

    func testParseAssertEventually() throws {
        let src = """
        ---
        id: t
        app: x
        ---

        ```pry
        assert_eventually: { contains: { id: "x" } }
          timeout: 1s
        ```
        """
        let spec = try SpecParser.parse(source: src)
        if case .assertEventually(_, let t) = spec.steps[0] {
            XCTAssertEqual(t.seconds, 1)
        } else { XCTFail("not assertEventually") }
    }

    func testParseSelectRangeAndMultiSelect() throws {
        let src = """
        ---
        id: t
        app: x
        ---

        ```pry
        select_range: { from: { id: "a" }, to: { id: "b" } }
        multi_select: [{ id: "a" }, { id: "b" }, { id: "c" }]
        ```
        """
        let spec = try SpecParser.parse(source: src)
        if case .selectRange = spec.steps[0] {} else { XCTFail("not selectRange") }
        if case .multiSelect(let arr) = spec.steps[1] {
            XCTAssertEqual(arr.count, 3)
        } else { XCTFail("not multiSelect") }
    }

    func testParseWithRetry() throws {
        let src = """
        ---
        id: t
        app: x
        ---

        ```pry
        with_retry: 3
          - click: { id: "flaky" }
          - assert_state: { viewmodel: VM, path: x, equals: 1 }
        ```
        """
        let spec = try SpecParser.parse(source: src)
        if case .withRetry(let n, let body) = spec.steps[0] {
            XCTAssertEqual(n, 3)
            XCTAssertEqual(body.count, 2)
        } else { XCTFail("not withRetry") }
    }

    func testParseCopyToVar() throws {
        let src = """
        ---
        id: t
        app: x
        ---

        ```pry
        copy_to: { var: clip, from: pasteboard }
        ```
        """
        let spec = try SpecParser.parse(source: src)
        if case .copyToVar(let name, let src) = spec.steps[0] {
            XCTAssertEqual(name, "clip")
            if case .pasteboard = src {} else { XCTFail("not pasteboard source") }
        } else { XCTFail("not copyToVar") }
    }

    func testParseFrontmatterSlowWarn() throws {
        let src = """
        ---
        id: t
        app: x
        slow_warn_ms: 500
        state_delta: every_step
        ax_tree_diff: on_failure
        screenshots_embed: true
        ---

        ```pry
        launch
        ```
        """
        let spec = try SpecParser.parse(source: src)
        XCTAssertEqual(spec.slowWarnMs, 500)
        XCTAssertEqual(spec.stateDeltaPolicy, .everyStep)
        XCTAssertEqual(spec.axTreeDiffPolicy, .onFailure)
        XCTAssertTrue(spec.screenshotsEmbed)
    }

    func testParseExpectChange() throws {
        let src = """
        ---
        id: t
        app: x
        ---

        ```pry
        expect_change:
          action: { click: { id: "btn" } }
          in: { viewmodel: VM, path: "count" }
          to: 1
          timeout: 500ms
        ```
        """
        let spec = try SpecParser.parse(source: src)
        XCTAssertEqual(spec.steps.count, 1)
        if case .expectChange(let a, let vm, let p, let to, let t) = spec.steps[0] {
            XCTAssertEqual(vm, "VM")
            XCTAssertEqual(p, "count")
            XCTAssertEqual(to.asInt, 1)
            XCTAssertEqual(t.seconds, 0.5)
            if case .click = a {} else { XCTFail("action not click") }
        } else { XCTFail("not expect_change") }
    }

    func testRejectsMissingFrontmatter() {
        XCTAssertThrowsError(try SpecParser.parse(source: "no frontmatter here"))
    }
}

final class YAMLFlowTests: XCTestCase {
    func testScalars() throws {
        XCTAssertEqual(try YAMLFlow.parse("42").asInt, 42)
        XCTAssertEqual(try YAMLFlow.parse("3.14").asSeconds, 3.14)
        XCTAssertEqual(try YAMLFlow.parse("true").asBool, true)
        XCTAssertEqual(try YAMLFlow.parse("\"hi\"").asString, "hi")
        XCTAssertEqual(try YAMLFlow.parse("hello").asString, "hello")
    }

    func testDurations() throws {
        XCTAssertEqual(try YAMLFlow.parse("2s").asSeconds, 2)
        XCTAssertEqual(try YAMLFlow.parse("500ms").asSeconds, 0.5)
        XCTAssertEqual(try YAMLFlow.parse("1min").asSeconds, 60)
    }

    func testNestedObject() throws {
        let v = try YAMLFlow.parse("{ id: \"foo\", count: 3, flags: [a, b] }")
        XCTAssertEqual(v["id"]?.asString, "foo")
        XCTAssertEqual(v["count"]?.asInt, 3)
        XCTAssertEqual(v["flags"]?.asArray?.count, 2)
    }
}

final class VerdictReporterTests: XCTestCase {
    func testRendersPassedFrontmatter() {
        let now = Date()
        let v = Verdict(
            specPath: "flows/x.md", specID: "x", app: "fr.app",
            status: .passed, duration: 1.234, stepsTotal: 3, stepsPassed: 3,
            failedAtStep: nil, startedAt: now, finishedAt: now,
            stepResults: [], failure: nil, errorKind: nil, errorMessage: nil,
            attachmentsDir: nil
        )
        let md = VerdictReporter.render(v)
        XCTAssertTrue(md.contains("status: passed"))
        XCTAssertTrue(md.contains("steps_total: 3"))
        XCTAssertTrue(md.contains("PASSED"))
    }

    func testRendersFailureContext() {
        let now = Date()
        let f = FailureContext(
            stepIndex: 4, stepSource: "click new",
            expected: "x equals 1", observed: "got 2",
            suggestion: "use wait_for", axTreeSnippet: "- AXButton",
            registeredState: "VM:\n  x: 2",
            relevantLogs: nil, attachments: ["snap.png"]
        )
        let v = Verdict(
            specPath: nil, specID: "id", app: "app",
            status: .failed, duration: 0, stepsTotal: 5, stepsPassed: 3,
            failedAtStep: 4, startedAt: now, finishedAt: now,
            stepResults: [], failure: f, errorKind: nil, errorMessage: nil,
            attachmentsDir: nil
        )
        let md = VerdictReporter.render(v)
        XCTAssertTrue(md.contains("FAILED at step 4"))
        XCTAssertTrue(md.contains("**Expected:** x equals 1"))
        XCTAssertTrue(md.contains("**Suggestion:** use wait_for"))
        XCTAssertTrue(md.contains("- AXButton"))
        XCTAssertTrue(md.contains("snap.png"))
    }
}

// MARK: - Integration (gated)

/// Live AX test — only runs when PRY_INTEGRATION=1 AND the spawning shell has
/// Accessibility permission. Demonstrates the public Pry API end-to-end.
final class PryProgrammaticAPITests: XCTestCase {

    override func setUp() async throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["PRY_INTEGRATION"] != "1",
                      "set PRY_INTEGRATION=1 to run live-AX tests")
    }

    func testLaunchClickAndState() async throws {
        guard let demoPath = ProcessInfo.processInfo.environment["PRY_DEMO_BINARY"] else {
            throw XCTSkip("PRY_DEMO_BINARY not set; build Fixtures/DemoApp first")
        }
        let pry = try await Pry.launch(
            app: "fr.neimad.pry.demoapp",
            executablePath: demoPath
        )
        try await pry.click(.id("new_doc_button"))
        try await Task.sleep(nanoseconds: 200_000_000)
        let count: Int? = try await pry.state(of: "DocumentListVM", path: "documents.count")
        XCTAssertEqual(count, 1)
        await pry.terminate()
    }
}
