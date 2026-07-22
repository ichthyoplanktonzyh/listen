import Cocoa
import AVFoundation
import FlutterMacOS

func realtimePreRollSuffix(_ data: Data, droppingByteCount: Int) -> Data {
  let boundedOffset = min(data.count, max(0, droppingByteCount))
  return Data(data.dropFirst(boundedOffset))
}

class MainFlutterWindow: NSWindow {
  private var shadowingRecorder: ShadowingRecorder?
  private var realtimeAudio: RealtimeAudioBridge?

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
  private var turnRecordingFile: AVAudioFile?
  private var turnRecordingPath: String?
  private var turnRecordedFrames: AVAudioFramePosition = 0
  private var preRoll = Data()
  // Provider VAD events arrive after the detected onset. Keep enough verified
  // mono PCM to recover the provider's absolute audio timeline position.
  private let preRollByteLimit = 320_000 // 10 seconds of mono PCM16 at 16 kHz.
  private let fallbackPreRollFrames: AVAudioFramePosition = 8_000 // 500 ms.
  private let onsetPaddingFrames: AVAudioFramePosition = 4_800 // 300 ms.
  private let recordingLock = NSLock()
  private var inputTapInstalled = false
  private var voiceProcessingEnabled = false

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
    case "requestPermission":
      switch AVCaptureDevice.authorizationStatus(for: .audio) {
      case .authorized:
        result(true)
      case .notDetermined:
        AVCaptureDevice.requestAccess(for: .audio) { granted in
          DispatchQueue.main.async { result(granted) }
        }
      case .denied, .restricted:
        result(false)
      @unknown default:
        result(false)
      }
    case "start": start(call, result: result)
    case "beginTurn": beginTurn(call, result: result)
    case "endTurn": endTurn(discard: false, result: result)
    case "discardTurn": endTurn(discard: true, result: result)
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
          let path = arguments["path"] as? String,
          let inputSampleRateHz = arguments["inputSampleRateHz"] as? Int,
          inputSampleRateHz == 16_000 || inputSampleRateHz == 24_000 else {
      result(FlutterError(code: "invalid_state", message: "Realtime audio is active, path is missing, or the input sample rate is unsupported.", details: nil)); return
    }
    guard let streamFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: Double(inputSampleRateHz), channels: 1, interleaved: true),
          let fileFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: true),
          let playbackFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 24_000, channels: 1, interleaved: false) else {
      result(FlutterError(code: "audio_format", message: "Required PCM formats are unavailable.", details: nil)); return
    }
    let url = URL(fileURLWithPath: path)
    do {
      try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      let input = engine.inputNode
      engine.attach(player)
      engine.connect(player, to: engine.mainMixerNode, format: playbackFormat)
      // Voice-processing I/O must be enabled before reading the hardware input
      // format or installing the tap. It supplies Apple's AEC/NS/AGC path so
      // assistant playback is not treated as a new learner turn.
      try input.setVoiceProcessingEnabled(true)
      voiceProcessingEnabled = true
      // A tap observes the input node's output bus. Voice Processing exposes
      // that bus as an aggregate on this macOS hardware.
      let inputFormat = input.outputFormat(forBus: 0)
      streamConverter = AVAudioConverter(from: inputFormat, to: streamFormat)
      fileConverter = streamFormat.sampleRate == fileFormat.sampleRate
        ? nil
        : AVAudioConverter(from: streamFormat, to: fileFormat)
      // The macOS Voice Processing aggregate exposes nine source channels on
      // this hardware. Its implicit 9 -> 1 layout conversion produces silence,
      // even though the tap buffers contain the processed uplink signal. Make
      // the mono source explicit for transport. Local recording then reuses
      // this verified mono stream instead of independently converting 9 -> 1.
      streamConverter?.channelMap = [0]
      recordingFile = try AVAudioFile(forWriting: url, settings: fileFormat.settings, commonFormat: .pcmFormatInt16, interleaved: true)
      recordingPath = path
      recordedFrames = 0
      preRoll.removeAll(keepingCapacity: true)
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
    let stream = converted(input, converter: streamConverter, format: streamFormat)
    if let stream,
       let samples = stream.int16ChannelData?[0] {
      let data = Data(bytes: samples, count: Int(stream.frameLength) * MemoryLayout<Int16>.size)
      DispatchQueue.main.async { [weak self] in
        self?.eventSink?(FlutterStandardTypedData(bytes: data))
      }
    }
    if let stream,
       let local = fileConverter == nil
         ? stream
         : converted(stream, converter: fileConverter, format: fileFormat) {
      recordingLock.lock()
      try? recordingFile?.write(from: local)
      recordedFrames += AVAudioFramePosition(local.frameLength)
      if turnRecordingFile != nil {
        try? turnRecordingFile?.write(from: local)
        turnRecordedFrames += AVAudioFramePosition(local.frameLength)
      }
      if let samples = local.int16ChannelData?[0] {
        preRoll.append(Data(bytes: samples, count: Int(local.frameLength) * MemoryLayout<Int16>.size))
        if preRoll.count > preRollByteLimit {
          preRoll.removeFirst(preRoll.count - preRollByteLimit)
        }
      }
      recordingLock.unlock()
    }
  }

  private func beginTurn(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard recordingFile != nil,
          let arguments = call.arguments as? [String: Any],
          let path = arguments["path"] as? String,
          let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: true)
    else {
      result(FlutterError(code: "invalid_state", message: "Realtime session is inactive or turn path is missing.", details: nil)); return
    }
    recordingLock.lock()
    defer { recordingLock.unlock() }
    guard turnRecordingFile == nil else {
      result(FlutterError(code: "turn_active", message: "A realtime learner turn is already being recorded.", details: nil)); return
    }
    do {
      let url = URL(fileURLWithPath: path)
      try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      let file = try AVAudioFile(forWriting: url, settings: format.settings, commonFormat: .pcmFormatInt16, interleaved: true)
      let audioStartMs = arguments["audioStartMs"] as? Int
      let bufferedFrames = AVAudioFramePosition(preRoll.count / 2)
      let availableStartFrame = max(0, recordedFrames - bufferedFrames)
      let requestedStartFrame: AVAudioFramePosition
      if let audioStartMs {
        requestedStartFrame = max(0, AVAudioFramePosition(audioStartMs * 16) - onsetPaddingFrames)
      } else {
        requestedStartFrame = max(0, recordedFrames - fallbackPreRollFrames)
      }
      let captureStartFrame = min(recordedFrames, max(availableStartFrame, requestedStartFrame))
      let skippedFrames = captureStartFrame - availableStartFrame
      let captureByteOffset = Int(skippedFrames) * MemoryLayout<Int16>.size
      let capturedPreRoll = realtimePreRollSuffix(preRoll, droppingByteCount: captureByteOffset)
      if !capturedPreRoll.isEmpty,
         let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(capturedPreRoll.count / 2)),
         let samples = buffer.int16ChannelData?[0] {
        buffer.frameLength = buffer.frameCapacity
        capturedPreRoll.withUnsafeBytes { raw in
          if let baseAddress = raw.baseAddress {
            memcpy(samples, baseAddress, capturedPreRoll.count)
          }
        }
        try file.write(from: buffer)
      }
      turnRecordingFile = file
      turnRecordingPath = path
      turnRecordedFrames = AVAudioFramePosition(capturedPreRoll.count / 2)
      result(true)
    } catch {
      result(FlutterError(code: "realtime_turn_start_failed", message: error.localizedDescription, details: nil))
    }
  }

  private func endTurn(discard: Bool, result: @escaping FlutterResult) {
    recordingLock.lock()
    guard let path = turnRecordingPath else {
      recordingLock.unlock()
      result(FlutterError(code: "no_active_turn", message: "No realtime learner turn is active.", details: nil)); return
    }
    let durationMs = Int(Double(turnRecordedFrames) / 16_000.0 * 1000.0)
    turnRecordingFile = nil
    turnRecordingPath = nil
    turnRecordedFrames = 0
    recordingLock.unlock()
    if discard {
      try? FileManager.default.removeItem(atPath: path)
      result(true)
    } else {
      result(["path": path, "durationMs": durationMs])
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
    if voiceProcessingEnabled {
      try? engine.inputNode.setVoiceProcessingEnabled(false)
      voiceProcessingEnabled = false
    }
    if engine.attachedNodes.contains(player) { engine.detach(player) }
    let path = recordingPath
    recordingLock.lock()
    let turnPath = turnRecordingPath
    turnRecordingFile = nil; turnRecordingPath = nil; turnRecordedFrames = 0
    preRoll.removeAll(keepingCapacity: false)
    recordingFile = nil; recordingPath = nil; streamConverter = nil; fileConverter = nil; recordedFrames = 0
    recordingLock.unlock()
    if discard, let path { try? FileManager.default.removeItem(atPath: path) }
    if let turnPath { try? FileManager.default.removeItem(atPath: turnPath) }
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
