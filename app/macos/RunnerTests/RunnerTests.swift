import Cocoa
import FlutterMacOS
import XCTest
@testable import listen

class RunnerTests: XCTestCase {

  func testWindowMinimumSizeMatchesListeningLayout() {
    XCTAssertEqual(MainFlutterWindow.contentMinimumSize.width, 640)
    XCTAssertEqual(MainFlutterWindow.contentMinimumSize.height, 560)
  }

}
