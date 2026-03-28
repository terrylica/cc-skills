@testable import CompanionCore
import Testing

@Suite struct CircuitBreakerTests {
    @Test func startsInClosedState() {
        let cb = CircuitBreaker(maxFailures: 3, cooldownSeconds: 60)
        #expect(!cb.isOpen)
    }

    @Test func opensAfterMaxFailures() {
        let cb = CircuitBreaker(maxFailures: 2, cooldownSeconds: 60)
        cb.recordFailure()
        cb.recordFailure()
        #expect(cb.isOpen)
    }

    @Test func doesNotOpenBeforeMaxFailures() {
        let cb = CircuitBreaker(maxFailures: 3, cooldownSeconds: 60)
        cb.recordFailure()
        cb.recordFailure()
        #expect(!cb.isOpen)
    }

    @Test func resetsOnSuccess() {
        let cb = CircuitBreaker(maxFailures: 2, cooldownSeconds: 60)
        cb.recordFailure()
        cb.recordSuccess()
        cb.recordFailure()
        #expect(!cb.isOpen) // Only 1 consecutive failure after reset
    }

    @Test func closesAfterCooldown() async throws {
        let cb = CircuitBreaker(maxFailures: 1, cooldownSeconds: 0.1)
        cb.recordFailure()
        #expect(cb.isOpen)
        try await Task.sleep(for: .milliseconds(150))
        #expect(!cb.isOpen) // Cooldown expired
    }

    @Test func tracksFailureCount() {
        let cb = CircuitBreaker(maxFailures: 5, cooldownSeconds: 60)
        #expect(cb.failureCount == 0)
        cb.recordFailure()
        #expect(cb.failureCount == 1)
        cb.recordFailure()
        #expect(cb.failureCount == 2)
        cb.recordSuccess()
        #expect(cb.failureCount == 0)
    }
}
