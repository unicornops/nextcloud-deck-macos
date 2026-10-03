import AppKit
import Foundation
import Security

/// Obtains app password from Nextcloud (password flow or browser flow for 2FA).
/// See: https://docs.nextcloud.com/server/latest/developer_manual/client_apis/LoginFlow/index.html
enum NextcloudAuth {

    // MARK: - Login Flow v2 (browser) – supports 2FA

    /// Login Flow v2: open browser for user to sign in (including 2FA), then poll for app password.
    /// Returns (serverURL, loginName, appPassword). Use this when the user has 2FA enabled.
    ///
    /// Polling keeps going through transient failures (network drops, sleep/wake, 5xx) until the
    /// 20-minute login token expires. Cancelling the calling task stops it with `CancellationError`.
    static func loginWithBrowser(
        serverURL: URL,
        session: URLSession = .shared,
        pollInterval: TimeInterval = 2,
        timeout: TimeInterval = 20 * 60,
        openURL: (URL) -> Void = { _ = NSWorkspace.shared.open($0) }
    ) async throws
        -> (serverURL: URL, loginName: String, appPassword: String) {
        let loginV2URL = serverURL.appendingPathComponent("index.php").appendingPathComponent("login")
            .appendingPathComponent("v2")
        var request = URLRequest(url: loginV2URL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw AuthError.invalidResponse
        }

        let decoder = JSONDecoder()
        let initResponse = try decoder.decode(LoginV2InitResponse.self, from: data)
        // Both URLs come from the server: only ever open or post to web URLs.
        guard let loginURL = webURL(initResponse.login),
              let pollURL = webURL(initResponse.poll.endpoint) else {
            throw AuthError.invalidResponse
        }
        openURL(loginURL)

        var pollRequest = URLRequest(url: pollURL)
        pollRequest.httpMethod = "POST"
        pollRequest.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        pollRequest.httpBody = "token=\(formEncoded(initResponse.poll.token))".data(using: .utf8)

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            try await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))

            let pollData: Data
            let pollResponse: URLResponse
            do {
                (pollData, pollResponse) = try await session.data(for: pollRequest)
            } catch {
                try Task.checkCancellation()
                continue // Transient network failure: try again on the next poll.
            }
            guard let pollHttp = pollResponse as? HTTPURLResponse else { continue }

            switch pollHttp.statusCode {
            case 200:
                let credentials = try decoder.decode(LoginV2PollResponse.self, from: pollData)
                guard let serverURL = webURL(credentials.server) else { throw AuthError.invalidResponse }
                return (serverURL, credentials.loginName, credentials.appPassword)
            case 404, 500 ... 599:
                continue // 404: not signed in yet. 5xx: server hiccup.
            default:
                if let err = try? decoder.decode(LoginV2PollError.self, from: pollData) {
                    throw AuthError.serverError(err.message)
                }
                throw AuthError.httpStatus(pollHttp.statusCode)
            }
        }
        throw AuthError.pollTimeout
    }

    /// Parses `string` as an http(s) URL with a host, or returns nil.
    private static func webURL(_ string: String) -> URL? {
        guard let url = URL(string: string),
              let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              url.host?.isEmpty == false else { return nil }
        return url
    }

    /// Percent-encodes a value for an `application/x-www-form-urlencoded` body.
    private static func formEncoded(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private struct LoginV2InitResponse: Decodable {
        let poll: Poll
        let login: String
        struct Poll: Decodable {
            let token: String
            let endpoint: String
        }
    }

    private struct LoginV2PollResponse: Decodable {
        let server: String
        let loginName: String
        let appPassword: String
    }

    private struct LoginV2PollError: Decodable {
        let message: String
    }

    // MARK: - Password flow (no 2FA or app password)

    /// Exchange username + password for an app password via OCS getapppassword.
    /// Fails if the account uses 2FA; use loginWithBrowser(serverURL:) instead.
    /// If the account already uses an app password, the server returns 403 — in that case the caller can use the
    /// provided password as the app password.
    static func getAppPassword(serverURL: URL, username: String, password: String) async throws -> String {
        let ocsURL = serverURL.appendingPathComponent("ocs").appendingPathComponent("v2.php")
            .appendingPathComponent("core").appendingPathComponent("getapppassword")
        let credentials = "\(username):\(password)"
        guard let credentialData = credentials.data(using: .utf8) else {
            throw AuthError.invalidEncoding
        }
        let basic = "Basic \(credentialData.base64EncodedString())"

        var request = URLRequest(url: ocsURL)
        request.setValue("true", forHTTPHeaderField: "OCS-APIRequest")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(basic, forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AuthError.invalidResponse
        }

        // 403 = already using app password; use the provided password as app password
        if http.statusCode == 403 {
            return password
        }

        guard http.statusCode == 200 else {
            if let msg = parseOCSError(data) { throw AuthError.serverError(msg) }
            throw AuthError.httpStatus(http.statusCode)
        }

        guard let appPassword = parseOCSAppPassword(data) else {
            throw AuthError.noAppPasswordInResponse
        }
        return appPassword
    }

    private static func parseOCSAppPassword(_ data: Data) -> String? {
        guard let xml = String(data: data, encoding: .utf8) else { return nil }
        if let start = xml.range(of: "<apppassword>"),
           let end = xml.range(of: "</apppassword>") {
            return String(xml[start.upperBound ..< end.lowerBound])
        }
        return nil
    }

    private static func parseOCSError(_ data: Data) -> String? {
        guard let xml = String(data: data, encoding: .utf8) else { return nil }
        if let start = xml.range(of: "<message>"),
           let end = xml.range(of: "</message>") {
            return String(xml[start.upperBound ..< end.lowerBound])
        }
        return nil
    }
}

enum AuthError: LocalizedError {
    case invalidEncoding
    case invalidResponse
    case serverError(String)
    case noAppPasswordInResponse
    case httpStatus(Int)
    case pollTimeout

    var errorDescription: String? {
        switch self {
        case .invalidEncoding: "Invalid credential encoding"
        case .invalidResponse: "Invalid response"
        case let .serverError(msg): msg
        case .noAppPasswordInResponse: "No app password in response"
        case let .httpStatus(code): "HTTP \(code)"
        case .pollTimeout: "Sign-in timed out. Complete sign-in in the browser and try again."
        }
    }
}
