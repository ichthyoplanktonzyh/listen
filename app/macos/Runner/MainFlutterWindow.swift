import Cocoa
import AVFoundation
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var shadowingRecorder: ShadowingRecorder?
  private var realtimeAudio: RealtimeAudioBridge?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    shadowingRecorder = ShadowingRecorder(messenger: flutterViewController.engine.binaryMessenger)
    realtimeAudio = RealtimeAudioBridge(messenger: flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
  }
}

private final class RealtimeAudioBridge: NSObject, FlutterStreamHandler {
  private let methodChannel: FlutterMethodChannel
  private let eventChannel: FlutterEventChannel
  private let engine = AVAudioEngine()
  private let player = AVAudioPlayerNode()
  private var eventSink: FlutterEventSink?
  private var streamConverter: AVAudioConverter?
  private var fileConverter: AVAudioConverter?
  private var recordingFile: AVAudioFile?
  private var recordingPath: String?
  private var recordedFrames: AVAudioFramePosition = 0
  private var inputTapInstalled = false

  init(messenger: FlutterBinaryMessenger) {
    methodChannel = FlutterMethodChannel(name: "app.llplayernext/realtime_audio", binaryMessenger: messenger)
    eventChannel = FlutterEventChannel(name: "app.llplayernext/realtime_audio_input", binaryMessenger: messenger)
    super.init()
    eventChannel.setStreamHandler(self)
    methodChannel.setMethodCallHandler { [weak self] call, result in self?.handle(call, result: result) }
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "start": start(call, result: result)
    case "playPcm": playPcm(call.arguments, result: result)
    case "stopPlayback": player.stop(); player.play(); result(true)
    case "shutdown": cleanup(discard: false); result(true)
    case "stop": stop(discard: false, result: result)
    case "cancel": stop(discard: true, result: result)
    default: result(FlutterMethodNotImplemented)
    }
  }

  private func start(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
      result(FlutterError(code: "microphone_permission", message: "Microphone permission is not granted.", details: nil)); return
    }
    guard recordingFile == nil,
          let arguments = call.arguments as? [String: Any],
          let path = arguments["path"] as? String else {
      result(FlutterError(code: "invalid_state", message: "Realtime audio is active or path is missing.", details: nil)); return
    }
    guard let streamFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 24_000, channels: 1, interleaved: true),
          let fileFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: true),
          let playbackFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 24_000, channels: 1, interleaved: false) else {
      result(FlutterError(code: "audio_format", message: "Required PCM formats are unavailable.", details: nil)); return
    }
    let url = URL(fileURLWithPath: path)
    do {
      try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      let input = engine.inputNode
      let inputFormat = input.outputFormat(forBus: 0)
      streamConverter = AVAudioConverter(from: inputFormat, to: streamFormat)
      fileConverter = AVAudioConverter(from: inputFormat, to: fileFormat)
      recordingFile = try AVAudioFile(forWriting: url, settings: fileFormat.settings, commonFormat: .pcmFormatInt16, interleaved: true)
      recordingPath = path
      recordedFrames = 0
      engine.attach(player)
      engine.connect(player, to: engine.mainMixerNode, format: playbackFormat)
      input.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in self?.consume(buffer, streamFormat: streamFormat, fileFormat: fileFormat) }
      inputTapInstalled = true
      engine.prepare()
      try engine.start()
      player.play()
      result(true)
    } catch {
      cleanup(discard: true)
      result(FlutterError(code: "realtime_audio_start_failed", message: error.localizedDescription, details: nil))
    }
  }

  private func converted(_ input: AVAudioPCMBuffer, converter: AVAudioConverter?, format: AVAudioFormat) -> AVAudioPCMBuffer? {
    guard let converter,
          let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(Double(input.frameLength) * format.sampleRate / input.format.sampleRate + 32)) else { return nil }
    var supplied = false
    var error: NSError?
    let status = converter.convert(to: output, error: &error) { _, state in
      if supplied { state.pointee = .noDataNow; return nil }
      supplied = true; state.pointee = .haveData; return input
    }
    return status == .error ? nil : output
  }

  private func consume(_ input: AVAudioPCMBuffer, streamFormat: AVAudioFormat, fileFormat: AVAudioFormat) {
    if let stream = converted(input, converter: streamConverter, format: streamFormat),
       let samples = stream.int16ChannelData?[0] {
      let data = Data(bytes: samples, count: Int(stream.frameLength) * MemoryLayout<Int16>.size)
      DispatchQueue.main.async { [weak self] in self?.eventSink?(FlutterStandardTypedData(bytes: data)) }
    }
    if let local = converted(input, converter: fileConverter, format: fileFormat) {
      try? recordingFile?.write(from: local)
      recordedFrames += AVAudioFramePosition(local.frameLength)
    }
  }

  private func playPcm(_ arguments: Any?, result: FlutterResult) {
    let data: Data? = (arguments as? FlutterStandardTypedData)?.data ?? (arguments as? [String: Any]).flatMap { ($0["pcm"] as? FlutterStandardTypedData)?.data }
    guard let data, !data.isEmpty,
          let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 24_000, channels: 1, interleaved: false),
          let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(data.count / 2)),
          let output = buffer.floatChannelData?[0] else { result(false); return }
    buffer.frameLength = buffer.frameCapacity
    data.withUnsafeBytes { raw in
      let samples = raw.bindMemory(to: Int16.self)
      for index in 0..<samples.count { output[index] = Float(samples[index]) / 32768.0 }
    }
    player.scheduleBuffer(buffer)
    result(true)
  }

  private func stop(discard: Bool, result: FlutterResult) {
    guard let path = recordingPath else { result(false); return }
    let durationMs = Int(Double(recordedFrames) / 16_000.0 * 1000.0)
    if discard {
      cleanup(discard: true)
      result(true)
    } else {
      if inputTapInstalled { engine.inputNode.removeTap(onBus: 0); inputTapInstalled = false }
      recordingFile = nil; recordingPath = nil; streamConverter = nil; fileConverter = nil; recordedFrames = 0
      result(["path": path, "durationMs": durationMs])
    }
  }

  private func cleanup(discard: Bool) {
    if inputTapInstalled { engine.inputNode.removeTap(onBus: 0); inputTapInstalled = false }
    player.stop()
    engine.stop()
    if engine.attachedNodes.contains(player) { engine.detach(player) }
    let path = recordingPath
    recordingFile = nil; recordingPath = nil; streamConverter = nil; fileConverter = nil; recordedFrames = 0
    if discard, let path { try? FileManager.default.removeItem(atPath: path) }
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
