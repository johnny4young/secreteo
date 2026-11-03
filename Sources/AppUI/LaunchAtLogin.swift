import Foundation
import ServiceManagement

/// Launch at login behind a seam, so tests never register the real app.
@MainActor
public protocol LaunchAtLoginControlling {
    var isEnabled: Bool { get }
    func setEnabled(_ enabled: Bool) throws
}

@MainActor
public struct SystemLaunchAtLogin: LaunchAtLoginControlling {
    public init() {}

    public var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    public func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}

@MainActor
public final class InMemoryLaunchAtLogin: LaunchAtLoginControlling {
    public private(set) var isEnabled = false
    private let failure: (any Error)?

    public init(failure: (any Error)? = nil) {
        self.failure = failure
    }

    public func setEnabled(_ enabled: Bool) throws {
        if let failure { throw failure }
        isEnabled = enabled
    }
}
