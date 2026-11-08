import Darwin
import Foundation
import IOKit.ps

enum ResourceProbeThermalState: String, Codable, Sendable {
    case nominal
    case fair
    case serious
    case critical

    var rank: Int {
        switch self {
        case .nominal: 0
        case .fair: 1
        case .serious: 2
        case .critical: 3
        }
    }
}

enum ResourceProbePowerSource: String, Codable, Sendable {
    case ac
    case battery
    case unknown
}

struct ResourceProbeUsage: Equatable, Sendable {
    let cpuAbsoluteTime: UInt64
    let physicalFootprintBytes: UInt64
    let energyNanojoules: UInt64
    let diskReadBytes: UInt64
    let diskWrittenBytes: UInt64
    let availableDiskBytes: UInt64
    let thermalState: ResourceProbeThermalState
    let powerSource: ResourceProbePowerSource
    let lowPowerModeEnabled: Bool

    static func current() throws -> ResourceProbeUsage {
        guard let usage = try? OwnProcessResourceUsage.current(extendedCounters: true),
              let energy = usage.energyNanojoules,
              let diskRead = usage.diskReadBytes, let diskWritten = usage.diskWrittenBytes
        else { throw ResourceRunProbeError.processUsageUnavailable }
        let availableDisk = try ResourceProbeDiskCapacity.availableBytes()
        return ResourceProbeUsage(
            cpuAbsoluteTime: usage.cpuAbsoluteTime,
            physicalFootprintBytes: usage.physicalFootprintBytes,
            energyNanojoules: energy,
            diskReadBytes: diskRead,
            diskWrittenBytes: diskWritten,
            availableDiskBytes: availableDisk,
            thermalState: ProcessInfo.processInfo.resourceProbeThermalState,
            powerSource: resourceProbePowerSource(),
            lowPowerModeEnabled: ProcessInfo.processInfo.isLowPowerModeEnabled)
    }
}

enum ResourceRunProbeError: Error, Equatable, LocalizedError {
    case diskCapacityUnavailable
    case processUsageUnavailable

    var errorDescription: String? {
        switch self {
        case .diskCapacityUnavailable:
            "available disk capacity could not be measured"
        case .processUsageUnavailable:
            "process resource counters could not be measured"
        }
    }
}

private extension ProcessInfo {
    var resourceProbeThermalState: ResourceProbeThermalState {
        switch thermalState {
        case .nominal: .nominal
        case .fair: .fair
        case .serious: .serious
        case .critical: .critical
        @unknown default: .critical
        }
    }
}

private func resourceProbePowerSource() -> ResourceProbePowerSource {
    let snapshot = IOPSCopyPowerSourcesInfo().takeRetainedValue()
    let value = IOPSGetProvidingPowerSourceType(snapshot).takeUnretainedValue()
        as String
    switch value {
    case kIOPMACPowerKey:
        return .ac
    case kIOPMBatteryPowerKey:
        return .battery
    default:
        return .unknown
    }
}
