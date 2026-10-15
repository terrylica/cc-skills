// hotkey-probe.swift: post a synthetic key chord at the HID tap and report whether an app reacted.
//
// Usage:  swift hotkey-probe.swift <keycode> <modifiers> <watch-app-name> [--escape]
//   e.g.  swift hotkey-probe.swift 7 cmd,shift "MyScreenshotApp" --escape     (7 = X on ANSI layouts)
//   modifiers: comma list of cmd, shift, ctrl, opt
//
// Counts the watch app's overlay windows (layer > 0) before and 1.2 s after the chord and prints FIRED or
// DID NOT FIRE. --escape sends Escape afterwards, only if an overlay appeared, to dismiss it.
//
// LIMIT: a synthetic event enters ABOVE DriverKit remappers (Karabiner-Elements), so this probe can say FIRED
// while the physical key still fails. Use it to test event taps and window-state changes; use
// key-path-logger.swift with a real key press before concluding anything about remapping.
// If the hotkey does not fire, the chord reaches the frontmost app instead (and, in a remote-desktop
// viewer, the remote machine), so pick a frontmost app where that is harmless.
import CoreGraphics
import Foundation

let args = Array(CommandLine.arguments.dropFirst())
guard args.count >= 3, let keycode = CGKeyCode(args[0]) else {
  print("usage: swift hotkey-probe.swift <keycode> <cmd,shift,ctrl,opt> <watch-app-name> [--escape]")
  exit(2)
}
var flags: CGEventFlags = []
for m in args[1].split(separator: ",") {
  switch m {
  case "cmd": flags.insert(.maskCommand)
  case "shift": flags.insert(.maskShift)
  case "ctrl": flags.insert(.maskControl)
  case "opt": flags.insert(.maskAlternate)
  default: print("unknown modifier \(m)"); exit(2)
  }
}
let app = args[2]
let escape = args.contains("--escape")

func overlayWindows() -> Int {
  let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
  return list.filter {
    ($0[kCGWindowOwnerName as String] as? String) == app && (($0[kCGWindowLayer as String] as? Int) ?? 0) > 0
  }.count
}

func press(_ code: CGKeyCode, _ mods: CGEventFlags) {
  let source = CGEventSource(stateID: .hidSystemState)
  for down in [true, false] {
    guard let e = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down) else { return }
    e.flags = mods
    e.post(tap: .cghidEventTap)
    usleep(30_000)
  }
}

let before = overlayWindows()
press(keycode, flags)
usleep(1_200_000)
let after = overlayWindows()
print("\(app) overlay windows: before=\(before) after=\(after) -> hotkey \(after > before ? "FIRED" : "DID NOT FIRE")")
if escape && after > before {
  press(53, [])  // kVK_Escape
  usleep(400_000)
  print("sent Escape; overlay windows now=\(overlayWindows())")
}
