import AppKit
import CompanionCore
import Foundation
import Logging

// Unbuffer stdout/stderr for launchd (Pitfall 5)
setbuf(stdout, nil)
setbuf(stderr, nil)

// Configure logging first
LoggingSystem.bootstrap(StreamLogHandler.standardError)

// Set up NSApplication as accessory (no dock icon, no app switcher)
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

// Create and start the companion app
let companion = CompanionApp()
companion.start()

// Set up SIGTERM handler using DispatchSource (not signal(), per research)
let sigSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
signal(SIGTERM, SIG_IGN)  // Let DispatchSource handle it
sigSource.setEventHandler {
    companion.shutdown()
    // Post dummy event to unblock RunLoop (Pitfall 4: NSApplication.stop requires event)
    let event = NSEvent.otherEvent(
        with: .applicationDefined, location: .zero,
        modifierFlags: [], timestamp: 0, windowNumber: 0,
        context: nil, subtype: 0, data1: 0, data2: 0
    )!
    app.postEvent(event, atStart: true)
    app.stop(nil)
}
sigSource.resume()

// Store references globally to prevent ARC deallocation (Pitfall 3)
nonisolated(unsafe) var keepAlive: (any DispatchSourceSignal)? = sigSource
nonisolated(unsafe) var keepCompanion: CompanionApp? = companion

// Enter run loop (blocks forever until SIGTERM)
app.run()
