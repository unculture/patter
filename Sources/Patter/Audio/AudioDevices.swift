import CoreAudio
import Foundation

struct AudioInputDevice: Identifiable, Hashable {
    let id: AudioDeviceID
    let uid: String
    let name: String
    let transportType: UInt32

    var isBluetooth: Bool {
        transportType == kAudioDeviceTransportTypeBluetooth || transportType == kAudioDeviceTransportTypeBluetoothLE
    }

    var isBuiltIn: Bool { transportType == kAudioDeviceTransportTypeBuiltIn }
}

/// Reads the audio input devices from Core Audio. Reading device properties needs no permission.
enum AudioDevices {
    static func inputDevices() -> [AudioInputDevice] {
        var address = globalAddress(kAudioHardwarePropertyDevices)
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.filter(hasInput).compactMap(device(for:))
    }

    static func defaultInputDevice() -> AudioInputDevice? {
        var address = globalAddress(kAudioHardwarePropertyDefaultInputDevice)
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id) == noErr,
              id != 0
        else { return nil }
        return device(for: id)
    }

    private static func device(for id: AudioDeviceID) -> AudioInputDevice? {
        guard let uid = string(kAudioDevicePropertyDeviceUID, of: id),
              let name = string(kAudioObjectPropertyName, of: id)
        else { return nil }
        var address = globalAddress(kAudioDevicePropertyTransportType)
        var transport: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(id, &address, 0, nil, &size, &transport)
        return AudioInputDevice(id: id, uid: uid, name: name, transportType: transport)
    }

    private static func hasInput(_ id: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr && size > 0
    }

    private static func string(_ selector: AudioObjectPropertySelector, of id: AudioDeviceID) -> String? {
        var address = globalAddress(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(id, &address, 0, nil, &size, pointer)
        }
        guard status == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }

    private static func globalAddress(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
    }
}

/// Which microphone Patter records from. Stored as a string in the preferences.
enum MicrophoneChoice: Hashable {
    /// The built-in microphone when the system default is Bluetooth, else the system default.
    case automatic
    case systemDefault
    case device(uid: String)

    init(storedValue: String?) {
        switch storedValue {
        case nil, "auto": self = .automatic
        case "system": self = .systemDefault
        case let uid?: self = .device(uid: uid)
        }
    }

    var storedValue: String {
        switch self {
        case .automatic: "auto"
        case .systemDefault: "system"
        case .device(let uid): uid
        }
    }

    /// The device to record from (nil means the system default), and whether the recorder can
    /// switch to the system default if that device delivers no audio. Only the automatic choice
    /// falls back: a device that the user picked keeps its time to start, for example the second
    /// that AirPods need.
    func resolve() -> (device: AudioInputDevice?, canFallBack: Bool) {
        switch self {
        case .systemDefault:
            return (nil, false)
        case .automatic:
            guard AudioDevices.defaultInputDevice()?.isBluetooth == true,
                  let builtIn = AudioDevices.inputDevices().first(where: \.isBuiltIn)
            else { return (nil, false) }
            return (builtIn, true)
        case .device(let uid):
            // A disconnected device means the system default.
            return (AudioDevices.inputDevices().first(where: { $0.uid == uid }), false)
        }
    }
}
