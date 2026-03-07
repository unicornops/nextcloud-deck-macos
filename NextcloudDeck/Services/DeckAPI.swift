import Foundation

/// Client for Nextcloud Deck REST API
/// https://deck.readthedocs.io/en/latest/API/
final class DeckAPI {
    private let baseURL: URL
    private let username: String
    private let appPassword: String
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    
    private static let apiPath = "/index.php/apps/deck/api/v1.0"
    
    init(serverURL: URL, username: String, appPassword: String) {
        self.baseURL = serverURL
            .appendingPathComponent("index.php")
            .appendingPathComponent("apps")
            .appendingPathComponent("deck")
            .appendingPathComponent("api")
            .appendingPathComponent("v1.0")
        self.username = username
        self.appPassword = appPassword
        self.session = URLSession.shared
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
    }
    
    private var authHeader: String {
        let credentials = "\(username):\(appPassword)"
        guard let data = credentials.data(using: .utf8) else { return "" }
        return "Basic \(data.base64EncodedString())"
    }
    
    /// Builds a full URL by appending the relative path to the base URL (avoids `URL(string:relativeTo:)` replacing the last path component and dropping `/v1.0`).
    private func url(for path: String) -> URL? {
        let basePath = baseURL.path
        let pathToUse = (basePath.hasSuffix("/") ? basePath : basePath + "/") + path
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.path = pathToUse
        return components.url
    }

    private func request<T: Decodable>(
        _ path: String,
        method: String = "GET",
        body: (any Encodable)? = nil
    ) async throws -> T {
        guard let url = url(for: path) else {
            throw DeckAPIError.invalidURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("true", forHTTPHeaderField: "OCS-APIRequest")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(authHeader, forHTTPHeaderField: "Authorization")
        
        if let body = body {
            req.httpBody = try encoder.encode(body)
        }
        
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw DeckAPIError.invalidResponse }
        
        if http.statusCode == 304 { throw DeckAPIError.notModified }
        if http.statusCode == 400, let err = try? decoder.decode(APIErrorResponse.self, from: data) {
            throw DeckAPIError.badRequest(err.message)
        }
        if http.statusCode == 403 { throw DeckAPIError.permissionDenied }
        guard (200...299).contains(http.statusCode) else {
            throw DeckAPIError.httpStatus(http.statusCode)
        }
        
        return try decoder.decode(T.self, from: data)
    }
    
    private func requestNoContent(_ path: String, method: String = "GET", body: (any Encodable)? = nil) async throws {
        guard let url = url(for: path) else {
            throw DeckAPIError.invalidURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("true", forHTTPHeaderField: "OCS-APIRequest")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(authHeader, forHTTPHeaderField: "Authorization")
        if let body = body {
            req.httpBody = try encoder.encode(body)
        }
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw DeckAPIError.invalidResponse }
        if http.statusCode == 400, let err = try? decoder.decode(APIErrorResponse.self, from: data) {
            throw DeckAPIError.badRequest(err.message)
        }
        guard (200...299).contains(http.statusCode) else {
            throw DeckAPIError.httpStatus(http.statusCode)
        }
    }
    
    // MARK: - Boards

    func getBoards(details: Bool = true) async throws -> [Board] {
        var path = baseURL.path
        if path.hasSuffix("/") { path.removeLast() }
        path += "/boards"
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.path = path
        components.queryItems = [URLQueryItem(name: "details", value: details ? "true" : "false")]
        guard let url = components.url else { throw DeckAPIError.invalidURL }
        let (data, response) = try await performRequest(url: url, method: "GET")
        if let boards = try? decoder.decode([Board].self, from: data) { return boards }
        if let wrapper = try? decoder.decode(OCSBoardsWrapper.self, from: data) { return wrapper.data }
        if let ocs = try? decoder.decode(OCSEnvelope.self, from: data) { return ocs.ocs.data }
        throw DeckAPIError.badRequest("Could not decode boards response")
    }

    private struct OCSBoardsWrapper: Decodable {
        let data: [Board]
    }

    private struct OCSEnvelope: Decodable {
        let ocs: OCSBoardsWrapper
    }

    private func performRequest(url: URL, method: String, body: Data? = nil) async throws -> (Data, URLResponse) {
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("true", forHTTPHeaderField: "OCS-APIRequest")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(authHeader, forHTTPHeaderField: "Authorization")
        req.httpBody = body
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw DeckAPIError.invalidResponse }
        if http.statusCode == 304 { throw DeckAPIError.notModified }
        if http.statusCode == 400, let err = try? decoder.decode(APIErrorResponse.self, from: data) {
            throw DeckAPIError.badRequest(err.message)
        }
        if http.statusCode == 403 { throw DeckAPIError.permissionDenied }
        guard (200...299).contains(http.statusCode) else {
            throw DeckAPIError.httpStatus(http.statusCode)
        }
        return (data, response)
    }

    private struct OCSBoardsResponse: Decodable {
        let data: [Board]
    }
    
    func getBoard(id: Int) async throws -> Board {
        try await request("boards/\(id)")
    }
    
    func createBoard(title: String, color: String = "0082c9") async throws -> Board {
        try await request("boards", method: "POST", body: CreateBoardRequest(title: title, color: color))
    }
    
    func updateBoard(id: Int, title: String?, color: String?, archived: Bool?) async throws -> Board {
        try await request("boards/\(id)", method: "PUT", body: UpdateBoardRequest(title: title, color: color, archived: archived))
    }
    
    func deleteBoard(id: Int) async throws {
        try await requestNoContent("boards/\(id)", method: "DELETE")
    }
    
    // MARK: - Stacks

    func getStacks(boardId: Int) async throws -> [Stack] {
        var path = baseURL.path
        if path.hasSuffix("/") { path.removeLast() }
        path += "/boards/\(boardId)/stacks"
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.path = path
        guard let url = components.url else { throw DeckAPIError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("true", forHTTPHeaderField: "OCS-APIRequest")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(authHeader, forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw DeckAPIError.invalidResponse }
        if http.statusCode == 304 { throw DeckAPIError.notModified }
        if http.statusCode == 400, let err = try? decoder.decode(APIErrorResponse.self, from: data) {
            throw DeckAPIError.badRequest(err.message)
        }
        if http.statusCode == 403 { throw DeckAPIError.permissionDenied }
        guard (200...299).contains(http.statusCode) else {
            throw DeckAPIError.httpStatus(http.statusCode)
        }
        do {
            return try decoder.decode([Stack].self, from: data)
        } catch let arrayError as DecodingError {
            if let wrapper = try? decoder.decode(OCSStacksWrapper.self, from: data) { return wrapper.data }
            if let ocs = try? decoder.decode(OCSStacksEnvelope.self, from: data) { return ocs.ocs.data }
            let detail = decodingErrorDescription(arrayError)
            throw DeckAPIError.badRequest("Could not decode stacks: \(detail)")
        } catch {
            throw DeckAPIError.badRequest("Could not decode stacks: \(error.localizedDescription)")
        }
    }

    private func decodingErrorDescription(_ error: DecodingError) -> String {
        switch error {
        case .keyNotFound(let key, let context):
            return "missing key '\(key.stringValue)' at \(context.codingPath.map(\.stringValue).joined(separator: "."))"
        case .typeMismatch(let type, let context):
            return "type mismatch for \(type) at \(context.codingPath.map(\.stringValue).joined(separator: "."))"
        case .valueNotFound(let type, let context):
            return "nil value for \(type) at \(context.codingPath.map(\.stringValue).joined(separator: "."))"
        case .dataCorrupted(let context):
            return "data corrupted at \(context.codingPath.map(\.stringValue).joined(separator: "."))"
        @unknown default:
            return error.localizedDescription
        }
    }

    private struct OCSStacksWrapper: Decodable {
        let data: [Stack]
    }

    private struct OCSStacksEnvelope: Decodable {
        let ocs: OCSStacksWrapper
    }
    
    func getStack(boardId: Int, stackId: Int) async throws -> Stack {
        try await request("boards/\(boardId)/stacks/\(stackId)")
    }
    
    func createStack(boardId: Int, title: String, order: Int = 999) async throws -> Stack {
        try await request("boards/\(boardId)/stacks", method: "POST", body: CreateStackRequest(title: title, order: order))
    }
    
    func updateStack(boardId: Int, stackId: Int, title: String?, order: Int?) async throws -> Stack {
        try await request("boards/\(boardId)/stacks/\(stackId)", method: "PUT", body: UpdateStackRequest(title: title, order: order))
    }
    
    func deleteStack(boardId: Int, stackId: Int) async throws {
        try await requestNoContent("boards/\(boardId)/stacks/\(stackId)", method: "DELETE")
    }
    
    // MARK: - Cards
    
    func getCard(boardId: Int, stackId: Int, cardId: Int) async throws -> Card {
        try await request("boards/\(boardId)/stacks/\(stackId)/cards/\(cardId)")
    }
    
    func createCard(boardId: Int, stackId: Int, title: String, description: String? = nil, order: Int = 999, duedate: String? = nil) async throws -> Card {
        try await request("boards/\(boardId)/stacks/\(stackId)/cards", method: "POST", body: CreateCardRequest(title: title, type: "plain", order: order, description: description, duedate: duedate))
    }
    
    func updateCard(boardId: Int, stackId: Int, cardId: Int, title: String?, description: String?, order: Int?, duedate: String?) async throws -> Card {
        try await request("boards/\(boardId)/stacks/\(stackId)/cards/\(cardId)", method: "PUT", body: UpdateCardRequest(title: title, description: description, type: "plain", order: order, duedate: duedate))
    }
    
    func deleteCard(boardId: Int, stackId: Int, cardId: Int) async throws {
        try await requestNoContent("boards/\(boardId)/stacks/\(stackId)/cards/\(cardId)", method: "DELETE")
    }
    
    func reorderCard(boardId: Int, stackId: Int, cardId: Int, order: Int, newStackId: Int?) async throws -> Card {
        try await request("boards/\(boardId)/stacks/\(stackId)/cards/\(cardId)/reorder", method: "PUT", body: ReorderCardRequest(order: order, stackId: newStackId))
    }
    
    func assignLabel(boardId: Int, stackId: Int, cardId: Int, labelId: Int) async throws {
        try await requestNoContent("boards/\(boardId)/stacks/\(stackId)/cards/\(cardId)/assignLabel", method: "PUT", body: LabelIdRequest(labelId: labelId))
    }
    
    func removeLabel(boardId: Int, stackId: Int, cardId: Int, labelId: Int) async throws {
        try await requestNoContent("boards/\(boardId)/stacks/\(stackId)/cards/\(cardId)/removeLabel", method: "PUT", body: LabelIdRequest(labelId: labelId))
    }
}

// MARK: - Request DTOs

private struct APIErrorResponse: Codable {
    let status: Int?
    let message: String
}

private struct CreateBoardRequest: Encodable {
    let title: String
    let color: String
}

private struct UpdateBoardRequest: Encodable {
    let title: String?
    let color: String?
    let archived: Bool?
}

private struct CreateStackRequest: Encodable {
    let title: String
    let order: Int
}

private struct UpdateStackRequest: Encodable {
    let title: String?
    let order: Int?
}

private struct CreateCardRequest: Encodable {
    let title: String
    let type: String
    let order: Int
    let description: String?
    let duedate: String?
}

private struct UpdateCardRequest: Encodable {
    let title: String?
    let description: String?
    let type: String
    let order: Int?
    let duedate: String?
}

private struct ReorderCardRequest: Encodable {
    let order: Int
    let stackId: Int?
}

private struct LabelIdRequest: Encodable {
    let labelId: Int
}

enum DeckAPIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case notModified
    case badRequest(String)
    case permissionDenied
    case httpStatus(Int)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .invalidResponse: return "Invalid response"
        case .notModified: return "Not modified"
        case .badRequest(let msg): return msg
        case .permissionDenied: return "Permission denied"
        case .httpStatus(let code): return "HTTP \(code)"
        }
    }
}
