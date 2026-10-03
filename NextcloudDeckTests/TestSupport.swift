import Foundation
@testable import NextcloudDeck
import XCTest

// MARK: - Stub server

/// A canned response from `StubURLProtocol`.
struct StubResponse {
    var status = 200
    var body = Data()
    /// Seconds to wait before answering.
    var delay: TimeInterval = 0
    /// Fail the request with this error instead of answering.
    var error: URLError?

    static func json(_ string: String, status: Int = 200, delay: TimeInterval = 0) -> StubResponse {
        StubResponse(status: status, body: Data(string.utf8), delay: delay)
    }

    static func status(_ status: Int) -> StubResponse {
        StubResponse(status: status)
    }
}

/// A request seen by `StubURLProtocol`.
struct RecordedRequest {
    let method: String
    let path: String
    let query: String?
    let headers: [String: String]
    let body: Data

    /// The value of header `name`, matched case-insensitively as HTTP requires.
    func header(_ name: String) -> String? {
        headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }

    var line: String {
        "\(method) \(path)" + (query.map { "?\($0)" } ?? "")
    }

    var json: [String: Any]? {
        (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
    }
}

/// Answers every request from `handler` and records it. Tests run serially, so the shared state is
/// reset in `reset()` (called from `setUp`) rather than being per-test.
final class StubURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private nonisolated(unsafe) static var _handler: (RecordedRequest) -> StubResponse = { _ in .status(404) }
    private nonisolated(unsafe) static var _requests: [RecordedRequest] = []

    static var handler: (RecordedRequest) -> StubResponse {
        get { lock.withLock { _handler } }
        set { lock.withLock { _handler = newValue } }
    }

    static var requests: [RecordedRequest] {
        lock.withLock { _requests }
    }

    static func reset() {
        lock.withLock {
            _handler = { _ in .status(404) }
            _requests = []
        }
    }

    /// An ephemeral session whose requests all go to the stub.
    static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let recorded = RecordedRequest(
            method: request.httpMethod ?? "GET",
            path: request.url?.path ?? "",
            query: request.url?.query,
            headers: request.allHTTPHeaderFields ?? [:],
            body: request.httpBody ?? Self.read(request.httpBodyStream)
        )
        let response = Self.lock.withLock { () -> StubResponse in
            Self._requests.append(recorded)
            return Self._handler(recorded)
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + response.delay) { [self] in
            if let error = response.error {
                client?.urlProtocol(self, didFailWithError: error)
                return
            }
            guard let url = request.url,
                  let http = HTTPURLResponse(url: url, statusCode: response.status, httpVersion: nil, headerFields: nil)
            else { return }
            client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: response.body)
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}

    private static func read(_ stream: InputStream?) -> Data {
        guard let stream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

// MARK: - Credentials

/// Keeps credentials in memory so tests never touch the real Keychain.
final class InMemoryCredentialStore: CredentialStore {
    var credentials: (serverURL: URL, username: String, appPassword: String)?
    private(set) var deleteCount = 0
    private(set) var saveCount = 0

    init(credentials: (serverURL: URL, username: String, appPassword: String)? = nil) {
        self.credentials = credentials
    }

    static func signedIn() -> InMemoryCredentialStore {
        InMemoryCredentialStore(credentials: (URL(string: "https://cloud.example")!, "rob", "app-password"))
    }

    func load() -> (serverURL: URL, username: String, appPassword: String)? {
        credentials
    }

    func save(serverURL: URL, username: String, appPassword: String) throws -> URL {
        saveCount += 1
        credentials = (serverURL, username, appPassword)
        return serverURL
    }

    func delete() throws {
        deleteCount += 1
        credentials = nil
    }
}

// MARK: - Helpers

let testServer = URL(string: "https://cloud.example")!

/// Polls `condition` on the main actor until it holds or `timeout` passes.
@MainActor
func waitUntil(
    timeout: TimeInterval = 3,
    _ condition: () -> Bool,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() {
        if Date() > deadline {
            XCTFail("Timed out waiting for condition", file: file, line: line)
            return
        }
        try? await Task.sleep(nanoseconds: 10_000_000)
    }
}

func sleep(seconds: TimeInterval) async {
    try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
}
