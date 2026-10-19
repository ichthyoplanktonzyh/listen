import Cocoa
import FlutterMacOS
import XCTest
@testable import listen

class RunnerTests: XCTestCase {

  func testRealtimePreRollSuffixUsesAnOffsetAfterFrontTrimming() {
    var preRoll = Data((0..<100).map(UInt8.init))
    preRoll.removeFirst(60)

    let captured = realtimePreRollSuffix(preRoll, droppingByteCount: 10)

    XCTAssertEqual(Array(captured), Array((70..<100).map(UInt8.init)))
  }

  func testRealtimePreRollSuffixClampsOffsetsToAvailableBytes() {
    var preRoll = Data((0..<10).map(UInt8.init))
    preRoll.removeFirst(4)

    XCTAssertEqual(
      Array(realtimePreRollSuffix(preRoll, droppingByteCount: -1)),
      Array((4..<10).map(UInt8.init))
    )
    XCTAssertTrue(
      realtimePreRollSuffix(preRoll, droppingByteCount: 100).isEmpty
    )
  }

}
