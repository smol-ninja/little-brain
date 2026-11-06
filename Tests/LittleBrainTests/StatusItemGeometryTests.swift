import XCTest
import AppKit
@testable import LittleBrain

final class StatusItemGeometryTests: XCTestCase {
    func testStatusItemOwnsItsFullMenuBarHeightIncludingTheScreenEdge() {
        // The status item's window reaches the screen edge above its inset button.
        let geometry = StatusItemGeometry(buttonFrame: NSRect(x: 908, y: 954.5, width: 66, height: 22),
                                          windowFrame: NSRect(x: 908, y: 949, width: 66, height: 33))
        for point in [NSPoint(x: 941, y: 966), NSPoint(x: 941, y: 980), NSPoint(x: 941, y: 982)] {
            XCTAssertTrue(geometry.containsActivationPoint(point), "The outside-click monitor must leave this press to the status item: \(point)")
        }
        for point in [NSPoint(x: 907, y: 982), NSPoint(x: 974, y: 982), NSPoint(x: 941, y: 948), NSPoint(x: 941, y: 983)] {
            XCTAssertFalse(geometry.containsActivationPoint(point), "Adjacent items and clicks outside the menu bar must still dismiss the panel: \(point)")
        }
    }
}
