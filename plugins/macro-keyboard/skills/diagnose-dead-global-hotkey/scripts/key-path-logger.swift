// key-path-logger.swift: watch a REAL key press travel through the four event-tap positions.
//
// Usage:  swift key-path-logger.swift [seconds=300] [watch-app-name]
//   e.g.  swift key-path-logger.swift 600 "MyScreenshotApp"
//
// Installs four LISTEN-ONLY taps (it can never block or change input): head and tail of the HID tap point,
// head and tail of the Session tap point. For every key-down with Command, Control or Option held it prints
//   <t>s [<position>] keyDown <modifiers>keycode=<n> front=<frontmost app> srcPid=<event source pid>
// and, if a watch app is given, how many of that app's overlay windows (layer > 0) are on screen 1 s later.
// Plain typing (no Cmd/Ctrl/Opt) is never logged.
//
// Reading the result:
//   - The modifiers are not the ones you pressed (e.g. Ctrl+Shift+X when you pressed Cmd+Shift+X)
//       -> something below the tap layer rewrote the key: a DriverKit remapper such as Karabiner-Elements.
//   - Seen at HID-head but missing at a later position -> an ACTIVE tap in between swallowed it
//       (run tap-census.swift to see whose taps sit there).
//   - Seen at every position, watch app shows no new window -> the hotkey owner did not match it
//       (wrong combination registered, or its registration failed).
//   - Not seen only while the problem app is frontmost -> Secure Event Input, which hides keys from every
//       other process's taps as well as from hotkeys (check kCGSSessionSecureInputPID with ioreg).
//   - Not seen anywhere, even from a neutral app -> the key never reached the window server
//       (hardware, KVM or sharing software, a remapper rule that drops it).
//
// Needs Input Monitoring for the app that runs it (the terminal); without it the taps cannot be created.
import AppKit
import CoreGraphics

let args = CommandLine.arguments.dropFirst()
let seconds = Double(args.first ?? "300") ?? 300
let watchApp = args.dropFirst().first
let start = Date()

func log(_ s: String) {
  print(String(format: "%7.2fs ", Date().timeIntervalSince(start)) + s)
  fflush(stdout)
}

func overlayWindows(_ owner: String) -> Int {
  let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
  return list.filter {
    ($0[kCGWindowOwnerName as String] as? String) == owner && (($0[kCGWindowLayer as String] as? Int) ?? 0) > 0
  }.count
}

func modifiers(_ f: CGEventFlags) -> String {
  var s = ""
  if f.contains(.maskControl) { s += "Ctrl+" }
  if f.contains(.maskAlternate) { s += "Opt+" }
  if f.contains(.maskShift) { s += "Shift+" }
  if f.contains(.maskCommand) { s += "Cmd+" }
  return s
}

let positions = ["", "HID-head", "HID-tail", "Session-head", "Session-tail"]

let callback: CGEventTapCallBack = { _, type, event, refcon in
  if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
    log("a logger tap was disabled by the system (\(type.rawValue))")
    return Unmanaged.passUnretained(event)
  }
  let flags = event.flags
  guard !flags.intersection([.maskCommand, .maskControl, .maskAlternate]).isEmpty else {
    return Unmanaged.passUnretained(event)
  }
  let tag = refcon.map { Int(bitPattern: $0) } ?? 0
  let keycode = event.getIntegerValueField(.keyboardEventKeycode)
  let source = event.getIntegerValueField(.eventSourceUnixProcessID)
  let front = NSWorkspace.shared.frontmostApplication?.localizedName ?? "?"
  var line = "[\(positions[tag])] keyDown \(modifiers(flags))keycode=\(keycode) front=\(front) srcPid=\(source)"
  if let app = watchApp { line += " \(app)Overlays=\(overlayWindows(app))" }
  log(line)
  if tag == 4, let app = watchApp {
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { log("   +1s \(app)Overlays=\(overlayWindows(app))") }
  }
  return Unmanaged.passUnretained(event)
}

let layout: [(CGEventTapLocation, CGEventTapPlacement, Int)] = [
  (.cghidEventTap, .headInsertEventTap, 1), (.cghidEventTap, .tailAppendEventTap, 2),
  (.cgSessionEventTap, .headInsertEventTap, 3), (.cgSessionEventTap, .tailAppendEventTap, 4),
]
for (location, placement, tag) in layout {
  guard let tap = CGEvent.tapCreate(
    tap: location, place: placement, options: .listenOnly,
    eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue),
    callback: callback, userInfo: UnsafeMutableRawPointer(bitPattern: tag))
  else {
    log("cannot create the \(positions[tag]) tap: grant Input Monitoring to the app running this script")
    exit(1)
  }
  CFRunLoopAddSource(CFRunLoopGetCurrent(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
  CGEvent.tapEnable(tap: tap, enable: true)
}
log("logging Cmd/Ctrl/Opt key-downs for \(Int(seconds))s at HID-head, HID-tail, Session-head, Session-tail")
DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { log("done"); exit(0) }
CFRunLoopRun()
