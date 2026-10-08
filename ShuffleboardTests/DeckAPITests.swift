import Foundation
import XCTest
@testable import Shuffleboard

/// Requests `DeckAPI` sends and how it maps responses, against `StubURLProtocol`.
final class DeckAPITests: XCTestCase {
    private var api: DeckAPI!
    private let attachments = "/index.php/apps/deck/api/v1.1/boards/1/stacks/2/cards/3/attachments"
    private var fileURL: URL!

    override func setUpWithError() throws {
        StubURLProtocol.reset()
        api = DeckAPI(serverURL: testServer, username: "rob", appPassword: "pw", session: StubURLProtocol.session())
        fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("deck-test-\(UUID().uuidString).txt")
        try Data("hello deck".utf8).write(to: fileURL)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: fileURL)
        StubURLProtocol.reset()
    }

    private var lines: [String] {
        StubURLProtocol.requests.map(\.line)
    }

    // MARK: - Errors

    func testUnauthorizedIsMapped() async {
        StubURLProtocol.handler = { _ in .status(401) }
        do {
            _ = try await api.getBoards()
            XCTFail("expected an error")
        } catch {
            guard case DeckAPIError.unauthorized = error else { return XCTFail("got \(error)") }
        }
    }

    func testForbiddenIsPermissionDenied() async {
        StubURLProtocol.handler = { _ in .status(403) }
        do {
            _ = try await api.getStacks(boardId: 1)
            XCTFail("expected an error")
        } catch {
            guard case DeckAPIError.permissionDenied = error else { return XCTFail("got \(error)") }
        }
    }

    func testBadRequestCarriesServerMessage() async {
        StubURLProtocol.handler = { _ in .json(#"{"status": 400, "message": "Title too long"}"#, status: 400) }
        do {
            _ = try await api.createStack(boardId: 1, title: "x")
            XCTFail("expected an error")
        } catch {
            guard case let DeckAPIError.badRequest(message) = error else { return XCTFail("got \(error)") }
            XCTAssertEqual(message, "Title too long")
        }
    }

    // MARK: - Cards

    func testReorderUsesDocumentedEndpoint() async throws {
        StubURLProtocol.handler = { _ in .json("[]") }
        try await api.reorderCard(boardId: 1, cardId: 3, order: 4, newStackId: 5)
        // The destination stack in the URL as well as the body: some servers take the URL's (#131).
        XCTAssertEqual(lines, ["PUT /index.php/apps/deck/api/v1.0/boards/1/stacks/5/cards/3/reorder"])
        let body = try XCTUnwrap(StubURLProtocol.requests.first?.json)
        XCTAssertEqual(body["order"] as? Int, 4)
        XCTAssertEqual(body["stackId"] as? Int, 5)
    }

    // MARK: - Attachments (API v1.1)

    func testListAttachmentsUsesV11() async throws {
        StubURLProtocol.handler = { _ in .json(#"[{"id": 1, "type": "file"}, {"id": 2, "type": "deck_file"}]"#) }
        let list = try await api.getAttachments(boardId: 1, stackId: 2, cardId: 3)
        XCTAssertEqual(list.map(\.id), [1, 2])
        XCTAssertEqual(lines, ["GET \(attachments)"])
    }

    func testListAttachmentsReportsErrors() async {
        StubURLProtocol.handler = { _ in .status(403) }
        do {
            _ = try await api.getAttachments(boardId: 1, stackId: 2, cardId: 3)
            XCTFail("expected an error, not an empty list")
        } catch {
            XCTAssertEqual(lines.count, 1)
        }
    }

    func testDownloadAndDeleteAddressAttachmentByType() async throws {
        StubURLProtocol.handler = { _ in .json("ok") }
        _ = try await api.downloadAttachment(boardId: 1, stackId: 2, cardId: 3, attachmentId: 9, type: "file")
        _ = try await api.downloadAttachment(boardId: 1, stackId: 2, cardId: 3, attachmentId: 8, type: "deck_file")
        _ = try await api.downloadAttachment(boardId: 1, stackId: 2, cardId: 3, attachmentId: 7)
        try await api.deleteAttachment(boardId: 1, stackId: 2, cardId: 3, attachmentId: 6, type: "file")
        XCTAssertEqual(lines, [
            "GET \(attachments)/file/9",
            "GET \(attachments)/deck_file/8",
            "GET \(attachments)/file/7",
            "DELETE \(attachments)/file/6",
        ])
    }

    func testUploadIsASinglePost() async throws {
        StubURLProtocol.handler = { _ in .json(#"{"id": 11, "type": "file", "data": "a.txt"}"#) }
        let attachment = try await api.uploadAttachment(
            boardId: 1, stackId: 2, cardId: 3, fileURL: fileURL, filename: "a.txt"
        )
        XCTAssertEqual(attachment?.id, 11)
        XCTAssertEqual(lines, ["POST \(attachments)"])
        let contentType = StubURLProtocol.requests.first?.header("Content-Type") ?? ""
        XCTAssertTrue(contentType.hasPrefix("multipart/form-data; boundary="), contentType)
        // Deck 1.17 and 1.18 reject an upload without a `data` field.
        XCTAssertEqual(DeckAPI.uploadFields, ["type": "file", "data": ""])
    }

    func testUploadWithUnreadableResponseIsNotRetried() async throws {
        StubURLProtocol.handler = { _ in .json("<html>ok</html>") }
        let attachment = try await api.uploadAttachment(
            boardId: 1, stackId: 2, cardId: 3, fileURL: fileURL, filename: "a.txt"
        )
        XCTAssertNil(attachment)
        XCTAssertEqual(lines.count, 1, "a second upload would duplicate the attachment")
    }

    func testMultipartBodyHasTypeFieldAndEscapedFilename() throws {
        let bodyFile = try DeckAPI.writeMultipartBody(
            fileURL: fileURL,
            filename: "evil\"\r\nX-Injected: 1.txt",
            fields: ["type": "file"],
            boundary: "B"
        )
        defer { try? FileManager.default.removeItem(at: bodyFile) }
        let body = try String(decoding: Data(contentsOf: bodyFile), as: UTF8.self)

        XCTAssertTrue(body.hasPrefix("--B\r\nContent-Disposition: form-data; name=\"type\"\r\n\r\nfile\r\n"))
        XCTAssertTrue(body.contains(#"filename="evil%22%0D%0AX-Injected: 1.txt""#))
        XCTAssertFalse(body.contains("\r\nX-Injected"))
        XCTAssertTrue(body.contains("hello deck"))
        XCTAssertTrue(body.hasSuffix("\r\n--B--\r\n"))
    }

    // MARK: - Session

    func testRevokeAppPassword() async throws {
        StubURLProtocol.handler = { _ in .json("{}") }
        try await api.revokeAppPassword()
        let request = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertEqual(request.line, "DELETE /ocs/v2.php/core/apppassword")
        XCTAssertEqual(request.header("OCS-APIRequest"), "true")
        XCTAssertEqual(request.header("Authorization"), "Basic " + Data("rob:pw".utf8).base64EncodedString())
    }

    // MARK: - Assignments (#74)

    /// Nextcloud answers a request with a session cookie as that session's user, so no request may use cookies:
    /// with one shared URLSession, a second account on the same server would act as the first.
    func testRequestsDoNotUseCookies() async throws {
        StubURLProtocol.handler = { _ in .json("[]") }
        _ = try await api.getBoards()
        _ = try? await api.uploadAttachment(boardId: 1, stackId: 2, cardId: 3, fileURL: fileURL, filename: "a.txt")
        try await api.revokeAppPassword()
        XCTAssertEqual(StubURLProtocol.requests.count, 3)
        for request in StubURLProtocol.requests {
            XCTAssertFalse(request.handlesCookies, "\(request.line) uses cookies")
        }
    }

    func testAssignAndUnassignUser() async throws {
        StubURLProtocol.handler = { _ in .json("{}") }
        try await api.assignUser(boardId: 1, stackId: 2, cardId: 3, userId: "alice")
        try await api.unassignUser(boardId: 1, stackId: 2, cardId: 3, userId: "staff", type: 1)
        XCTAssertEqual(lines, [
            "PUT /index.php/apps/deck/api/v1.0/boards/1/stacks/2/cards/3/assignUser",
            "PUT /index.php/apps/deck/api/v1.0/boards/1/stacks/2/cards/3/unassignUser",
        ])
        let bodies = StubURLProtocol.requests.compactMap(\.json)
        XCTAssertEqual(bodies.first?["userId"] as? String, "alice")
        XCTAssertEqual(bodies.first?["type"] as? Int, 0)
        XCTAssertEqual(bodies.last?["userId"] as? String, "staff")
        XCTAssertEqual(bodies.last?["type"] as? Int, 1, "a group assignment is removed as a group")
    }

    // MARK: - Conditional fetches (#79)

    func testFetchStacksReturnsTheETag() async throws {
        StubURLProtocol.handler = { _ in StubResponse(status: 200, body: Data("[]".utf8), headers: ["ETag": "\"v1\""]) }
        let fetched = try await api.fetchStacks(boardId: 1, ifNoneMatch: nil)
        XCTAssertEqual(fetched?.etag, "\"v1\"")
        XCTAssertNil(StubURLProtocol.requests.first?.header("If-None-Match"), "no condition on a full load")
    }

    func testFetchStacksIsNilWhenNotModified() async throws {
        StubURLProtocol.handler = { request in
            request.header("If-None-Match") == "\"v1\"" ? .status(304) : .json("[]")
        }
        let fetched = try await api.fetchStacks(boardId: 1, ifNoneMatch: "\"v1\"")
        XCTAssertNil(fetched, "304 means unchanged")
        XCTAssertEqual(StubURLProtocol.requests.first?.header("If-None-Match"), "\"v1\"")
    }

    func testFetchBoardsIsNilWhenNotModified() async throws {
        StubURLProtocol.handler = { request in
            request.header("If-None-Match") == "\"b1\"" ? .status(304) : .json("[]")
        }
        let fetched = try await api.fetchBoards(ifNoneMatch: "\"b1\"")
        XCTAssertNil(fetched)
    }

    // MARK: - Comments (#75)

    private static let ocsComment = """
    {"ocs": {"meta": {"status": "ok", "statuscode": 200, "message": "OK"},
     "data": {"id": 9, "message": "Hi", "actorId": "rob", "actorDisplayName": "Rob",
              "creationDateTime": "2026-10-06T09:00:00+00:00"}}}
    """

    func testCommentRequests() async throws {
        StubURLProtocol.handler = { request in
            switch request.method {
            case "GET": .json(#"{"ocs": {"meta": {}, "data": []}}"#)
            case "DELETE": .json(#"{"ocs": {"meta": {}, "data": []}}"#)
            default: .json(Self.ocsComment)
            }
        }
        _ = try await api.getComments(cardId: 5, offset: 20)
        let added = try await api.addComment(cardId: 5, message: "Hi")
        _ = try await api.updateComment(cardId: 5, commentId: 9, message: "Hello")
        try await api.deleteComment(cardId: 5, commentId: 9)

        let base = "/ocs/v2.php/apps/deck/api/v1.0/cards/5/comments"
        XCTAssertEqual(lines, [
            "GET \(base)?limit=20&offset=20",
            "POST \(base)",
            "PUT \(base)/9",
            "DELETE \(base)/9",
        ])
        XCTAssertEqual(added.id, 9)
        XCTAssertEqual(StubURLProtocol.requests[1].json?["message"] as? String, "Hi")
        XCTAssertEqual(StubURLProtocol.requests[2].json?["message"] as? String, "Hello")
        XCTAssertEqual(StubURLProtocol.requests[1].header("OCS-APIRequest"), "true")
    }

    func testOCSErrorMessagesAreReported() async {
        StubURLProtocol.handler = { _ in
            .json(
                #"{"ocs": {"meta": {"status": "failure", "statuscode": 404, "message": "No comment found"}, "data": []}}"#,
                status: 404
            )
        }
        do {
            _ = try await api.updateComment(cardId: 5, commentId: 9, message: "x")
            XCTFail("expected an error")
        } catch {
            guard case let DeckAPIError.badRequest(message) = error else { return XCTFail("got \(error)") }
            XCTAssertEqual(message, "No comment found")
        }
    }

    // MARK: - Editing boards (#133)

    func testEditingABoardSendsEveryField() async throws {
        StubURLProtocol.handler = { _ in .json(#"{"id": 1, "title": "Renamed", "color": "9C59B6", "archived": true}"#) }
        let board = try await api.updateBoard(id: 1, title: "Renamed", color: "9C59B6", archived: true)
        XCTAssertEqual(board.title, "Renamed")
        XCTAssertEqual(lines, ["PUT /index.php/apps/deck/api/v1.0/boards/1"])
        let body = try XCTUnwrap(StubURLProtocol.requests.first?.json)
        XCTAssertEqual(body["title"] as? String, "Renamed")
        XCTAssertEqual(body["color"] as? String, "9C59B6")
        // Deck takes a missing `archived` as false, which would unarchive the board.
        XCTAssertEqual(body["archived"] as? Bool, true)
    }

    // MARK: - Archive (#76)

    func testArchiveRequests() async throws {
        StubURLProtocol.handler = { _ in .json("[]") }
        try await api.archiveCard(boardId: 1, stackId: 2, cardId: 3)
        try await api.unarchiveCard(boardId: 1, stackId: 2, cardId: 3)
        _ = try await api.getArchivedStacks(boardId: 1)
        XCTAssertEqual(lines, [
            "PUT /index.php/apps/deck/api/v1.0/boards/1/stacks/2/cards/3/archive",
            "PUT /index.php/apps/deck/api/v1.0/boards/1/stacks/2/cards/3/unarchive",
            "GET /index.php/apps/deck/api/v1.0/boards/1/stacks/archived",
        ])
    }

    // MARK: - Sharing (#80)

    func testShareRequests() async throws {
        StubURLProtocol.handler = { _ in .json("{}") }
        try await api.addShare(boardId: 1, type: .group, participant: "staff", permissions: SharePermissions())
        try await api.updateShare(boardId: 1, aclId: 7, permissions: SharePermissions(edit: true, manage: true))
        try await api.removeShare(boardId: 1, aclId: 7)
        XCTAssertEqual(lines, [
            "POST /index.php/apps/deck/api/v1.0/boards/1/acl",
            "PUT /index.php/apps/deck/api/v1.0/boards/1/acl/7",
            "DELETE /index.php/apps/deck/api/v1.0/boards/1/acl/7",
        ])
        let added = try XCTUnwrap(StubURLProtocol.requests[0].json)
        XCTAssertEqual(added["type"] as? Int, 1)
        XCTAssertEqual(added["participant"] as? String, "staff")
        XCTAssertEqual(added["permissionEdit"] as? Bool, false, "new shares start read-only")
        let updated = try XCTUnwrap(StubURLProtocol.requests[1].json)
        XCTAssertEqual(updated["permissionEdit"] as? Bool, true)
        XCTAssertEqual(updated["permissionShare"] as? Bool, false)
        XCTAssertEqual(updated["permissionManage"] as? Bool, true)
    }

    func testShareeSearchMatchesDecksWebUI() async throws {
        StubURLProtocol
            .handler = { _ in
                .json(#"{"ocs": {"meta": {}, "data": [{"id": "alice", "label": "Alice", "source": "users"}]}}"#)
            }
        let found = try await api.searchSharees("ali")
        XCTAssertEqual(found.map(\.participantId), ["alice"])
        let request = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertEqual(request.path, "/ocs/v2.php/core/autocomplete/get")
        let items = URLComponents(string: "x:/?" + (request.query ?? ""))?.queryItems ?? []
        XCTAssertEqual(items.first { $0.name == "search" }?.value, "ali")
        XCTAssertEqual(items.first { $0.name == "itemType" }?.value, "deck")
        XCTAssertEqual(items.filter { $0.name == "shareTypes[]" }.compactMap(\.value), ["0", "1", "6", "7"])
    }
}
