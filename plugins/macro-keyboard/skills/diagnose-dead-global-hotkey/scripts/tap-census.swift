// tap-census.swift: list every keyboard CGEventTap on this Mac, marking each ACTIVE or listen-only.
//
// Usage:  swift tap-census.swift
//
// One line per tap that watches keyDown/keyUp/flagsChanged:
//   <process name>  pid=<pid>  <HID|Session|AnnotatedSession>  <ACTIVE(can swallow)|listen-only>  enabled=<bool>
//
// An ACTIVE tap can delete or rewrite key events before global hotkeys (Carbon RegisterEventHotKey) are
// dispatched, so it is the first suspect when a hotkey dies only while some app is running or frontmost.
// Run it once as a baseline, then again in the failing state, and diff the two.
// Read-only: it lists taps, it never creates one.
import AppKit
import CoreGraphics

var count: UInt32 = 0
CGGetEventTapList(0, nil, &count)
var taps = [CGEventTapInformation](repeating: CGEventTapInformation(), count: Int(count))
CGGetEventTapList(count, &taps, &count)

let keyboardMask: UInt64 = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
  | (1 << CGEventType.flagsChanged.rawValue)
let points = ["HID", "Session", "AnnotatedSession"]

for tap in taps where tap.eventsOfInterest & keyboardMask != 0 {
  let pid = pid_t(tap.tappingProcess)
  let name = NSRunningApplication(processIdentifier: pid)?.localizedName ?? "pid \(pid)"
  let point = Int(tap.tapPoint.rawValue) < points.count ? points[Int(tap.tapPoint.rawValue)] : "?"
  let mode = tap.options == .listenOnly ? "listen-only" : "ACTIVE(can swallow)"
  print("\(name)\tpid=\(pid)\t\(point)\t\(mode)\tenabled=\(tap.enabled)")
}
