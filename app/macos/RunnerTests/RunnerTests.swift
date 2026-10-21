import Cocoa
import AVFoundation
import FlutterMacOS
import XCTest
@testable import listen

class RunnerTests: XCTestCase {

  func testWindowMinimumSizeMatchesListeningLayout() {
    XCTAssertEqual(MainFlutterWindow.contentMinimumSize.width, 640)
    XCTAssertEqual(MainFlutterWindow.contentMinimumSize.height, 560)
  }

  func testRealtimeRecordingStopSnapshotRequiresAnActivePath() {
    XCTAssertNil(RealtimeRecordingStopSnapshot(path: nil, recordedFrames: 0))
  }

  func testRealtimeRecordingStopSnapshotReturnsTheTypedDartPayload() {
    let snapshot = RealtimeRecordingStopSnapshot(
      path: "/tmp/captured.wav",
      recordedFrames: 16_000
    )

    XCTAssertEqual(snapshot?.durationMs, 1_000)
    XCTAssertEqual(snapshot?.methodResult["path"] as? String, "/tmp/captured.wav")
    XCTAssertEqual(snapshot?.methodResult["durationMs"] as? Int, 1_000)
  }

}
