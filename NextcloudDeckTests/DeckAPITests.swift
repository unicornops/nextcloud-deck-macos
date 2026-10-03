import Foundation
@testable import NextcloudDeck
import XCTest

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
        try await api.reorderCard(boardId: 1, stackId: 2, cardId: 3, order: 4, newStackId: 5)
        XCTAssertEqual(lines, ["PUT /index.php/apps/deck/api/v1.0/boards/1/stacks/2/cards/3/reorder"])
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
}
