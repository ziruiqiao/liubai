import AppKit
import SwiftUI

@MainActor
enum MainWindowPresenter {
    static let identifier = NSUserInterfaceItemIdentifier("liubai.main")
    private static weak var mainWindow: NSWindow?
    private static var closeObserver: NSObjectProtocol?

    static func register(_ window: NSWindow) {
        window.identifier = identifier
        guard mainWindow !== window else { return }
        if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
        mainWindow = window
        closeObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak window] _ in
            MainActor.assumeIsolated {
                window?.identifier = nil
                mainWindow = nil
                if let token = closeObserver { NotificationCenter.default.removeObserver(token) }
                closeObserver = nil
            }
        }
    }

    @discardableResult
    static func revealExisting() -> Bool {
        guard let window = mainWindow else { return false }
        if window.isMiniaturized { window.deminiaturize(nil) }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        return true
    }

    static func open(using action: OpenWindowAction) {
        open { action(id: "main") }
    }

    static func open(create: () -> Void) {
        if !revealExisting() {
            create()
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
