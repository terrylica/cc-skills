import AppKit
import Foundation
import Logging
import CSherpaOnnx

// Unbuffer stdout/stderr for launchd (Pitfall 5)
setbuf(stdout, nil)
setbuf(stderr, nil)

// Configure logging first
LoggingSystem.bootstrap(StreamLogHandler.standardError)
let logger = Logger(label: Config.appName)

// Verify C interop works -- call a trivial sherpa-onnx function
let version = String(cString: SherpaOnnxGetVersionStr())
logger.info("sherpa-onnx C API version: \(version)")

// Set up NSApplication as accessory (no dock icon, no app switcher)
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

// Set up SIGTERM handler using DispatchSource (not signal(), per research)
let sigSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
signal(SIGTERM, SIG_IGN)  // Let DispatchSource handle it
sigSource.setEventHandler {
    logger.info("SIGTERM received, shutting down")
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

// Store sigSource globally to prevent ARC deallocation (Pitfall 3)
nonisolated(unsafe) var keepAlive: (any DispatchSourceSignal)? = sigSource

logger.info("Starting \(Config.appName)")

// Enter run loop (blocks forever until SIGTERM)
app.run()

logger.info("\(Config.appName) exited cleanly")
