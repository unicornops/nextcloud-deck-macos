import Foundation
import XCTest
@testable import Shuffleboard

/// Board sharing (#80): search results, and which changes the signed-in user may make.
final class SharingTests: XCTestCase {
    private func board(permissions: String, acl: String = "[]") throws -> Board {
        try JSONDecoder().decode(Board.self, from: Data("""
        {"id": 1, "title": "B", "archived": false, "labels": [],
         "owner": {"uid": "rob", "displayname": "Rob"}, "acl": \(acl),
         "permissions": \(permissions)}
        """.utf8))
    }

    private let owner = #"{"PERMISSION_READ": true, "PERMISSION_EDIT": true, "PERMISSION_MANAGE": true, "PERMISSION_SHARE": true}"#
    private let sharer = #"{"PERMISSION_READ": true, "PERMISSION_EDIT": true, "PERMISSION_MANAGE": false, "PERMISSION_SHARE": true}"#
    private let readOnlySharer = #"{"PERMISSION_READ": true, "PERMISSION_EDIT": false, "PERMISSION_MANAGE": false, "PERMISSION_SHARE": true}"#
    private let viewer = #"{"PERMISSION_READ": true, "PERMISSION_EDIT": false, "PERMISSION_MANAGE": false, "PERMISSION_SHARE": false}"#

    func testShareesDecodeFromAutocomplete() throws {
        let json = """
        {"ocs": {"meta": {}, "data": [
          {"id": "alice", "label": "Alice Smith", "source": "users", "shareWithDisplayNameUnique": "alice@example.com"},
          {"id": "staff", "label": "Staff", "source": "groups"},
          {"id": "abc123", "label": "Design", "source": "circles"},
          {"id": "bob@other.example", "label": "", "source": "remotes"},
          {"id": "x", "label": "Mail", "source": "emails"}
        ]}}
        """
        let sharees = try JSONDecoder().decode(OCSResponse<[Sharee]>.self, from: Data(json.utf8)).ocs.data
        XCTAssertEqual(sharees.map(\.shareType), [.user, .group, .team, .federated, nil])
        XCTAssertEqual(sharees[0].detail, "alice@example.com")
        XCTAssertEqual(sharees[3].label, "bob@other.example", "falls back to the id")
        XCTAssertNotEqual(sharees[0].id, Sharee(participantId: "alice", label: "", source: "groups").id)
    }

    func testOwnerCanDoEverything() throws {
        let board = try board(permissions: owner)
        XCTAssertTrue(board.canShare)
        XCTAssertTrue(board.canManage)
        XCTAssertTrue(SharePermissions.Right.allCases.allSatisfy(board.canGrant))
    }

    func testSharerWithoutManageCanOnlyPassOnRightsTheyHold() throws {
        let editor = try board(permissions: sharer)
        XCTAssertTrue(editor.canShare)
        XCTAssertFalse(editor.canManage, "can't remove shares")
        XCTAssertTrue(editor.canGrant(.edit))
        XCTAssertTrue(editor.canGrant(.share))
        XCTAssertFalse(editor.canGrant(.manage))

        let reader = try board(permissions: readOnlySharer)
        XCTAssertFalse(reader.canGrant(.edit), "Deck drops rights the sharer doesn't hold")
        XCTAssertTrue(reader.canGrant(.share))
    }

    func testViewerCanChangeNothing() throws {
        let board = try board(permissions: viewer)
        XCTAssertFalse(board.canShare)
        XCTAssertFalse(board.canManage)
        XCTAssertFalse(SharePermissions.Right.allCases.contains(where: board.canGrant))
    }

    func testAlreadySharedMatchesIdAndType() throws {
        let board = try board(permissions: owner, acl: """
        [{"id": 1, "participant": {"uid": "alice"}, "type": 0,
          "permissionEdit": true, "permissionShare": false, "permissionManage": false}]
        """)
        XCTAssertTrue(board.isShared(with: Sharee(participantId: "alice", label: "Alice", source: "users")))
        XCTAssertFalse(board.isShared(with: Sharee(participantId: "alice", label: "Alice", source: "groups")))
        XCTAssertTrue(board.isShared(with: Sharee(participantId: "rob", label: "Rob", source: "users")), "the owner")
        XCTAssertFalse(board.isShared(with: Sharee(participantId: "bob", label: "Bob", source: "users")))
    }

    func testPermissionsSubscript() {
        var permissions = SharePermissions()
        permissions[.manage] = true
        XCTAssertEqual(permissions, SharePermissions(manage: true))
    }
}
