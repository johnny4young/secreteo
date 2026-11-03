import AppKit
import AppUI

@main
enum SecreteoMain {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        let delegate = SecreteoAppDelegate()
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }
}
