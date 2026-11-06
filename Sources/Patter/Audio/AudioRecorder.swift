import Accelerate
import AudioToolbox
import AVFoundation
import CoreAudio
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

    func append(_ samples: UnsafeBufferPointer<Float>) {
        storage.withLockUnchecked { $0.append(contentsOf: samples) }
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
    /// A Core Audio call failed. The text names the step, for the log.
    case coreAudio(String, OSStatus)

    var errorDescription: String? {
        switch self {
        case .noInputDevice: "No microphone found"
        case .unsupportedFormat: "The microphone format is not supported"
        case .noAudio, .coreAudio: "The microphone did not start"
        }
    }
}

private func check(_ status: OSStatus, _ step: @autoclosure () -> String) throws {
    if status != noErr { throw RecorderError.coreAudio(step(), status) }
}

/// Records from one microphone and converts the audio to the 16 kHz mono format that the models use.
///
/// The recorder uses a Core Audio input unit (AUHAL) that opens only the chosen device.
/// AVAudioEngine did not work for this: it always opened the system default input first, and it
/// went back to that input on its own. With Bluetooth headphones as the default, that switched the
/// headphones to headset mode even when Patter recorded from the built-in microphone.
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

    private let log = Logger(subsystem: "com.unculture.Patter", category: "audio")
    private let queue = DispatchQueue(label: "com.unculture.Patter.audio", qos: .userInteractive)
    private let buffer = SampleBuffer()
    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)!

    // Only used on `queue`.
    private var unit: AudioUnit?
    private var device: AudioInputDevice?
    /// The sample rate that `unit` delivers. It is the rate of the device when the unit started.
    private var unitSampleRate: Double = 0
    /// Kept alive while `unit` can call it.
    private var processor: CaptureProcessor?
    private var session = 0
    private var ready = ReadySignal()
    private var startTime = Date()

    deinit {
        tearDownCapture()
    }

    /// Starts a recording. `device` nil means the system default input.
    /// If `canFallBack` is true and the device sends no audio within 1.2 s, the recorder
    /// switches to the system default input.
    func start(device: AudioInputDevice?, canFallBack: Bool) {
        meter.update(0)
        _ = buffer.drain()
        queue.async { [self] in
            tearDownCapture()
            session += 1
            let current = session
            startTime = Date()
            ready = ReadySignal()
            begin(on: device)

            if canFallBack, device != nil {
                queue.asyncAfter(deadline: .now() + 1.2) { [self] in
                    guard session == current, !ready.hasFired, unit != nil else { return }
                    log.notice("No audio from \(self.device?.name ?? "?", privacy: .public) after 1.2 s, switching to the system default")
                    tearDownCapture()
                    begin(on: nil)
                }
            }
            queue.asyncAfter(deadline: .now() + 4) { [self] in
                guard session == current, !ready.hasFired, unit != nil else { return }
                tearDownCapture()
                report(RecorderError.noAudio)
            }
        }
    }

    /// Stops the recording and returns all of its samples.
    func stop() -> [Float] {
        queue.sync {
            session += 1
            tearDownCapture()
        }
        meter.update(0)
        return buffer.drain()
    }

    // MARK: - Input unit, on `queue`

    private func begin(on requested: AudioInputDevice?) {
        guard let device = requested ?? AudioDevices.defaultInputDevice() else {
            report(RecorderError.noInputDevice)
            return
        }
        do {
            try startCapture(on: device)
        } catch {
            tearDownCapture()
            if let fallback = AudioDevices.defaultInputDevice(), fallback.id != device.id {
                log.error("Could not start \(device.name, privacy: .public): \(String(describing: error), privacy: .public). Using the system default.")
                do {
                    try startCapture(on: fallback)
                    return
                } catch {
                    tearDownCapture()
                }
            }
            report(error)
        }
    }

    /// Opens `device` and starts to record from it. If this throws, call `tearDownCapture`.
    private func startCapture(on device: AudioInputDevice) throws {
        var description = AudioComponentDescription(
            componentType: kAudioUnitType_Output, componentSubType: kAudioUnitSubType_HALOutput,
            componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0, componentFlagsMask: 0)
        guard let component = AudioComponentFindNext(nil, &description) else { throw RecorderError.noInputDevice }
        var instance: AudioUnit?
        try check(AudioComponentInstanceNew(component, &instance), "create the input unit")
        guard let unit = instance else { throw RecorderError.noInputDevice }
        self.unit = unit
        self.device = device
        let recorder = Unmanaged.passUnretained(self).toOpaque()

        // Listen before the device is selected, so that no format change is lost. A Bluetooth
        // headset changes its sample rate when it switches to headset mode, just after it opens.
        try check(
            AudioUnitAddPropertyListener(unit, kAudioUnitProperty_StreamFormat, formatListener, recorder),
            "listen for format changes")

        // Input only. Element 1 is the input side of the unit, and element 0 is the output side.
        var on: UInt32 = 1
        var off: UInt32 = 0
        let flagSize = UInt32(MemoryLayout<UInt32>.size)
        try check(
            AudioUnitSetProperty(unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1, &on, flagSize),
            "enable input")
        try check(
            AudioUnitSetProperty(unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0, &off, flagSize),
            "disable output")
        var id = device.id
        try check(
            AudioUnitSetProperty(
                unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                &id, UInt32(MemoryLayout<AudioDeviceID>.size)),
            "select \(device.name)")

        // The unit converts the sample format and the channels, but not the sample rate. So it
        // delivers mono audio at the rate of the device, and the processor converts it to 16 kHz.
        let rate = try Self.deviceSampleRate(of: unit)
        guard rate > 0 else { throw RecorderError.noInputDevice }
        guard let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1) else {
            throw RecorderError.unsupportedFormat
        }
        try check(
            AudioUnitSetProperty(
                unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1,
                format.streamDescription, UInt32(MemoryLayout<AudioStreamBasicDescription>.size)),
            "set the sample format")

        var maximumFrames: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        try check(
            AudioUnitGetProperty(
                unit, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0, &maximumFrames, &size),
            "read the buffer size")

        let deviceName = device.name
        let startTime = startTime
        guard let processor = CaptureProcessor(
            unit: unit, format: format, targetFormat: targetFormat, maximumFrames: max(maximumFrames, 4096),
            samples: buffer, meter: meter, ready: ready,
            onFirstAudio: { [weak self] in self?.announceReady(deviceName: deviceName, startTime: startTime) })
        else { throw RecorderError.unsupportedFormat }
        self.processor = processor
        unitSampleRate = rate

        var callback = AURenderCallbackStruct(
            inputProc: inputCallback, inputProcRefCon: Unmanaged.passUnretained(processor).toOpaque())
        try check(
            AudioUnitSetProperty(
                unit, kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Global, 0,
                &callback, UInt32(MemoryLayout<AURenderCallbackStruct>.size)),
            "set the input callback")
        try check(AudioUnitInitialize(unit), "initialize the input unit")
        try check(AudioOutputUnitStart(unit), "start \(device.name)")

        var alive = Self.isAliveAddress
        AudioObjectAddPropertyListener(device.id, &alive, deviceListener, recorder)
        log.notice("Opened \(device.name, privacy: .public) at \(Int(rate)) Hz")
    }

    private func tearDownCapture() {
        guard let unit else { return }
        let recorder = Unmanaged.passUnretained(self).toOpaque()
        if let device {
            var alive = Self.isAliveAddress
            AudioObjectRemovePropertyListener(device.id, &alive, deviceListener, recorder)
        }
        // Stop waits for the last input callback to finish, so `processor` can go after it.
        AudioOutputUnitStop(unit)
        AudioUnitRemovePropertyListenerWithUserData(unit, kAudioUnitProperty_StreamFormat, formatListener, recorder)
        AudioUnitUninitialize(unit)
        AudioComponentInstanceDispose(unit)
        self.unit = nil
        processor = nil
    }

    /// The format of the device changed, for example because a Bluetooth headset switched to
    /// headset mode. Restart on the same device with the new sample rate. Called on any thread.
    fileprivate func formatChanged(_ changed: AudioUnit) {
        queue.async { [self] in
            guard let unit, unit == changed, let device,
                  let rate = try? Self.deviceSampleRate(of: unit), rate > 0, rate != unitSampleRate
            else { return }
            log.notice("\(device.name, privacy: .public) changed to \(Int(rate)) Hz, restarting it")
            tearDownCapture()
            begin(on: device)
        }
    }

    /// The device was disconnected, or came back. If it is gone, continue on the system default.
    /// The samples so far stay in the buffer. Called on any thread.
    fileprivate func deviceChanged(_ id: AudioObjectID) {
        queue.async { [self] in
            guard unit != nil, let device, device.id == id, !Self.isAlive(id) else { return }
            tearDownCapture()
            guard let replacement = AudioDevices.defaultInputDevice(), replacement.id != id else {
                report(RecorderError.noInputDevice)
                return
            }
            log.notice("\(device.name, privacy: .public) disconnected, continuing with \(replacement.name, privacy: .public)")
            begin(on: replacement)
        }
    }

    private func announceReady(deviceName: String, startTime: Date) {
        let milliseconds = Int(Date().timeIntervalSince(startTime) * 1000)
        log.notice("Microphone ready after \(milliseconds) ms: \(deviceName, privacy: .public)")
        DispatchQueue.main.async { [weak self] in self?.onReady?(deviceName) }
    }

    private func report(_ error: Error) {
        log.error("Recording failed: \(String(describing: error), privacy: .public)")
        DispatchQueue.main.async { [weak self] in self?.onFailure?(error) }
    }

    /// The sample rate on the device side of the input element.
    private static func deviceSampleRate(of unit: AudioUnit) throws -> Double {
        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        try check(
            AudioUnitGetProperty(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 1, &format, &size),
            "read the device format")
        return format.mSampleRate
    }

    private static let isAliveAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyDeviceIsAlive,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)

    private static func isAlive(_ id: AudioObjectID) -> Bool {
        var address = isAliveAddress
        var alive: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(id, &address, 0, nil, &size, &alive) == noErr && alive != 0
    }
}

// MARK: - Callbacks

// The recorder lives as long as the app, so the listeners can point to it without a reference count.

private let inputCallback: AURenderCallback = { refCon, flags, timeStamp, bus, frameCount, _ in
    Unmanaged<CaptureProcessor>.fromOpaque(refCon).takeUnretainedValue()
        .render(flags: flags, timeStamp: timeStamp, bus: bus, frameCount: frameCount)
}

private let formatListener: AudioUnitPropertyListenerProc = { refCon, unit, _, scope, element in
    guard scope == kAudioUnitScope_Input, element == 1 else { return }
    Unmanaged<AudioRecorder>.fromOpaque(refCon).takeUnretainedValue().formatChanged(unit)
}

private let deviceListener: AudioObjectPropertyListenerProc = { id, _, _, refCon in
    if let refCon {
        Unmanaged<AudioRecorder>.fromOpaque(refCon).takeUnretainedValue().deviceChanged(id)
    }
    return noErr
}

// MARK: - Processing

/// Turns the buffers of one input unit into 16 kHz samples. It runs on the audio thread, so it
/// allocates its buffers up front, and it never waits for the recorder's queue: `stop` holds the
/// queue while the unit waits for the last callback to finish.
private final class CaptureProcessor {
    private let unit: AudioUnit
    private let input: AVAudioPCMBuffer
    private let output: AVAudioPCMBuffer
    private let converter: AVAudioConverter
    private let samples: SampleBuffer
    private let meter: AudioLevelMeter
    private let ready: ReadySignal
    private let onFirstAudio: () -> Void

    init?(
        unit: AudioUnit, format: AVAudioFormat, targetFormat: AVAudioFormat, maximumFrames: AVAudioFrameCount,
        samples: SampleBuffer, meter: AudioLevelMeter, ready: ReadySignal, onFirstAudio: @escaping () -> Void
    ) {
        let ratio = targetFormat.sampleRate / format.sampleRate
        guard let input = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: maximumFrames),
              let output = AVAudioPCMBuffer(
                pcmFormat: targetFormat,
                frameCapacity: AVAudioFrameCount((Double(maximumFrames) * ratio).rounded(.up)) + 32),
              let converter = AVAudioConverter(from: format, to: targetFormat)
        else { return nil }
        self.unit = unit
        self.input = input
        self.output = output
        self.converter = converter
        self.samples = samples
        self.meter = meter
        self.ready = ready
        self.onFirstAudio = onFirstAudio
    }

    func render(
        flags: UnsafeMutablePointer<AudioUnitRenderActionFlags>, timeStamp: UnsafePointer<AudioTimeStamp>,
        bus: UInt32, frameCount: UInt32
    ) -> OSStatus {
        guard frameCount <= input.frameCapacity else { return kAudioUnitErr_TooManyFramesToProcess }
        input.frameLength = frameCount
        let status = AudioUnitRender(unit, flags, timeStamp, bus, frameCount, input.mutableAudioBufferList)
        guard status == noErr else { return status }

        meter.update(level())
        if let converted = convert() {
            samples.append(converted)
        }
        // Bluetooth headsets send exact zeros while they switch modes. Any real
        // microphone has some noise, so the first non-zero buffer means that audio flows.
        if !ready.hasFired, peak() > 1e-6, ready.fire() {
            onFirstAudio()
        }
        return noErr
    }

    /// Maps the RMS level of the input to 0...1. About -55 dBFS (a quiet room) gives 0,
    /// and about -12 dBFS (loud speech close to the microphone) gives 1.
    private func level() -> Float {
        guard let channel = input.floatChannelData?[0], input.frameLength > 0 else { return 0 }
        var meanSquare: Float = 0
        vDSP_measqv(channel, 1, &meanSquare, vDSP_Length(input.frameLength))
        let decibels = 10 * log10(max(meanSquare, 1e-12))
        return min(max((decibels + 55) / 43, 0), 1)
    }

    private func peak() -> Float {
        guard let channel = input.floatChannelData?[0], input.frameLength > 0 else { return 0 }
        var peak: Float = 0
        vDSP_maxmgv(channel, 1, &peak, vDSP_Length(input.frameLength))
        return peak
    }

    /// Converts the input to 16 kHz. The result points into `output`, so use it before the next call.
    private func convert() -> UnsafeBufferPointer<Float>? {
        let input = input
        var supplied = false
        var error: NSError?
        output.frameLength = 0
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            if supplied {
                // .noDataNow keeps the resampler state, so that consecutive buffers join without clicks.
                inputStatus.pointee = .noDataNow
                return nil
            }
            supplied = true
            inputStatus.pointee = .haveData
            return input
        }
        guard status != .error, let data = output.floatChannelData?[0] else { return nil }
        return UnsafeBufferPointer(start: data, count: Int(output.frameLength))
    }
}
