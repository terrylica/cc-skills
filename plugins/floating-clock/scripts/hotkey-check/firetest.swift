// firetest — can a combo reach a Carbon global hotkey at all?
//
// For each combo given on the command line ("ctrl+opt+shift+cmd+H" style):
//   1. registers it as a Carbon global hotkey in THIS process,
//   2. presses it through System Events (the path a real keystroke takes past
//      event taps; a direct CGEventPost from a terminal child is dropped),
//   3. pumps the AppKit event loop and reports whether our handler fired.
// FIRED  -> the chord reached the Carbon dispatcher intact (no event tap such
//           as BTT, Karabiner or Hammerspoon swallowed or rewrote it first).
// MISSED -> something upstream consumed or altered it.
//
// It does NOT prove nobody else listens: on current macOS a Carbon hotkey is
// delivered to EVERY process that registered it (verified 2026-10-10 against
// another app's registered hotkey: both fired), and RegisterEventHotKey only refuses duplicates
// within one process. Use sidefx for "does anything else react?".
//
//   make hotkey-tools && build/hotkey-check/firetest ctrl+opt+shift+cmd+H
import AppKit
import Carbon
import Foundation

let keyCodes: [String: UInt32] = [
    "A": 0, "S": 1, "D": 2, "F": 3, "H": 4, "G": 5, "Z": 6, "X": 7, "C": 8, "V": 9,
    "B": 11, "Q": 12, "W": 13, "E": 14, "R": 15, "Y": 16, "T": 17, "1": 18, "2": 19,
    "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28,
    "0": 29, "]": 30, "O": 31, "U": 32, "[": 33, "I": 34, "P": 35, "L": 37, "J": 38,
    "'": 39, "K": 40, ";": 41, "\\": 42, ",": 43, "/": 44, "N": 45, "M": 46, ".": 47,
    "`": 50, "F1": 122, "F2": 120, "F3": 99, "F4": 118, "F5": 96, "F6": 97, "F7": 98,
    "F8": 100, "F9": 101, "F10": 109, "F11": 103, "F12": 111, "F13": 105, "F14": 107,
    "F15": 113, "F16": 106, "F17": 64, "F18": 79, "F19": 80, "F20": 90,
    "Space": 49, "Return": 36, "Tab": 48, "Escape": 53,
]

func parse(_ s: String) -> (UInt32, UInt32, CGEventFlags)? {
    var parts = s.split(separator: "+").map(String.init)
    guard let key = parts.popLast(), let code = keyCodes[key] else { return nil }
    var carbon: UInt32 = 0
    var flags = CGEventFlags()
    for p in parts {
        switch p {
        case "ctrl": carbon |= UInt32(controlKey); flags.insert(.maskControl)
        case "opt": carbon |= UInt32(optionKey); flags.insert(.maskAlternate)
        case "shift": carbon |= UInt32(shiftKey); flags.insert(.maskShift)
        case "cmd": carbon |= UInt32(cmdKey); flags.insert(.maskCommand)
        default: return nil
        }
    }
    // F-keys carry the secondary-fn flag when typed on a real keyboard.
    if key.hasPrefix("F"), key.count > 1 { flags.insert(.maskSecondaryFn) }
    return (code, carbon, flags)
}

_ = NSApplication.shared
NSApp.setActivationPolicy(.accessory)
NSApp.finishLaunching()
var fired = 0
var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
    fired += 1
    return noErr
}, 1, &spec, nil, nil)

func pump(_ secs: Double) {
    let end = Date().addingTimeInterval(secs)
    while Date() < end {
        if let e = NSApp.nextEvent(matching: .any, until: Date().addingTimeInterval(0.02), inMode: .default, dequeue: true) { NSApp.sendEvent(e) }
        if fired > 0 { return }
    }
}
if !AXIsProcessTrusted() {
    FileHandle.standardError.write("WARN: not AX-trusted; posted events may be dropped\n".data(using: .utf8)!)
}

var exitCode: Int32 = 0
for (i, combo) in CommandLine.arguments.dropFirst().enumerated() {
    guard let (code, carbon, flags) = parse(combo) else {
        print("BADSPEC\t\(combo)"); exitCode = 2; continue
    }
    var ref: EventHotKeyRef?
    let st = RegisterEventHotKey(code, carbon, EventHotKeyID(signature: OSType(0x4654_5354), id: UInt32(i + 1)),
                                 GetApplicationEventTarget(), 0, &ref)
    guard st == noErr, let r = ref else { print("REGERR\(st)\t\(combo)"); exitCode = 1; continue }
    fired = 0
    // Post through System Events: the same path a real keypress takes past
    // event taps (direct CGEventPost from this process is dropped by TCC).
    var using: [String] = []
    if carbon & UInt32(controlKey) != 0 { using.append("control down") }
    if carbon & UInt32(optionKey) != 0 { using.append("option down") }
    if carbon & UInt32(shiftKey) != 0 { using.append("shift down") }
    if carbon & UInt32(cmdKey) != 0 { using.append("command down") }
    _ = flags
    let script = "tell application \"System Events\" to key code \(code)" + (using.isEmpty ? "" : " using {" + using.joined(separator: ", ") + "}")
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    task.arguments = ["-e", script]
    try? task.run()
    while task.isRunning { pump(0.02) }
    pump(0.6)
    UnregisterEventHotKey(r)
    print("\(fired > 0 ? "FIRED" : "MISSED")\t\(combo)")
    if fired == 0 { exitCode = 1 }
}
exit(exitCode)
