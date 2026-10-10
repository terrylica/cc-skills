// wins — list on-screen windows (owner, layer, pid, bounds), optionally
// filtered by an owner-name substring. The visibility tests count
// `wins floating` lines: 0 = clock hidden, N = clock + N-1 rails shown.
import CoreGraphics
import Foundation
let filter = CommandLine.arguments.count > 1 ? CommandLine.arguments[1].lowercased() : ""
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
for w in list {
    let owner = w[kCGWindowOwnerName as String] as? String ?? "?"
    if !filter.isEmpty && !owner.lowercased().contains(filter) { continue }
    let b = w[kCGWindowBounds as String] as? [String: Any] ?? [:]
    print("\(owner)\tlayer=\(w[kCGWindowLayer as String] ?? "?")\tpid=\(w[kCGWindowOwnerPID as String] ?? "?")\t\(b["X"] ?? 0),\(b["Y"] ?? 0) \(b["Width"] ?? 0)x\(b["Height"] ?? 0)")
}
