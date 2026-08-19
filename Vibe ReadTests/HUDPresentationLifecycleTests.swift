import Testing
@testable import Vibe_Read

struct HUDPresentationLifecycleTests {
    @Test func currentPresentationAcceptsItsOwnDelayedWork() {
        var guardState = HUDPresentationTokenGuard()
        let token = guardState.beginPresentation()

        #expect(guardState.isCurrent(token))
    }

    @Test func newerPresentationInvalidatesOldTimerAndAnimationCallbacks() {
        var guardState = HUDPresentationTokenGuard()
        let oldTimerToken = guardState.beginPresentation()
        let oldAnimationToken = guardState.currentToken

        let currentToken = guardState.beginPresentation()

        #expect(!guardState.isCurrent(oldTimerToken))
        #expect(!guardState.isCurrent(oldAnimationToken))
        #expect(guardState.isCurrent(currentToken))
    }

    @Test func everyPresentationAdvancesTheGeneration() {
        var guardState = HUDPresentationTokenGuard()
        let first = guardState.beginPresentation()
        let second = guardState.beginPresentation()
        let third = guardState.beginPresentation()

        #expect(first != second)
        #expect(second != third)
        #expect(guardState.currentToken == third)
    }
}
