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

    init(serverURL: URL, username: String, appPassword: String, session: URLSession = .shared) {
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
        self.session = session
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
    }

    private var authHeader: String {
        let credentials = "\(username):\(appPassword)"
        guard let data = credentials.data(using: .utf8) else { return "" }
        return "Basic \(data.base64EncodedString())"
    }

    /// Builds a full URL by appending the relative path to the base URL (avoids `URL(string:relativeTo:)` replacing the
    /// last path component and dropping `/v1.0`).
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
    ) async throws
        -> T {
        guard let requestURL = url(for: path) else { throw DeckAPIError.invalidURL }
        let encodedBody = try body.map { try encoder.encode($0) }
        let (data, _) = try await performRequest(url: requestURL, method: method, body: encodedBody)
        return try decoder.decode(T.self, from: data)
    }

    private func requestNoContent(
        _ path: String,
        method: String = "GET",
        body: (any Encodable)? = nil
    ) async throws {
        guard let requestURL = url(for: path) else { throw DeckAPIError.invalidURL }
        let encodedBody = try body.map { try encoder.encode($0) }
        _ = try await performRequest(url: requestURL, method: method, body: encodedBody)
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
        try validate(response: response, data: data)
        return (data, response)
    }

    /// Maps a non-2xx response to a `DeckAPIError`.
    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw DeckAPIError.invalidResponse }
        if http.statusCode == 304 { throw DeckAPIError.notModified }
        if http.statusCode == 400, let err = try? decoder.decode(APIErrorResponse.self, from: data) {
            throw DeckAPIError.badRequest(err.message)
        }
        if http.statusCode == 401 { throw DeckAPIError.unauthorized }
        if http.statusCode == 403 { throw DeckAPIError.permissionDenied }
        guard (200 ... 299).contains(http.statusCode) else {
            throw DeckAPIError.httpStatus(http.statusCode)
        }
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
        try await request(
            "boards/\(id)",
            method: "PUT",
            body: UpdateBoardRequest(title: title, color: color, archived: archived)
        )
    }

    func deleteBoard(id: Int) async throws {
        try await requestNoContent("boards/\(id)", method: "DELETE")
    }

    func undoDeleteBoard(id: Int) async throws {
        try await requestNoContent("boards/\(id)/undo_delete", method: "POST")
    }

    // MARK: - Stacks

    func getStacks(boardId: Int) async throws -> [Stack] {
        guard let url = url(for: "boards/\(boardId)/stacks") else { throw DeckAPIError.invalidURL }
        let (data, _) = try await performRequest(url: url, method: "GET")
        return try decodeStacks(from: data, context: "stacks")
    }

    private func decodingErrorDescription(_ error: DecodingError) -> String {
        switch error {
        case let .keyNotFound(key, context):
            return "missing key '\(key.stringValue)' at \(context.codingPath.map(\.stringValue).joined(separator: "."))"
        case let .typeMismatch(type, context):
            return "type mismatch for \(type) at \(context.codingPath.map(\.stringValue).joined(separator: "."))"
        case let .valueNotFound(type, context):
            return "nil value for \(type) at \(context.codingPath.map(\.stringValue).joined(separator: "."))"
        case let .dataCorrupted(context):
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
        guard let url = url(for: "boards/\(boardId)/stacks/archived") else { throw DeckAPIError.invalidURL }
        let (data, _) = try await performRequest(url: url, method: "GET")
        return try decodeStacks(from: data, context: "archived stacks")
    }

    /// Decodes a `[Stack]` from raw response data, trying direct decode first then
    /// OCS wrapper formats. `context` is used only in error messages.
    private func decodeStacks(from data: Data, context: String) throws -> [Stack] {
        do {
            return try decoder.decode([Stack].self, from: data)
        } catch let arrayError as DecodingError {
            if let wrapper = try? decoder.decode(OCSStacksWrapper.self, from: data) { return wrapper.data }
            if let ocs = try? decoder.decode(OCSStacksEnvelope.self, from: data) { return ocs.ocs.data }
            let detail = decodingErrorDescription(arrayError)
            throw DeckAPIError.badRequest("Could not decode \(context): \(detail)")
        } catch {
            throw DeckAPIError.badRequest("Could not decode \(context): \(error.localizedDescription)")
        }
    }

    func createStack(boardId: Int, title: String, order: Int = 999) async throws -> Stack {
        try await request(
            "boards/\(boardId)/stacks",
            method: "POST",
            body: CreateStackRequest(title: title, order: order)
        )
    }

    func updateStack(boardId: Int, stackId: Int, title: String?, order: Int?) async throws -> Stack {
        try await request(
            "boards/\(boardId)/stacks/\(stackId)",
            method: "PUT",
            body: UpdateStackRequest(title: title, order: order)
        )
    }

    func deleteStack(boardId: Int, stackId: Int) async throws {
        try await requestNoContent("boards/\(boardId)/stacks/\(stackId)", method: "DELETE")
    }

    // MARK: - Cards

    func getCard(boardId: Int, stackId: Int, cardId: Int) async throws -> Card {
        let path = "boards/\(boardId)/stacks/\(stackId)/cards/\(cardId)"
        guard let requestURL = url(for: path) else { throw DeckAPIError.invalidURL }
        let (data, _) = try await performRequest(url: requestURL, method: "GET")
        return try decodeCard(from: data, context: "card response")
    }

    /// Decodes a `Card` from raw response data, trying direct decode first then
    /// OCS wrapper formats. `context` is used only in the error message.
    private func decodeCard(from data: Data, context: String) throws -> Card {
        if let card = try? decoder.decode(Card.self, from: data) {
            return card
        }
        if let wrapper = try? decoder.decode(OCSCardWrapper.self, from: data) {
            return wrapper.data
        }
        if let envelope = try? decoder.decode(OCSCardEnvelope.self, from: data) {
            return envelope.ocs.data
        }
        throw DeckAPIError.badRequest("Could not decode \(context)")
    }

    func createCard(
        boardId: Int,
        stackId: Int,
        title: String,
        description: String? = nil,
        order: Int = 999,
        duedate: String? = nil
    ) async throws
        -> Card {
        try await request(
            "boards/\(boardId)/stacks/\(stackId)/cards",
            method: "POST",
            body: CreateCardRequest(
                title: title,
                type: "plain",
                order: order,
                description: description,
                duedate: duedate
            )
        )
    }

    /// Saves `card`'s current state. Deck's update endpoint requires `owner` and overwrites every field
    /// it is given or defaults (a missing `duedate`/`done` clears them, a missing `order` becomes 0),
    /// so the whole card is always sent rather than just the edited fields.
    func updateCard(boardId: Int, stackId: Int, card: Card) async throws -> Card {
        try await request(
            "boards/\(boardId)/stacks/\(stackId)/cards/\(card.id)",
            method: "PUT",
            body: UpdateCardRequest(card: card, fallbackOwner: username)
        )
    }

    func deleteCard(boardId: Int, stackId: Int, cardId: Int) async throws {
        try await requestNoContent("boards/\(boardId)/stacks/\(stackId)/cards/\(cardId)", method: "DELETE")
    }

    func reorderCard(boardId: Int, stackId: Int, cardId: Int, order: Int, newStackId: Int?) async throws -> Card {
        let body = try encoder.encode(ReorderCardRequest(order: order, stackId: newStackId))
        let paths = [
            "cards/\(cardId)/reorder",
            "boards/\(boardId)/stacks/\(stackId)/cards/\(cardId)/reorder",
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
            true
        default:
            false
        }
    }

    private func decodeReorderedCardResponse(
        data: Data,
        boardId: Int,
        stackId: Int,
        newStackId: Int?,
        cardId: Int
    ) async throws
        -> Card {
        if data.isEmpty {
            return try await getCard(boardId: boardId, stackId: newStackId ?? stackId, cardId: cardId)
        }

        if let card = try? decodeCard(from: data, context: "reorder response") {
            return card
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
        try await requestNoContent(
            "boards/\(boardId)/stacks/\(stackId)/cards/\(cardId)/assignLabel",
            method: "PUT",
            body: LabelIdRequest(labelId: labelId)
        )
    }

    func removeLabel(boardId: Int, stackId: Int, cardId: Int, labelId: Int) async throws {
        try await requestNoContent(
            "boards/\(boardId)/stacks/\(stackId)/cards/\(cardId)/removeLabel",
            method: "PUT",
            body: LabelIdRequest(labelId: labelId)
        )
    }

    // MARK: - Labels

    /// Creates a new label on the board. Returns the created label (or reload board to get it).
    func createLabel(boardId: Int, title: String, color: String = "31CC7C") async throws -> DeckLabel {
        try await request(
            "boards/\(boardId)/labels",
            method: "POST",
            body: CreateLabelRequest(title: title, color: color)
        )
    }

    // MARK: - Attachments

    // Attachments use Deck's internal web routes first (what the Deck web UI uses: they handle both
    // `file` and `deck_file` attachments) and fall back to REST API v1.0 only when the internal route
    // does not exist on the server. Once a request has reached a route that exists, its result is final,
    // so an upload is never sent twice and the real error is reported.

    private struct OCSAttachmentsWrapper: Decodable {
        let data: [Attachment]
    }

    private struct OCSAttachmentsEnvelope: Decodable {
        let ocs: OCSAttachmentsWrapper
    }

    /// Runs `internalRoute`, falling back to `restRoute` only when the internal route is missing (404/405).
    private func withRESTFallback<T>(
        _ internalRoute: () async throws -> T,
        restRoute: () async throws -> T
    ) async throws
        -> T {
        do {
            return try await internalRoute()
        } catch let error as DeckAPIError where error.isMissingRoute {
            return try await restRoute()
        }
    }

    /// Fetches the list of attachments for a card.
    func getAttachments(boardId: Int, stackId: Int, cardId: Int) async throws -> [Attachment] {
        try await withRESTFallback {
            try await fetchAttachments(at: deckAppURL(for: "cards/\(cardId)/attachments"))
        } restRoute: {
            try await fetchAttachments(at: url(for: "boards/\(boardId)/stacks/\(stackId)/cards/\(cardId)/attachments"))
        }
    }

    private func fetchAttachments(at url: URL?) async throws -> [Attachment] {
        guard let url else { throw DeckAPIError.invalidURL }
        let (data, _) = try await performRequest(url: url, method: "GET")
        guard let attachments = decodeAttachments(from: data) else {
            throw DeckAPIError.badRequest("Could not decode attachments response")
        }
        return attachments
    }

    /// Decodes an attachment list from the response envelopes Deck uses, or returns `nil` if the
    /// response is not an attachment list (as opposed to an empty one).
    private func decodeAttachments(from data: Data) -> [Attachment]? {
        if let attachments = try? decoder.decode([Attachment].self, from: data) {
            return attachments
        }
        if let wrapper = try? decoder.decode(OCSAttachmentsWrapper.self, from: data) {
            return wrapper.data
        }
        if let envelope = try? decoder.decode(OCSAttachmentsEnvelope.self, from: data) {
            return envelope.ocs.data
        }
        // Lenient fallback: decode the entries that parse and skip any that don't.
        let parsed = try? JSONSerialization.jsonObject(with: data)
        let entries: [[String: Any]]? = if let array = parsed as? [[String: Any]] {
            array
        } else if let object = parsed as? [String: Any] {
            (object["data"] as? [[String: Any]])
                ?? ((object["ocs"] as? [String: Any])?["data"] as? [[String: Any]])
        } else {
            nil
        }
        return entries?.compactMap { dict -> Attachment? in
            guard let jsonData = try? JSONSerialization.data(withJSONObject: dict) else { return nil }
            return try? decoder.decode(Attachment.self, from: jsonData)
        }
    }

    /// Downloads the file content of an attachment. Returns raw binary data.
    func downloadAttachment(
        boardId: Int,
        stackId: Int,
        cardId: Int,
        attachmentId: Int,
        type: String? = nil
    ) async throws
        -> Data {
        // The internal route takes the attachment as "{type}:{id}".
        let typePrefix = type ?? "file"
        return try await withRESTFallback {
            guard let url = deckAppURL(for: "cards/\(cardId)/attachment/\(typePrefix):\(attachmentId)") else {
                throw DeckAPIError.invalidURL
            }
            return try await performRequest(url: url, method: "GET").0
        } restRoute: {
            guard let url = url(for: "boards/\(boardId)/stacks/\(stackId)/cards/\(cardId)/attachments/\(attachmentId)")
            else {
                throw DeckAPIError.invalidURL
            }
            return try await performRequest(url: url, method: "GET").0
        }
    }

    /// Uploads a file as an attachment to a card.
    ///
    /// Returns the created attachment, or `nil` if the server accepted the upload but its response
    /// could not be decoded (the upload is not retried in that case, which would duplicate it).
    @discardableResult
    func uploadAttachment(
        boardId: Int,
        stackId: Int,
        cardId: Int,
        fileURL: URL,
        filename: String
    ) async throws
        -> Attachment? {
        let boundary = "Boundary-\(UUID().uuidString)"
        let bodyFile = try Self.writeMultipartBody(fileURL: fileURL, filename: filename, boundary: boundary)
        defer { try? FileManager.default.removeItem(at: bodyFile) }

        let data = try await withRESTFallback {
            guard let url = deckAppURL(for: "cards/\(cardId)/attachment") else { throw DeckAPIError.invalidURL }
            return try await performMultipartUpload(url: url, bodyFile: bodyFile, boundary: boundary)
        } restRoute: {
            let path = "boards/\(boardId)/stacks/\(stackId)/cards/\(cardId)/attachments"
            guard let base = url(for: path),
                  var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
                throw DeckAPIError.invalidURL
            }
            components.queryItems = [URLQueryItem(name: "type", value: "file")]
            guard let url = components.url else { throw DeckAPIError.invalidURL }
            return try await performMultipartUpload(url: url, bodyFile: bodyFile, boundary: boundary)
        }
        return try? decoder.decode(Attachment.self, from: data)
    }

    /// Writes a `multipart/form-data` body holding `fileURL` to a temporary file, streaming the file
    /// in chunks so large attachments are not loaded into memory.
    static func writeMultipartBody(fileURL: URL, filename: String, boundary: String) throws -> URL {
        let bodyFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("deck-upload-\(UUID().uuidString)")
        guard FileManager.default.createFile(atPath: bodyFile.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        do {
            let output = try FileHandle(forWritingTo: bodyFile)
            defer { try? output.close() }
            let input = try FileHandle(forReadingFrom: fileURL)
            defer { try? input.close() }

            let header = "--\(boundary)\r\n"
                + "Content-Disposition: form-data; name=\"file\"; filename=\"\(multipartQuoted(filename))\"\r\n"
                + "Content-Type: application/octet-stream\r\n\r\n"
            try output.write(contentsOf: Data(header.utf8))
            while let chunk = try input.read(upToCount: 1 << 20), !chunk.isEmpty {
                try output.write(contentsOf: chunk)
            }
            try output.write(contentsOf: Data("\r\n--\(boundary)--\r\n".utf8))
        } catch {
            try? FileManager.default.removeItem(at: bodyFile)
            throw error
        }
        return bodyFile
    }

    /// Escapes a value for a quoted `Content-Disposition` parameter (RFC 7578 §4.2 / WHATWG form encoding):
    /// `"`, CR and LF are percent-encoded so a filename cannot break out of the header.
    static func multipartQuoted(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\"", with: "%22")
            .replacingOccurrences(of: "\r", with: "%0D")
            .replacingOccurrences(of: "\n", with: "%0A")
    }

    /// Uploads a prepared multipart body file to `url` with the standard Deck headers and returns the
    /// response body on success.
    private func performMultipartUpload(url: URL, bodyFile: URL, boundary: String) async throws -> Data {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("true", forHTTPHeaderField: "OCS-APIRequest")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(authHeader, forHTTPHeaderField: "Authorization")
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await session.upload(for: req, fromFile: bodyFile)
        try validate(response: response, data: data)
        return data
    }

    /// Deletes an attachment from a card.
    func deleteAttachment(
        boardId: Int,
        stackId: Int,
        cardId: Int,
        attachmentId: Int,
        type: String? = nil
    ) async throws {
        let typePrefix = type ?? "file"
        try await withRESTFallback {
            guard let url = deckAppURL(for: "cards/\(cardId)/attachment/\(typePrefix):\(attachmentId)") else {
                throw DeckAPIError.invalidURL
            }
            _ = try await performRequest(url: url, method: "DELETE")
        } restRoute: {
            try await requestNoContent(
                "boards/\(boardId)/stacks/\(stackId)/cards/\(cardId)/attachments/\(attachmentId)",
                method: "DELETE"
            )
        }
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

/// Body for `PUT /boards/{boardId}/stacks/{stackId}/cards/{cardId}`.
/// See https://github.com/nextcloud/deck/blob/main/docs/API.md (Update card details).
struct UpdateCardRequest: Encodable {
    let title: String
    let description: String
    let type: String
    let owner: String
    let order: Int
    let duedate: String?
    let startdate: String?
    let done: String?

    /// `fallbackOwner` (the signed-in user) is used when the card was decoded without an owner,
    /// because the server rejects an update with an empty one.
    init(card: Card, fallbackOwner: String) {
        self.title = card.title
        self.description = card.description ?? ""
        self.type = card.type ?? "plain"
        self.owner = card.owner.flatMap { $0.isEmpty ? nil : $0 } ?? fallbackOwner
        self.order = card.order
        self.duedate = card.duedate
        self.startdate = card.startdate
        self.done = card.done
    }

    enum CodingKeys: String, CodingKey {
        case title, description, type, owner, order, duedate, startdate, done
    }

    /// Dates are always encoded, as `null` when unset, so the body states exactly what the card should be.
    /// `archived` is deliberately omitted: the server leaves it unchanged, but rejects `true` for an
    /// already-archived card.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(title, forKey: .title)
        try c.encode(description, forKey: .description)
        try c.encode(type, forKey: .type)
        try c.encode(owner, forKey: .owner)
        try c.encode(order, forKey: .order)
        try c.encode(duedate, forKey: .duedate)
        try c.encode(startdate, forKey: .startdate)
        try c.encode(done, forKey: .done)
    }
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
    /// The app password was rejected: revoked from Nextcloud's security settings, or expired.
    case unauthorized
    case permissionDenied
    case httpStatus(Int)

    /// The route does not exist on this server (as opposed to the request failing on a route that does).
    var isMissingRoute: Bool {
        switch self {
        case .httpStatus(404), .httpStatus(405): true
        default: false
        }
    }

    var errorDescription: String? {
        switch self {
        case .invalidURL: "Invalid URL"
        case .invalidResponse: "Invalid response"
        case .notModified: "Not modified"
        case let .badRequest(msg): msg
        case .unauthorized:
            "Your Nextcloud session has ended — the app password may have been revoked. Please sign in again."
        case .permissionDenied: "Permission denied"
        case let .httpStatus(code): "HTTP \(code)"
        }
    }
}
