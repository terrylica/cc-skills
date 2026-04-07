@testable import CompanionCore
import Foundation
import Testing

/// Chaos tests for the WAV path fallback chain introduced in h07.
///
/// These tests do NOT invoke afplay or play audio. They exercise
/// `ensureWritableWavDirectory()` and `getAfplayHealthSnapshot()` in isolation
/// by manipulating the filesystem state of `~/.local/share/tts-debug-wav/`.
///
/// On the pre-fix AfplayPlayer, these tests fail to compile because:
///   - there is no `ensureWritableWavDirectoryForTesting()` shim
///   - there is no `getAfplayHealthSnapshot()` method
///   - there are no `__testing_*` accessors
/// Failure-to-compile is a strictly stronger form of "test fails on pre-fix code".
@Suite(.serialized)
@MainActor
struct AfplayPlayerChaosTests {

    private var primaryDir: String {
        NSHomeDirectory() + "/.local/share/tts-debug-wav"
    }

    /// Helper: ensure primary exists and is writable before each test.
    private func resetPrimary() {
        let fm = FileManager.default
        let parent = (primaryDir as NSString).deletingLastPathComponent
        _ = chmod(parent, 0o755)
        try? fm.createDirectory(atPath: primaryDir, withIntermediateDirectories: true)
        _ = chmod(primaryDir, 0o755)
    }

    @Test func primaryRecreatesWhenDeleted() throws {
        resetPrimary()
        let player = AfplayPlayer()

        // Chaos: delete the primary dir
        try? FileManager.default.removeItem(atPath: primaryDir)
        #expect(!FileManager.default.fileExists(atPath: primaryDir),
                "Primary dir should be deleted before act")

        // Act: resolve — should recreate primary
        let resolved = player.ensureWritableWavDirectoryForTesting()
        #expect(resolved.level == 0, "Primary should recreate successfully")
        #expect(FileManager.default.fileExists(atPath: primaryDir),
                "Primary dir should be recreated")

        let snap = player.getAfplayHealthSnapshot()
        #expect(snap.primary_dir_writable == true)
        #expect(snap.fallback_level == 0)
        #expect(snap.consecutive_failure_count == 0)
    }

    @Test func fallsBackWhenPrimaryUnwritable() throws {
        resetPrimary()
        let fm = FileManager.default
        let parent = (primaryDir as NSString).deletingLastPathComponent

        // Remove primary and make parent read-only
        try? fm.removeItem(atPath: primaryDir)
        let chmodResult = chmod(parent, 0o500)
        guard chmodResult == 0 else {
            // Cannot execute chaos on this filesystem; skip gracefully
            return
        }
        defer { _ = chmod(parent, 0o755); resetPrimary() }

        let player = AfplayPlayer()
        let resolved = player.ensureWritableWavDirectoryForTesting()
        #expect(resolved.level >= 1, "Expected fallback to level 1 or 2, got \(resolved.level)")

        let snap = player.getAfplayHealthSnapshot()
        #expect(snap.fallback_level >= 1)
        #expect(snap.consecutive_failure_count >= 1)
        #expect(snap.last_failure_class != nil)
    }

    @Test func failureLoggedAtMostOncePerClassIn60sWindow() throws {
        resetPrimary()
        let fm = FileManager.default
        let parent = (primaryDir as NSString).deletingLastPathComponent

        try? fm.removeItem(atPath: primaryDir)
        let chmodResult = chmod(parent, 0o500)
        guard chmodResult == 0 else { return }
        defer { _ = chmod(parent, 0o755); resetPrimary() }

        let player = AfplayPlayer()
        // Hammer the resolver to force repeated failures
        for _ in 0..<10 {
            _ = player.ensureWritableWavDirectoryForTesting()
        }

        #expect(player.__testing_consecutiveFailureCount >= 10,
                "Failures should accumulate")
        #expect(player.__testing_loggedClassCount <= 2,
                "At most one log per class (primary + possibly tmp); got \(player.__testing_loggedClassCount)")
    }

    @Test func recoveryResetsStateAndIsIdempotent() throws {
        resetPrimary()
        let fm = FileManager.default
        let parent = (primaryDir as NSString).deletingLastPathComponent

        // Put player into failing state
        try? fm.removeItem(atPath: primaryDir)
        let chmodResult = chmod(parent, 0o500)
        guard chmodResult == 0 else { return }
        let player = AfplayPlayer()
        _ = player.ensureWritableWavDirectoryForTesting()
        let failingSnap = player.getAfplayHealthSnapshot()
        #expect(failingSnap.fallback_level >= 1)

        // Restore writability
        _ = chmod(parent, 0o755)
        defer { resetPrimary() }

        // First recovery call resets state
        let recovered = player.ensureWritableWavDirectoryForTesting()
        #expect(recovered.level == 0)
        let recoveredSnap = player.getAfplayHealthSnapshot()
        #expect(recoveredSnap.fallback_level == 0)
        #expect(recoveredSnap.consecutive_failure_count == 0)

        // Second call is a no-op at the telemetry level
        _ = player.ensureWritableWavDirectoryForTesting()
        let idempotentSnap = player.getAfplayHealthSnapshot()
        #expect(idempotentSnap.fallback_level == 0)
        #expect(idempotentSnap.consecutive_failure_count == 0)
    }
}
