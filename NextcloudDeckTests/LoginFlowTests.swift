import Foundation
@testable import NextcloudDeck
import XCTest

/// Login Flow v2 polling in `NextcloudAuth` (#59), against `StubURLProtocol`.
final class LoginFlowTests: XCTestCase {
    private static let success = StubResponse.json(
        #"{"server": "https://cloud.example", "loginName": "rob", "appPassword": "secret"}"#
    )

    override func setUp() {
        StubURLProtocol.reset()
    }

    override func tearDown() {
        StubURLProtocol.reset()
    }

    /// Serves the flow's start request and answers polls from `polls` in order (404 once exhausted).
    private func serve(loginURL: String = "https://cloud.example/login/v2/flow/abc", polls: [StubResponse]) {
        let lock = NSLock()
        nonisolated(unsafe) var remaining = polls
        StubURLProtocol.handler = { request in
            if request.path == "/index.php/login/v2" {
                return .json("""
                {"poll": {"token": "a+b/c", "endpoint": "https://cloud.example/login/v2/poll"}, "login": "\(loginURL)"}
                """)
            }
            return lock.withLock { remaining.isEmpty ? .status(404) : remaining.removeFirst() }
        }
    }

    private func login(timeout: TimeInterval = 5, opened: @escaping (URL) -> Void = { _ in }) async throws
        -> (serverURL: URL, loginName: String, appPassword: String) {
        try await NextcloudAuth.loginWithBrowser(
            serverURL: testServer,
            session: StubURLProtocol.session(),
            pollInterval: 0.02,
            timeout: timeout,
            openURL: opened
        )
    }

    func testTransientFailuresAreRetriedUntilSignedIn() async throws {
        serve(polls: [StubResponse(error: URLError(.networkConnectionLost)), .status(503), .status(404), Self.success])
        var opened: [URL] = []
        let result = try await login { opened.append($0) }

        XCTAssertEqual(result.loginName, "rob")
        XCTAssertEqual(result.appPassword, "secret")
        XCTAssertEqual(opened, [URL(string: "https://cloud.example/login/v2/flow/abc")!])
        let poll = try XCTUnwrap(StubURLProtocol.requests.last { $0.path == "/login/v2/poll" })
        XCTAssertEqual(String(decoding: poll.body, as: UTF8.self), "token=a%2Bb%2Fc")
    }

    func testRefusalIsReported() async {
        serve(polls: [.json(#"{"message": "Access forbidden"}"#, status: 403)])
        do {
            _ = try await login()
            XCTFail("expected an error")
        } catch {
            guard case let AuthError.serverError(message) = error else { return XCTFail("got \(error)") }
            XCTAssertEqual(message, "Access forbidden")
        }
    }

    func testNonWebLoginURLIsNeverOpened() async {
        for url in ["file:///etc/passwd", "javascript:alert(1)", "x-custom://open"] {
            serve(loginURL: url, polls: [])
            var opened: [URL] = []
            do {
                _ = try await login { opened.append($0) }
                XCTFail("\(url) should be refused")
            } catch {
                guard case AuthError.invalidResponse = error else { return XCTFail("got \(error) for \(url)") }
            }
            XCTAssertTrue(opened.isEmpty, url)
        }
    }

    func testGivesUpWhenTheTokenExpires() async {
        serve(polls: [])
        do {
            _ = try await login(timeout: 0.15)
            XCTFail("expected a timeout")
        } catch {
            guard case AuthError.pollTimeout = error else { return XCTFail("got \(error)") }
        }
    }

    func testCancellingStopsPolling() async {
        serve(polls: [])
        let task = Task { try await login() }
        await sleep(seconds: 0.1)
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("expected cancellation")
        } catch {
            XCTAssertTrue(error is CancellationError, "got \(error)")
        }
    }
}
