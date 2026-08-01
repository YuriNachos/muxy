import AppKit
import Testing
@testable import Muxy

@Suite("GhosttyTerminalNSView mouse routing")
@MainActor
struct TerminalMouseRoutingTests {
    @Test func plainLeftPressReachesTheSurface() {
        #expect(GhosttyTerminalNSView.forwardsLeftMousePress(commandHeld: false))
    }

    @Test func commandLeftPressNeverReachesTheSurface() {
        #expect(GhosttyTerminalNSView.forwardsLeftMousePress(commandHeld: true) == false)
    }

    @Test func forwardedPressAlwaysReleases() {
        #expect(GhosttyTerminalNSView.forwardsLeftMouseRelease(routing: .forwardedToSurface, didDrag: false))
        #expect(GhosttyTerminalNSView.forwardsLeftMouseRelease(routing: .forwardedToSurface, didDrag: true))
    }

    @Test func commandClickReleasesSoLinksStillOpen() {
        #expect(GhosttyTerminalNSView.forwardsLeftMouseRelease(routing: .commandPending, didDrag: false))
    }

    @Test func commandDragDoesNotRelease() {
        #expect(GhosttyTerminalNSView.forwardsLeftMouseRelease(routing: .commandPending, didDrag: true) == false)
    }

    @Test func handledCommandClickDoesNotRelease() {
        #expect(GhosttyTerminalNSView.forwardsLeftMouseRelease(routing: .commandHandled, didDrag: false) == false)
        #expect(GhosttyTerminalNSView.forwardsLeftMouseRelease(routing: .commandHandled, didDrag: true) == false)
    }

    @Test func releaseWithoutPressIsDropped() {
        #expect(GhosttyTerminalNSView.forwardsLeftMouseRelease(routing: .ignored, didDrag: false) == false)
        #expect(GhosttyTerminalNSView.forwardsLeftMouseRelease(routing: .ignored, didDrag: true) == false)
    }

    @Test func overlayOnlyLetsAForwardedPressRelease() {
        #expect(GhosttyTerminalNSView.reachesSurfaceWhileOverlayActive(routing: .forwardedToSurface))
        #expect(GhosttyTerminalNSView.reachesSurfaceWhileOverlayActive(routing: .commandPending) == false)
        #expect(GhosttyTerminalNSView.reachesSurfaceWhileOverlayActive(routing: .commandHandled) == false)
        #expect(GhosttyTerminalNSView.reachesSurfaceWhileOverlayActive(routing: .ignored) == false)
    }

    @Test func rightPressNeverReachesTheSurfaceWithoutMouseReporting() {
        #expect(GhosttyTerminalNSView.forwardsRightMouseButton(mouseCaptured: false, shiftHeld: false) == false)
    }

    @Test func rightPressReachesMouseReportingPrograms() {
        #expect(GhosttyTerminalNSView.forwardsRightMouseButton(mouseCaptured: true, shiftHeld: false))
    }

    @Test func shiftRightClickBypassesMouseReportingPrograms() {
        #expect(GhosttyTerminalNSView.forwardsRightMouseButton(mouseCaptured: true, shiftHeld: true) == false)
    }
}

@Suite("Drag activation")
struct DragActivationTests {
    @Test func jitterWithinTheThresholdIsNotADrag() {
        #expect(DragActivation.exceedsDistance(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 102, y: 101)) == false)
    }

    @Test func movementAtExactlyTheThresholdIsNotADrag() {
        #expect(DragActivation.exceedsDistance(
            from: CGPoint(x: 100, y: 100),
            to: CGPoint(x: 100, y: 100 + DragActivation.distance)
        ) == false)
    }

    @Test func movementBeyondTheThresholdIsADrag() {
        #expect(DragActivation.exceedsDistance(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 100, y: 106)))
    }
}

@Suite("TabAreaView command drag")
@MainActor
struct TabAreaCommandDragTests {
    @Test func commandHeldAtGestureStartBeginsThePaneDrag() {
        #expect(TabAreaView.startsCommandDrag(commandHeld: true, isRejected: false))
    }

    @Test func gestureStartedWithoutCommandNeverBecomesAPaneDrag() {
        #expect(TabAreaView.startsCommandDrag(commandHeld: false, isRejected: false) == false)
        #expect(TabAreaView.startsCommandDrag(commandHeld: true, isRejected: true) == false)
    }
}
