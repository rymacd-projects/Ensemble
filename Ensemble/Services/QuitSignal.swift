import AppKit

/// Lets the background updater ask Ensemble to close politely (with a standard "please quit" signal).
/// Ensemble saves the library and then quits, exactly as if you chose Quit from the menu.
enum QuitSignal {
    private static var source: DispatchSourceSignal?

    static func install(beforeQuit: @escaping () -> Void) {
        guard source == nil else { return }
        signal(SIGTERM, SIG_IGN)   // hand the signal to us instead of the default "die immediately"
        let handler = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        handler.setEventHandler {
            beforeQuit()
            NSApp.terminate(nil)
        }
        handler.resume()
        source = handler
    }
}
