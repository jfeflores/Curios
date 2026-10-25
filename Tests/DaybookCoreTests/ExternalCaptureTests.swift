#if DAYBOOK_STANDALONE_TESTS
import Foundation
#else
import XCTest
#endif
@testable import DaybookCore

final class ExternalCaptureTests: XCTestCase {
    private func link(_ host: String = "add", _ arguments: [URLQueryItem], scheme: String = "curios") -> URL {
        var parts = URLComponents(); parts.scheme = scheme; parts.host = host; parts.queryItems = arguments
        return parts.url!
    }
    func testBothSchemesAndAllowListedNavigation() throws {
        for scheme in ["curios", "daybook"] {
            XCTAssertEqual(try ExternalCapture.parse(link("add", [.init(name: "title", value: " Test "), .init(name: "notes", value: "Hello\nworld")], scheme: scheme)), .add(title: "Test", notes: "Hello\nworld", schedule: nil))
            XCTAssertEqual(try ExternalCapture.parse(link("show", [.init(name: "list", value: "today")], scheme: scheme)), .show(.today))
        }
    }
    func testRejectsForeignDestructiveUnknownDuplicateAndMalformedInputs() {
        let invalid = [
            "things:///add?title=X", "https://add?title=X", "curios://delete?id=X", "curios://add?title=X&title=Y",
            "curios://add?title=X&%74itle=Y", "curios://add?title=X&completed=true", "curios://add?title=X&notes=X&when=today&extra=X",
            "curios://add?title=X&when=not-a-day", "curios://add?title=X&when=", "curios://add?title=",
            "curios://add?title=%FF", "curios://add?title=X%00Y", "curios://add?title=X&notes=Y%00Z",
            "curios://user@add?title=X", "curios://add:123?title=X", "curios://add/path?title=X", "curios://add?title=X#fragment",
            "curios://show?list=today&title=X", "curios://show?list=foreign", "curios://add?title=X&", "curios://add?title=X&notes"
        ]
        for value in invalid { XCTAssertThrowsError(try ExternalCapture.parse(URL(string: value)!)) }
    }
    func testUTF8PayloadBoundaries() throws {
        let maximumTitle = String(repeating: "a", count: ExternalCapture.maximumTitleBytes)
        let maximumNotes = String(repeating: "n", count: ExternalCapture.maximumNotesBytes)
        _ = try ExternalCapture.parse(link("add", [.init(name: "title", value: maximumTitle), .init(name: "notes", value: maximumNotes)]))
        XCTAssertThrowsError(try ExternalCapture.parse(link("add", [.init(name: "title", value: maximumTitle + "a")])))
        XCTAssertThrowsError(try ExternalCapture.parse(link("add", [.init(name: "title", value: "X"), .init(name: "notes", value: maximumNotes + "n")])))
        XCTAssertThrowsError(try ExternalCapture.parse(link("add", [.init(name: "title", value: String(repeating: "é", count: ExternalCapture.maximumTitleBytes / 2 + 1))])))
        XCTAssertThrowsError(try ExternalCapture.parse(link("add", [.init(name: "title", value: "X"), .init(name: "when", value: String(repeating: "x", count: ExternalCapture.maximumScheduleBytes + 1))])))
        XCTAssertThrowsError(try ExternalCapture.parse(URL(string: "curios://add?title=X&notes=" + String(repeating: "a", count: ExternalCapture.maximumURLBytes))!))
    }
    func testClipboardIsBoundedBeforeDraftCreation() throws {
        XCTAssertEqual(try ExternalCapture.pasteTitles(" First\n\n Second "), ["First", "Second"])
        XCTAssertEqual(try ExternalCapture.pasteTitles(String(repeating: "X\n", count: ExternalCapture.maximumPasteTasks)).count, ExternalCapture.maximumPasteTasks)
        XCTAssertThrowsError(try ExternalCapture.pasteTitles(String(repeating: "X\n", count: ExternalCapture.maximumPasteTasks + 1)))
        XCTAssertThrowsError(try ExternalCapture.pasteTitles(String(repeating: "x", count: ExternalCapture.maximumPasteBytes + 1)))
        XCTAssertThrowsError(try ExternalCapture.pasteTitles(String(repeating: "é", count: ExternalCapture.maximumTitleBytes / 2 + 1)))
    }
}
