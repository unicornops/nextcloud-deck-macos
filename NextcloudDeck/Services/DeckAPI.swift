import Foundation

/// Client for Nextcloud Deck REST API
/// https://deck.readthedocs.io/en/latest/API/
final class DeckAPI {
    private let baseURL: URL
    private let ocsBaseURL: URL
    private let deckAppBaseURL: URL
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
        self.ocsBaseURL = serverURL
            .appendingPathComponent("ocs")
            .appendingPathComponent("v2.php")
            .appendingPathComponent("apps")
            .appendingPathComponent("deck")
            .appendingPathComponent("api")
            .appendingPathComponent("v1.0")
        self.deckAppBaseURL = serverURL
            .appendingPathComponent("index.php")
            .appendingPathComponent("apps")
            .appendingPathComponent("deck")
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

    private func ocsURL(for path: String) -> URL? {
        let basePath = ocsBaseURL.path
        let pathToUse = (basePath.hasSuffix("/") ? basePath : basePath + "/") + path
        var components = URLComponents(url: ocsBaseURL, resolvingAgainstBaseURL: false)!
        components.path = pathToUse
        return components.url
    }

    private func deckAppURL(for path: String) -> URL? {
        let basePath = deckAppBaseURL.path
        let pathToUse = (basePath.hasSuffix("/") ? basePath : basePath + "/") + path
        var components = URLComponents(url: deckAppBaseURL, resolvingAgainstBaseURL: false)!
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
        let (data, _) = try await performRequest(url: url, method: "GET")
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
        guard let url = url(for: "boards") else { throw DeckAPIError.invalidURL }
        let body = try encoder.encode(CreateBoardRequest(title: title, color: color))
        let (data, _) = try await performRequest(url: url, method: "POST", body: body)
        return try decoder.decode(Board.self, from: data)
    }

    func updateBoard(id: Int, title: String?, color: String?, archived: Bool?) async throws -> Board {
        try await request("boards/\(id)", method: "PUT", body: UpdateBoardRequest(title: title, color: color, archived: archived))
    }

    func deleteBoard(id: Int) async throws {
        try await requestNoContent("boards/\(id)", method: "DELETE")
    }

    func undoDeleteBoard(id: Int) async throws {
        try await requestNoContent("boards/\(id)/undo_delete", method: "POST")
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

    private struct OCSCardWrapper: Decodable {
        let data: Card
    }

    private struct OCSCardEnvelope: Decodable {
        let ocs: OCSCardWrapper
    }

    private struct OCSCardArrayWrapper: Decodable {
        let data: [Card]
    }

    private struct OCSCardArrayEnvelope: Decodable {
        let ocs: OCSCardArrayWrapper
    }

    func getStack(boardId: Int, stackId: Int) async throws -> Stack {
        try await request("boards/\(boardId)/stacks/\(stackId)")
    }

    /// Fetches stacks that have been archived (soft-deleted) on the board.
    func getArchivedStacks(boardId: Int) async throws -> [Stack] {
        var path = baseURL.path
        if path.hasSuffix("/") { path.removeLast() }
        path += "/boards/\(boardId)/stacks/archived"
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
            throw DeckAPIError.badRequest("Could not decode archived stacks: \(detail)")
        } catch {
            throw DeckAPIError.badRequest("Could not decode archived stacks: \(error.localizedDescription)")
        }
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
        let path = "boards/\(boardId)/stacks/\(stackId)/cards/\(cardId)"
        guard let requestURL = url(for: path) else { throw DeckAPIError.invalidURL }
        let (data, _) = try await performRequest(url: requestURL, method: "GET")

        if let card = try? decoder.decode(Card.self, from: data) {
            return card
        }
        if let wrapper = try? decoder.decode(OCSCardWrapper.self, from: data) {
            return wrapper.data
        }
        if let envelope = try? decoder.decode(OCSCardEnvelope.self, from: data) {
            return envelope.ocs.data
        }
        throw DeckAPIError.badRequest("Could not decode card response")
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
        let body = try encoder.encode(ReorderCardRequest(order: order, stackId: newStackId))
        let paths = [
            "cards/\(cardId)/reorder",
            "boards/\(boardId)/stacks/\(stackId)/cards/\(cardId)/reorder"
        ]

        var lastError: Error?

        for path in paths {
            guard let requestURL = url(for: path) else {
                lastError = DeckAPIError.invalidURL
                continue
            }

            do {
                let (data, _) = try await performRequest(url: requestURL, method: "PUT", body: body)
                return try await decodeReorderedCardResponse(
                    data: data,
                    boardId: boardId,
                    stackId: stackId,
                    newStackId: newStackId,
                    cardId: cardId
                )
            } catch {
                lastError = error
                if !shouldTryLegacyReorderFallback(error) || path == paths.last {
                    throw error
                }
            }
        }

        if let lastError {
            throw lastError
        }

        throw DeckAPIError.invalidResponse
    }

    private func shouldTryLegacyReorderFallback(_ error: Error) -> Bool {
        switch error {
        case DeckAPIError.httpStatus(404), DeckAPIError.httpStatus(405), DeckAPIError.badRequest:
            return true
        default:
            return false
        }
    }

    private func decodeReorderedCardResponse(
        data: Data,
        boardId: Int,
        stackId: Int,
        newStackId: Int?,
        cardId: Int
    ) async throws -> Card {
        if data.isEmpty {
            return try await getCard(boardId: boardId, stackId: newStackId ?? stackId, cardId: cardId)
        }

        if let card = try? decoder.decode(Card.self, from: data) {
            return card
        }

        if let wrapper = try? decoder.decode(OCSCardWrapper.self, from: data) {
            return wrapper.data
        }

        if let envelope = try? decoder.decode(OCSCardEnvelope.self, from: data) {
            return envelope.ocs.data
        }

        return try await getCard(boardId: boardId, stackId: newStackId ?? stackId, cardId: cardId)
    }

    func moveCardToStack(card: Card, toStackId: Int, order: Int) async throws -> [Card] {
        guard let requestURL = deckAppURL(for: "cards/\(card.id)/reorder") else {
            throw DeckAPIError.invalidURL
        }

        var updatedCard = card
        updatedCard.stackId = toStackId
        updatedCard.order = order
        let body = try encoder.encode(updatedCard)

        let (data, _) = try await performRequest(url: requestURL, method: "PUT", body: body)

        if let cards = try? decoder.decode([Card].self, from: data) {
            return cards
        }

        if let wrapper = try? decoder.decode(OCSCardArrayWrapper.self, from: data) {
            return wrapper.data
        }

        if let envelope = try? decoder.decode(OCSCardArrayEnvelope.self, from: data) {
            return envelope.ocs.data
        }

        throw DeckAPIError.badRequest("Could not decode moved cards response")
    }

    func assignLabel(boardId: Int, stackId: Int, cardId: Int, labelId: Int) async throws {
        try await requestNoContent("boards/\(boardId)/stacks/\(stackId)/cards/\(cardId)/assignLabel", method: "PUT", body: LabelIdRequest(labelId: labelId))
    }

    func removeLabel(boardId: Int, stackId: Int, cardId: Int, labelId: Int) async throws {
        try await requestNoContent("boards/\(boardId)/stacks/\(stackId)/cards/\(cardId)/removeLabel", method: "PUT", body: LabelIdRequest(labelId: labelId))
    }

    // MARK: - Labels

    /// Creates a new label on the board. Returns the created label (or reload board to get it).
    func createLabel(boardId: Int, title: String, color: String = "31CC7C") async throws -> DeckLabel {
        try await request("boards/\(boardId)/labels", method: "POST", body: CreateLabelRequest(title: title, color: color))
    }

    // MARK: - Attachments

    private struct OCSAttachmentsWrapper: Decodable {
        let data: [Attachment]
    }

    private struct OCSAttachmentsEnvelope: Decodable {
        let ocs: OCSAttachmentsWrapper
    }

    /// Fetches the list of attachments for a card.
    ///
    /// Uses the internal Deck route (`/apps/deck/cards/{cardId}/attachments`)
    /// which is what the Deck web UI uses. Falls back to the REST API v1.0
    /// endpoint if the internal route fails.
    func getAttachments(boardId: Int, stackId: Int, cardId: Int) async throws -> [Attachment] {
        // 1. Internal Deck route (matches the web UI)
        if let internalURL = deckAppURL(for: "cards/\(cardId)/attachments") {
            do {
                let (data, _) = try await performRequest(url: internalURL, method: "GET")
                let result = decodeAttachments(from: data)
                if !result.isEmpty {
                    return result
                }
            } catch {
                // Fall through to REST API fallback
            }
        }

        // 2. REST API v1.0 fallback
        let apiPath = "boards/\(boardId)/stacks/\(stackId)/cards/\(cardId)/attachments"
        if let apiURL = url(for: apiPath) {
            do {
                let (data, _) = try await performRequest(url: apiURL, method: "GET")
                let result = decodeAttachments(from: data)
                if !result.isEmpty {
                    return result
                }
            } catch {
                // Both routes failed
            }
        }

        return []
    }

    /// Attempts to decode an attachment list from raw response data, trying
    /// multiple common response envelopes.
    private func decodeAttachments(from data: Data) -> [Attachment] {
        if let attachments = try? decoder.decode([Attachment].self, from: data) {
            return attachments
        }
        if let wrapper = try? decoder.decode(OCSAttachmentsWrapper.self, from: data) {
            return wrapper.data
        }
        if let envelope = try? decoder.decode(OCSAttachmentsEnvelope.self, from: data) {
            return envelope.ocs.data
        }
        // Fallback: extract from raw JSON
        if let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let arr: [[String: Any]]?
            if let direct = parsed["data"] as? [[String: Any]] {
                arr = direct
            } else if let ocs = parsed["ocs"] as? [String: Any], let ocsData = ocs["data"] as? [[String: Any]] {
                arr = ocsData
            } else {
                arr = nil
            }
            if let arr {
                return arr.compactMap { dict -> Attachment? in
                    guard let jsonData = try? JSONSerialization.data(withJSONObject: dict) else { return nil }
                    return try? decoder.decode(Attachment.self, from: jsonData)
                }
            }
        }
        if let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            return arr.compactMap { dict -> Attachment? in
                guard let jsonData = try? JSONSerialization.data(withJSONObject: dict) else { return nil }
                return try? decoder.decode(Attachment.self, from: jsonData)
            }
        }
        return []
    }

    /// Downloads the file content of an attachment. Returns raw binary data.
    ///
    /// Uses the internal Deck route (`/cards/{cardId}/attachment/{attachmentId}`)
    /// as primary, falling back to REST API v1.0 if needed.
    func downloadAttachment(boardId: Int, stackId: Int, cardId: Int, attachmentId: Int, type: String? = nil) async throws -> Data {
        // The internal route parses attachmentId as "{type}:{id}" — default is deck_file.
        let typePrefix = type ?? "file"
        // 1. Internal Deck route (singular "attachment")
        if let internalURL = deckAppURL(for: "cards/\(cardId)/attachment/\(typePrefix):\(attachmentId)") {
            do {
                let (data, _) = try await performRequest(url: internalURL, method: "GET")
                return data
            } catch {
                // Fall through to REST API fallback
            }
        }

        // 2. REST API v1.0 fallback
        guard let url = url(for: "boards/\(boardId)/stacks/\(stackId)/cards/\(cardId)/attachments/\(attachmentId)") else {
            throw DeckAPIError.invalidURL
        }
        let (data, _) = try await performRequest(url: url, method: "GET")
        return data
    }

    /// Uploads a file as an attachment to a card.
    ///
    /// Uses the internal Deck route (`/cards/{cardId}/attachment`, singular)
    /// as primary, falling back to REST API v1.0 if needed.
    func uploadAttachment(boardId: Int, stackId: Int, cardId: Int, fileURL: URL, filename: String) async throws -> Attachment {
        let boundary = UUID().uuidString
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
        body.append(try Data(contentsOf: fileURL))
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        let extraHeaders = [
            "Content-Type": "multipart/form-data; boundary=\(boundary)",
            "Content-Length": "\(body.count)"
        ]

        // 1. Internal Deck route (singular "attachment")
        if let internalURL = deckAppURL(for: "cards/\(cardId)/attachment") {
            do {
                var req = URLRequest(url: internalURL)
                req.httpMethod = "POST"
                req.setValue("true", forHTTPHeaderField: "OCS-APIRequest")
                req.setValue("application/json", forHTTPHeaderField: "Accept")
                req.setValue(authHeader, forHTTPHeaderField: "Authorization")
                for (key, value) in extraHeaders { req.setValue(value, forHTTPHeaderField: key) }
                req.httpBody = body

                let (data, response) = try await session.data(for: req)
                guard let http = response as? HTTPURLResponse else { throw DeckAPIError.invalidResponse }
                if http.statusCode == 400, let err = try? decoder.decode(APIErrorResponse.self, from: data) {
                    throw DeckAPIError.badRequest(err.message)
                }
                if http.statusCode == 403 { throw DeckAPIError.permissionDenied }
                guard (200...299).contains(http.statusCode) else {
                    throw DeckAPIError.httpStatus(http.statusCode)
                }
                return try decoder.decode(Attachment.self, from: data)
            } catch {
                // Fall through to REST API fallback
            }
        }

        // 2. REST API v1.0 fallback
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw DeckAPIError.invalidURL
        }
        let path = (baseURL.path.hasSuffix("/") ? baseURL.path : baseURL.path + "/") + "boards/\(boardId)/stacks/\(stackId)/cards/\(cardId)/attachments"
        components.path = path
        components.queryItems = [URLQueryItem(name: "type", value: "file")]
        guard let url = components.url else { throw DeckAPIError.invalidURL }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("true", forHTTPHeaderField: "OCS-APIRequest")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(authHeader, forHTTPHeaderField: "Authorization")
        for (key, value) in extraHeaders { req.setValue(value, forHTTPHeaderField: key) }
        req.httpBody = body

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw DeckAPIError.invalidResponse }
        if http.statusCode == 400, let err = try? decoder.decode(APIErrorResponse.self, from: data) {
            throw DeckAPIError.badRequest(err.message)
        }
        if http.statusCode == 403 { throw DeckAPIError.permissionDenied }
        guard (200...299).contains(http.statusCode) else {
            throw DeckAPIError.httpStatus(http.statusCode)
        }
        return try decoder.decode(Attachment.self, from: data)
    }

    /// Deletes an attachment from a card.
    ///
    /// Uses the internal Deck route (`/cards/{cardId}/attachment/{attachmentId}`)
    /// as primary, falling back to REST API v1.0 if needed.
    func deleteAttachment(boardId: Int, stackId: Int, cardId: Int, attachmentId: Int, type: String? = nil) async throws {
        let typePrefix = type ?? "file"
        // 1. Internal Deck route (singular "attachment")
        if let internalURL = deckAppURL(for: "cards/\(cardId)/attachment/\(typePrefix):\(attachmentId)") {
            do {
                _ = try await performRequest(url: internalURL, method: "DELETE")
                return
            } catch {
                // Fall through to REST API fallback
            }
        }

        // 2. REST API v1.0 fallback
        try await requestNoContent("boards/\(boardId)/stacks/\(stackId)/cards/\(cardId)/attachments/\(attachmentId)", method: "DELETE")
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

private struct CreateLabelRequest: Encodable {
    let title: String
    let color: String
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
