import MicCapture
import Foundation
import IOKit

/// Shared interpretation of the existing Audio preference. A temporarily
/// missing device falls back for this capture without erasing the user's UID.
struct MicrophoneInputSelection: Equatable {
    let deviceIdentifier: String?
    let usesSystemFallback: Bool
    var replacesBluetooth = false

    static let preferenceKey = "preferredInputUID"
    static let systemDefault = "default"

    static func preferredIdentifier(defaults: UserDefaults) -> String? {
        guard let value = defaults.object(forKey: preferenceKey) as? String,
              !value.isEmpty, value != systemDefault else { return nil }
        return value
    }

    static func resolve(
        _ preferredIdentifier: String?,
        isAvailable: (String) -> Bool = { (try? AudioDeviceCatalog.inputDevice(matching: $0)) != nil }
    ) -> Self {
        guard let preferredIdentifier else {
            return Self(deviceIdentifier: nil, usesSystemFallback: false)
        }
        return isAvailable(preferredIdentifier)
            ? Self(deviceIdentifier: preferredIdentifier, usesSystemFallback: false)
            : Self(deviceIdentifier: nil, usesSystemFallback: true)
    }

    /// A Bluetooth headset's microphone switches it to its call profile: it opens late, loses
    /// the first words and records narrowband. The Mac's own microphone is used instead,
    /// unless the person chose the headset.
    func avoidingBluetoothDefault(_ system: SystemInput) -> Self {
        guard deviceIdentifier == nil, system.defaultTransport == .bluetooth,
              let builtIn = system.builtInIdentifier else { return self }
        return Self(deviceIdentifier: builtIn, usesSystemFallback: usesSystemFallback, replacesBluetooth: true)
    }
}

/// The system's default input and the Mac's own microphone, read when a dictation starts.
struct SystemInput: Equatable {
    var defaultTransport: AudioInputTransport?
    var builtInIdentifier: String?
    /// How the chosen device connects, for the timing log.
    var transport: (String?) -> AudioInputTransport? = { _ in nil }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.defaultTransport == rhs.defaultTransport && lhs.builtInIdentifier == rhs.builtInIdentifier
    }

    static func live() -> Self {
        let defaultTransport = AudioDeviceCatalog.defaultInputDeviceID().map(AudioDeviceCatalog.inputTransport)
        let replacing = defaultTransport == .bluetooth && laptopLidIsOpen(clamshellState())
        return Self(
            defaultTransport: defaultTransport,
            builtInIdentifier: replacing ? AudioDeviceCatalog.builtInInput()?.uid : nil,
            transport: { identifier in
                guard let identifier else { return defaultTransport }
                let device = try? AudioDeviceCatalog.inputDevice(matching: identifier)
                return device.map { AudioDeviceCatalog.inputTransport($0.id) }
            })
    }

    /// Only a laptop's built-in input is a microphone; a desktop's is its line-in jack.
    /// A closed lid mutes it.
    static func laptopLidIsOpen(_ clamshellState: Bool?) -> Bool {
        clamshellState == false
    }

    /// `AppleClamshellState`, or nil on a Mac without a lid.
    static func clamshellState() -> Bool? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        let state = IORegistryEntryCreateCFProperty(service, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)
        return state?.takeRetainedValue() as? Bool
    }
}
