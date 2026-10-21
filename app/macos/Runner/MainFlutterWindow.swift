import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
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
