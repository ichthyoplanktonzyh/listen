import Cocoa
import FlutterMacOS
import AVFoundation

class MainFlutterWindow: NSWindow {
  private var shadowingRecorder: ShadowingRecorder?
  private var fullscreenBridge: FullscreenBridge?

  // Keep in step with ListenBreakpoints.minWindowWidth / minWindowHeight in
  // lib/theme/breakpoints.dart, which documents where these numbers come from.
  // test/window_min_size_test.dart fails if the two sides drift apart.
  static let contentMinimumSize = NSSize(width: 640, height: 560)

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    // Without this the window can be dragged narrower than any layout supports,
    // which repainted the AppBar overflow that #18 fixed (see #19).
    self.contentMinSize = MainFlutterWindow.contentMinimumSize

    RegisterGeneratedPlugins(registry: flutterViewController)
    shadowingRecorder = ShadowingRecorder(messenger: flutterViewController.engine.binaryMessenger)
    fullscreenBridge = FullscreenBridge(window: self, messenger: flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
  }
}

/// #25-A: the window side of the fullscreen immersive state. Dart asks for
/// system fullscreen with `setFullScreen`; the bridge pushes every actual
/// transition back through `onFullScreenChanged`, so the green traffic-light
/// button and system gestures keep the Dart immersive state in step — the
/// window is the source of truth, Dart mirrors it.
private final class FullscreenBridge: NSObject {
  private let channel: FlutterMethodChannel
  private weak var window: NSWindow?

  init(window: NSWindow, messenger: FlutterBinaryMessenger) {
    self.window = window
    channel = FlutterMethodChannel(name: "app.llplayernext/fullscreen", binaryMessenger: messenger)
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in self?.handle(call, result: result) }
    let center = NotificationCenter.default
    center.addObserver(
      self, selector: #selector(didEnterFullScreen),
      name: NSWindow.didEnterFullScreenNotification, object: window)
    center.addObserver(
      self, selector: #selector(didExitFullScreen),
      name: NSWindow.didExitFullScreenNotification, object: window)
  }

  deinit { NotificationCenter.default.removeObserver(self) }

  @objc private func didEnterFullScreen(_ notification: Notification) {
    channel.invokeMethod("onFullScreenChanged", arguments: true)
  }

  @objc private func didExitFullScreen(_ notification: Notification) {
    channel.invokeMethod("onFullScreenChanged", arguments: false)
  }

  private var isFullScreen: Bool { window?.styleMask.contains(.fullScreen) ?? false }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "setFullScreen":
      guard let desired = call.arguments as? Bool else {
        result(FlutterError(code: "invalid_arguments", message: "setFullScreen expects a Bool.", details: nil))
        return
      }
      if isFullScreen != desired { window?.toggleFullScreen(nil) }
      result(true)
    case "isFullScreen":
      result(isFullScreen)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}

private final class ShadowingRecorder: NSObject, AVAudioRecorderDelegate {
  private let channel: FlutterMethodChannel
  private var recorder: AVAudioRecorder?
  private var startedAt: Date?

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: "app.llplayernext/shadowing_recorder",
      binaryMessenger: messenger
    )
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "permissionStatus":
      result(permissionStatus())
    case "requestPermission":
      AVCaptureDevice.requestAccess(for: .audio) { granted in
        DispatchQueue.main.async { result(granted ? "granted" : "denied") }
      }
    case "openSettings":
      guard let url = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
      ) else {
        result(false)
        return
      }
      result(NSWorkspace.shared.open(url))
    case "start":
      start(call, result: result)
    case "stop":
      stop(result: result)
    case "cancel":
      cancel(result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func permissionStatus() -> String {
    switch AVCaptureDevice.authorizationStatus(for: .audio) {
    case .authorized: return "granted"
    case .denied: return "denied"
    case .restricted: return "restricted"
    case .notDetermined: return "not_determined"
    @unknown default: return "restricted"
    }
  }

  private func start(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard permissionStatus() == "granted" else {
      result(FlutterError(
        code: "microphone_permission",
        message: "Microphone permission is not granted.",
        details: permissionStatus()
      ))
      return
    }
    guard recorder == nil,
          let arguments = call.arguments as? [String: Any],
          let path = arguments["path"] as? String else {
      result(FlutterError(code: "invalid_state", message: "Recorder is already active or path is missing.", details: nil))
      return
    }
    let sampleRate = arguments["sampleRateHz"] as? Double ?? 16_000
    let url = URL(fileURLWithPath: path)
    do {
      try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      let next = try AVAudioRecorder(
        url: url,
        settings: [
          AVFormatIDKey: Int(kAudioFormatLinearPCM),
          AVSampleRateKey: sampleRate,
          AVNumberOfChannelsKey: 1,
          AVLinearPCMBitDepthKey: 16,
          AVLinearPCMIsFloatKey: false,
          AVLinearPCMIsBigEndianKey: false,
        ]
      )
      next.delegate = self
      next.isMeteringEnabled = true
      guard next.prepareToRecord(), next.record() else {
        throw NSError(domain: "ShadowingRecorder", code: 1, userInfo: [NSLocalizedDescriptionKey: "Audio recorder could not start."])
      }
      recorder = next
      startedAt = Date()
      result(true)
    } catch {
      recorder = nil
      startedAt = nil
      result(FlutterError(code: "recording_start_failed", message: error.localizedDescription, details: nil))
    }
  }

  private func stop(result: FlutterResult) {
    guard let active = recorder else {
      result(FlutterError(code: "invalid_state", message: "Recorder is not active.", details: nil))
      return
    }
    let durationMs = max(0, Int(active.currentTime * 1000.0))
    let path = active.url.path
    active.stop()
    recorder = nil
    startedAt = nil
    result(["path": path, "durationMs": durationMs])
  }

  private func cancel(result: FlutterResult) {
    guard let active = recorder else {
      result(false)
      return
    }
    let path = active.url.path
    active.stop()
    recorder = nil
    startedAt = nil
    try? FileManager.default.removeItem(atPath: path)
    result(true)
  }
}
