// SandboxDiagBrokerRunner — launchd entry point for the read-only sandbox diagnostics broker.
//
// Why a compiled shim (launchd-runner policy): the Background panel labels a job by the code
// signature of the executable launchd starts. Pointing the plist at /usr/bin/python3 would show an
// opaque "python3" row; this shim is ad-hoc signed as com.terryli.sandbox-diag-broker-runner.
//
// It refuses to start a broker that is not root-owned or is writable by others, because the whole
// point of the broker is that an agent cannot change what it runs outside the sandbox.
import Foundation

let dir = "/usr/local/libexec/claude-code-sandbox-policy"
let python = "/usr/bin/python3"
let broker = dir + "/sandbox_diag_broker.py"

func rootOwnedAndLocked(_ path: String) -> Bool {
    guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
          let owner = attrs[.ownerAccountID] as? NSNumber,
          let perms = attrs[.posixPermissions] as? NSNumber else { return false }
    return owner.intValue == 0 && (perms.intValue & 0o022) == 0
}

guard FileManager.default.isExecutableFile(atPath: python) else {
    FileHandle.standardError.write("sandbox-diag-broker-runner: \(python) missing\n".data(using: .utf8)!)
    exit(78)
}
guard rootOwnedAndLocked(broker) else {
    FileHandle.standardError.write("sandbox-diag-broker-runner: \(broker) missing, not root-owned, or group/world-writable\n".data(using: .utf8)!)
    exit(78)
}

var args = [python, broker] + CommandLine.arguments.dropFirst()
let cargs = args.map { strdup($0) } + [nil]
execv(python, cargs)
FileHandle.standardError.write("sandbox-diag-broker-runner: execv failed: \(String(cString: strerror(errno)))\n".data(using: .utf8)!)
exit(71)
