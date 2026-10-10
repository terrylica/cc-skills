// sidefx — does pressing a combo make ANYTHING else on the Mac react?
//
// Nothing of ours is registered. For each combo: snapshot (on-screen windows
// by owner/layer/bounds, frontmost app, pasteboard changeCount), press the
// combo through System Events, wait, snapshot again, and diff. The pseudo-
// combo "null" skips the keypress and measures background churn.
// floating-clock windows are ignored (they resize every second by design).
// Positive control: a combo another running app has registered must REACT.
// Known benign diff: the first keypress in a text field hides the mouse
// pointer ("Window Server" at layer 2147483630, ~15x24) — any combo does it.
//
//   make hotkey-tools && build/hotkey-check/sidefx null ctrl+opt+shift+cmd+H
import AppKit
import Foundation

struct Snap: Equatable {
    var windows: Set<String>
    var front: String
    var pb: Int
}

func snap() -> Snap {
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
    var w = Set<String>()
    for d in list {
        let owner = d[kCGWindowOwnerName as String] as? String ?? "?"
        if owner == "floating-clock" { continue }
        let b = d[kCGWindowBounds as String] as? [String: Any] ?? [:]
        let layer = d[kCGWindowLayer as String] as? Int ?? 0
        w.insert("\(owner)|L\(layer)|\(b["X"] ?? 0),\(b["Y"] ?? 0),\(b["Width"] ?? 0)x\(b["Height"] ?? 0)")
    }
    let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?"
    return Snap(windows: w, front: front, pb: NSPasteboard.general.changeCount)
}

let codes: [String: Int] = ["A": 0, "S": 1, "D": 2, "F": 3, "H": 4, "G": 5, "Z": 6, "X": 7, "C": 8,
    "V": 9, "B": 11, "Q": 12, "W": 13, "E": 14, "R": 15, "Y": 16, "T": 17, "O": 31, "U": 32,
    "I": 34, "P": 35, "L": 37, "J": 38, "K": 40, "N": 45, "M": 46]

func press(_ combo: String) {
    var parts = combo.split(separator: "+").map(String.init)
    let key = parts.removeLast()
    var using: [String] = []
    for p in parts {
        switch p {
        case "ctrl": using.append("control down")
        case "opt": using.append("option down")
        case "shift": using.append("shift down")
        case "cmd": using.append("command down")
        default: break
        }
    }
    let script = "tell application \"System Events\" to key code \(codes[key]!)" + (using.isEmpty ? "" : " using {" + using.joined(separator: ", ") + "}")
    let t = Process()
    t.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    t.arguments = ["-e", script]
    try? t.run(); t.waitUntilExit()
}

var anyReaction = false
for combo in CommandLine.arguments.dropFirst() {
    let a = snap()
    if combo != "null" { press(combo) }
    Thread.sleep(forTimeInterval: 1.0)
    let b = snap()
    var notes: [String] = []
    let added = b.windows.subtracting(a.windows), removed = a.windows.subtracting(b.windows)
    if !added.isEmpty { notes.append("+windows \(added.sorted())") }
    if !removed.isEmpty { notes.append("-windows \(removed.sorted())") }
    if a.front != b.front { notes.append("front \(a.front) -> \(b.front)") }
    if a.pb != b.pb { notes.append("pasteboard changed") }
    print("\(notes.isEmpty ? "QUIET" : "REACTED")\t\(combo)\t\(notes.joined(separator: "; "))")
    if !notes.isEmpty && combo != "null" { anyReaction = true }
}
exit(anyReaction ? 1 : 0)
