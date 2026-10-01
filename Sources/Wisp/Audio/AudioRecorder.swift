import Accelerate
import AudioToolbox
import AVFoundation
import os

/// The latest microphone level, from 0 (silence) to 1 (loud speech).
/// The audio thread writes it and the waveform reads it at display rate.
final class AudioLevelMeter: Sendable {
    private let value = OSAllocatedUnfairLock(initialState: Float(0))

    var level: Float { value.withLock { $0 } }

    func update(_ level: Float) {
        value.withLock { $0 = level }
    }
}

/// Collects 16 kHz mono samples across audio callbacks.
private final class SampleBuffer: Sendable {
    private let storage = OSAllocatedUnfairLock(initialState: [Float]())

    func append(_ samples: [Float]) {
        storage.withLock { $0.append(contentsOf: samples) }
    }

    func drain() -> [Float] {
        storage.withLock { samples in
            defer { samples = [] }
            return samples
        }
    }
}

/// Fires one time per recording, when the first real audio arrives.
private final class ReadySignal: Sendable {
    private let fired = OSAllocatedUnfairLock(initialState: false)

    var hasFired: Bool { fired.withLock { $0 } }

    /// Returns true only for the first call.
    func fire() -> Bool {
        fired.withLock { fired in
            defer { fired = true }
            return !fired
        }
    }
}

enum RecorderError: LocalizedError {
    case noInputDevice
    case unsupportedFormat
    case noAudio

    var errorDescription: String? {
        switch self {
        case .noInputDevice: "No microphone found"
        case .unsupportedFormat: "The microphone format is not supported"
        case .noAudio: "The microphone did not start"
        }
    }
}

/// Records from a microphone and converts the audio to the 16 kHz mono format that the models use.
///
/// Starting a microphone takes time: about 0.1 s for the built-in microphone, and a second or more
/// for Bluetooth headphones, which must first switch to headset mode. So `start` returns at once,
/// sets up the device on a background queue, and calls `onReady` when the first real audio arrives.
final class AudioRecorder {
    static let sampleRate: Double = 16_000

    let meter = AudioLevelMeter()
    /// Called on the main queue when audio starts to arrive, with the name of the device.
    var onReady: ((String) -> Void)?
    /// Called on the main queue if the microphone does not start, or stops because of a device problem.
    var onFailure: ((Error) -> Void)?

    private let log = Logger(subsystem: "com.unculture.Wisp", category: "audio")
    private let queue = DispatchQueue(label: "com.unculture.Wisp.audio", qos: .userInteractive)
    private let buffer = SampleBuffer()
    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)!

    // Only used on `queue`.
    private var engine: AVAudioEngine?
    private var device: AudioInputDevice?
    private var configurationObserver: NSObjectProtocol?
    private var session = 0
    private var ready = ReadySignal()
    private var startTime = Date()

    /// Starts a recording. `device` nil means the system default input.
    /// If `canFallBack` is true and the device sends no audio within 1.2 s, the recorder
    /// switches to the system default input.
    func start(device: AudioInputDevice?, canFallBack: Bool) {
        meter.update(0)
        _ = buffer.drain()
        queue.async { [self] in
            session += 1
            let current = session
            startTime = Date()
            begin(on: device)

            if canFallBack, device != nil {
                queue.asyncAfter(deadline: .now() + 1.2) { [self] in
                    guard session == current, !ready.hasFired, engine != nil else { return }
                    log.notice("No audio from \(self.device?.name ?? "?", privacy: .public) after 1.2 s, switching to the system default")
                    tearDownEngine()
                    begin(on: nil)
                }
            }
            queue.asyncAfter(deadline: .now() + 4) { [self] in
                guard session == current, !ready.hasFired, engine != nil else { return }
                tearDownEngine()
                report(RecorderError.noAudio)
            }
        }
    }

    /// Stops the recording and returns all of its samples.
    func stop() -> [Float] {
        queue.sync {
            session += 1
            tearDownEngine()
        }
        meter.update(0)
        return buffer.drain()
    }

    // MARK: - Engine, on `queue`

    private func begin(on device: AudioInputDevice?) {
        do {
            try startEngine(on: device)
        } catch {
            tearDownEngine()
            if device != nil {
                log.error("Could not start \(device?.name ?? "?", privacy: .public): \(error.localizedDescription, privacy: .public). Using the system default.")
                do {
                    try startEngine(on: nil)
                    return
                } catch {
                    tearDownEngine()
                }
            }
            report(error)
        }
    }

    private func startEngine(on device: AudioInputDevice?) throws {
        // A new engine for each recording always picks up the current devices.
        let engine = AVAudioEngine()
        self.engine = engine
        self.device = device
        ready = ReadySignal()

        let input = engine.inputNode
        if let device, let unit = input.audioUnit {
            var id = device.id
            let status = AudioUnitSetProperty(
                unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                &id, UInt32(MemoryLayout<AudioDeviceID>.size))
            if status != noErr { throw RecorderError.noInputDevice }
        }

        try installTap(on: engine)
        engine.prepare()
        try engine.start()

        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
        ) { [weak self] _ in
            self?.queue.async { self?.handleConfigurationChange(of: engine) }
        }
    }

    private func installTap(on engine: AVAudioEngine) throws {
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw RecorderError.noInputDevice
        }
        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw RecorderError.unsupportedFormat
        }

        let buffer = buffer
        let meter = meter
        let targetFormat = targetFormat
        let ready = ready
        // Captured here, because the tap must never wait for `queue`: `stop` holds `queue`
        // while the engine waits for the last tap callback to finish.
        let deviceName = device?.name ?? AudioDevices.defaultInputDevice()?.name ?? "Microphone"
        let startTime = startTime
        input.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] pcm, _ in
            meter.update(Self.level(of: pcm))
            if let samples = Self.convert(pcm, with: converter, to: targetFormat) {
                buffer.append(samples)
            }
            // Bluetooth headsets send exact zeros while they switch modes. Any real
            // microphone has some noise, so the first non-zero buffer means that audio flows.
            if !ready.hasFired, Self.peak(of: pcm) > 1e-6, ready.fire() {
                self?.announceReady(deviceName: deviceName, startTime: startTime)
            }
        }
    }

    private func announceReady(deviceName: String, startTime: Date) {
        let milliseconds = Int(Date().timeIntervalSince(startTime) * 1000)
        log.notice("Microphone ready after \(milliseconds) ms: \(deviceName, privacy: .public)")
        DispatchQueue.main.async { [weak self] in self?.onReady?(deviceName) }
    }

    /// The input device changed during a recording (for example, headphones were connected).
    /// The samples so far stay in the buffer, and the recording continues.
    private func handleConfigurationChange(of changed: AVAudioEngine) {
        // Selecting a device also posts this notification, just after the start, while the
        // engine keeps running. A restart then only loses about 0.2 s of audio.
        guard let engine, engine === changed, !engine.isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        do {
            try installTap(on: engine)
            engine.prepare()
            try engine.start()
        } catch {
            tearDownEngine()
            report(error)
        }
    }

    private func tearDownEngine() {
        if let configurationObserver {
            NotificationCenter.default.removeObserver(configurationObserver)
        }
        configurationObserver = nil
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
    }

    private func report(_ error: Error) {
        log.error("Recording failed: \(error.localizedDescription, privacy: .public)")
        DispatchQueue.main.async { [weak self] in self?.onFailure?(error) }
    }

    // MARK: - Signal processing

    /// Maps the RMS level of a buffer to 0...1. About -55 dBFS (a quiet room) gives 0,
    /// and about -12 dBFS (loud speech close to the microphone) gives 1.
    private static func level(of pcm: AVAudioPCMBuffer) -> Float {
        guard let channel = pcm.floatChannelData?[0], pcm.frameLength > 0 else { return 0 }
        var meanSquare: Float = 0
        vDSP_measqv(channel, 1, &meanSquare, vDSP_Length(pcm.frameLength))
        let decibels = 10 * log10(max(meanSquare, 1e-12))
        return min(max((decibels + 55) / 43, 0), 1)
    }

    private static func peak(of pcm: AVAudioPCMBuffer) -> Float {
        guard let channel = pcm.floatChannelData?[0], pcm.frameLength > 0 else { return 0 }
        var peak: Float = 0
        vDSP_maxmgv(channel, 1, &peak, vDSP_Length(pcm.frameLength))
        return peak
    }

    private static func convert(
        _ pcm: AVAudioPCMBuffer, with converter: AVAudioConverter, to format: AVAudioFormat
    ) -> [Float]? {
        let ratio = format.sampleRate / pcm.format.sampleRate
        let capacity = AVAudioFrameCount((Double(pcm.frameLength) * ratio).rounded(.up)) + 32
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }

        var supplied = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            if supplied {
                // .noDataNow keeps the resampler state, so that consecutive buffers join without clicks.
                inputStatus.pointee = .noDataNow
                return nil
            }
            supplied = true
            inputStatus.pointee = .haveData
            return pcm
        }
        guard status != .error, let samples = output.floatChannelData?[0] else { return nil }
        return Array(UnsafeBufferPointer(start: samples, count: Int(output.frameLength)))
    }
}
