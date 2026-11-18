import AppKit
import SwiftUI

/// Opens Privacy › Accessibility and floats the app's icon beside it, to drag into the list.
/// It closes itself once the grant arrives.
@MainActor
final class AccessibilityGrantGuide {
    static let shared = AccessibilityGrantGuide()

    private var panel: NSPanel?
    private var watch: Task<Void, Never>?

    func show(
        opensSystemSettings: Bool, isGranted: @escaping @Sendable () -> Bool,
        onGranted: @escaping @MainActor () -> Void = {}
    ) {
        if opensSystemSettings,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        let panel = panel ?? makePanel()
        self.panel = panel
        place(panel, beside: Self.systemSettingsFrame())
        panel.orderFrontRegardless()
        watch?.cancel()
        watch = Task { @MainActor [weak self] in
            let start = ContinuousClock.now
            var sawSettings = false
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled, let self else { return }
                if isGranted() {
                    self.close()
                    return onGranted()
                }
                let settings = Self.systemSettingsFrame()
                if Self.shouldClose(
                    settingsOnScreen: settings != nil, sawSettings: sawSettings, elapsed: ContinuousClock.now - start) {
                    return self.close()
                }
                sawSettings = sawSettings || settings != nil
                if let panel = self.panel { self.place(panel, beside: settings) }
            }
        }
    }

    nonisolated static let timeLimit: Duration = .seconds(300)
    nonisolated static let unseenLimit: Duration = .seconds(15)

    /// Leaving System Settings, never seeing it, or never finishing ends the guide.
    nonisolated static func shouldClose(settingsOnScreen: Bool, sawSettings: Bool, elapsed: Duration) -> Bool {
        (sawSettings && !settingsOnScreen) || (!sawSettings && !settingsOnScreen && elapsed >= unseenLimit)
            || elapsed >= timeLimit
    }

    func close() {
        watch?.cancel()
        watch = nil
        panel?.orderOut(nil)
        panel = nil
    }

    private func makePanel() -> NSPanel {
        let hosting = NSHostingView(rootView: AccessibilityGrantGuideView { [weak self] in self?.close() })
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: hosting.fittingSize),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.contentView = hosting
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        // System Settings is in front while the person drags, so the panel must float over it.
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.title = L10n.text("Allow Accessibility…")
        return panel
    }

    /// Beside System Settings, on its screen, while it is on screen, else low on the main screen.
    private func place(_ panel: NSPanel, beside settings: CGRect?) {
        let size = panel.frame.size
        let settingsScreen = settings.flatMap { frame in
            NSScreen.screens.first { $0.frame.contains(CGPoint(x: frame.midX, y: frame.midY)) }
        }
        guard let screen = settingsScreen ?? NSScreen.main else { return }
        let origin = Self.origin(for: size, beside: settings, in: screen.visibleFrame)
        if panel.frame.origin != origin { panel.setFrameOrigin(origin) }
    }

    nonisolated static func origin(for size: CGSize, beside target: CGRect?, in screen: CGRect) -> CGPoint {
        let gap: CGFloat = 12
        guard let target else {
            return CGPoint(x: screen.midX - size.width / 2, y: screen.minY + screen.height * 0.2)
        }
        let y = min(max(target.midY - size.height / 2, screen.minY), screen.maxY - size.height)
        if target.maxX + gap + size.width <= screen.maxX { return CGPoint(x: target.maxX + gap, y: y) }
        if target.minX - gap - size.width >= screen.minX { return CGPoint(x: target.minX - gap - size.width, y: y) }
        return CGPoint(x: target.midX - size.width / 2, y: max(target.minY - gap - size.height, screen.minY))
    }

    /// Window bounds need no Screen Recording permission; only titles do, and none is read.
    private static func systemSettingsFrame() -> CGRect? {
        let ids = Set(NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.systempreferences")
            .map(\.processIdentifier))
        guard !ids.isEmpty,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]],
              let primaryHeight = NSScreen.screens.first?.frame.height
        else { return nil }
        for window in windows {
            guard let pid = window[kCGWindowOwnerPID as String] as? pid_t, ids.contains(pid),
                  window[kCGWindowLayer as String] as? Int == 0,
                  let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds)
            else { continue }
            // Core Graphics counts from the top of the primary screen, AppKit from its bottom.
            return CGRect(x: frame.minX, y: primaryHeight - frame.maxY, width: frame.width, height: frame.height)
        }
        return nil
    }
}

struct AccessibilityGrantGuideView: View {
    let close: () -> Void

    private var appName: String {
        FileManager.default.displayName(atPath: Bundle.main.bundlePath)
            .replacingOccurrences(of: ".app", with: "")
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath))
                .resizable()
                .frame(width: 52, height: 52)
                // A file URL, as Finder drags it, is what the Accessibility list accepts.
                .onDrag { NSItemProvider(contentsOf: Bundle.main.bundleURL) ?? NSItemProvider() }
                .accessibilityLabel(appName)
                .accessibilityIdentifier("accessibility-guide-icon")
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: appName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SecreteoDesign.text)
                Text("Drag into the list, then turn it on.")
                    .font(.system(size: 12))
                    .foregroundStyle(SecreteoDesign.secondaryText)
                    .fixedSize()
            }
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(SecreteoDesign.tertiaryText)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.text("Close"))
            .accessibilityIdentifier("accessibility-guide-close")
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(SecreteoDesign.card, in: RoundedRectangle(cornerRadius: 16))
        .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(SecreteoDesign.hairline) }
        .padding(1)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("accessibility-guide")
    }
}
