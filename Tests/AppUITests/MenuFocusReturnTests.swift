import Darwin
import Testing

@testable import AppUI

@MainActor
struct MenuFocusReturnTests {
    @MainActor
    private final class Screen {
        var front: pid_t?
        var activated: [pid_t] = []
        var looks = 0
        /// The other app takes focus at this look, if ever.
        var answersAtLook: Int?
        let own: pid_t = 1
        let other: pid_t = 2

        var system: MenuFocusReturn.System {
            MenuFocusReturn.System(
                ownProcess: own,
                frontmost: { [self] in
                    looks += 1
                    if let answersAtLook, looks >= answersAtLook { front = other }
                    return front
                },
                activate: { [self] in activated.append($0) },
                pause: { await Task.yield() })
        }
    }

    private func run(_ focus: MenuFocusReturn, seeing screen: Screen) async -> pid_t? {
        await withCheckedContinuation { continuation in
            focus.run { continuation.resume(returning: screen.front) }
        }
    }

    @Test func theActionWaitsUntilThePreviousAppHasFocus() async {
        let screen = Screen()
        screen.front = screen.other
        let focus = MenuFocusReturn(system: screen.system)
        focus.remember()
        screen.front = screen.own
        screen.answersAtLook = 5

        let frontAtAction = await run(focus, seeing: screen)

        #expect(screen.activated == [screen.other])
        #expect(frontAtAction == screen.other)
    }

    @Test func nothingIsActivatedWhenThisAppWasAlreadyFrontmost() async {
        let screen = Screen()
        screen.front = screen.own
        let focus = MenuFocusReturn(system: screen.system)
        focus.remember()
        var ran = false
        focus.run { ran = true }
        #expect(ran, "Settings is where the user was, so it runs at once")
        #expect(screen.activated.isEmpty)
    }

    @Test func theActionStillRunsWhenThePreviousAppNeverAnswers() async {
        let screen = Screen()
        screen.front = screen.other
        let focus = MenuFocusReturn(system: screen.system)
        focus.remember()
        screen.front = screen.own

        let frontAtAction = await run(focus, seeing: screen)

        #expect(frontAtAction == screen.own)
        #expect(screen.looks > 5, "It waited before giving up")
    }

    @Test func aRememberedAppIsUsedOnce() async {
        let screen = Screen()
        screen.front = screen.other
        let focus = MenuFocusReturn(system: screen.system)
        focus.remember()
        _ = await run(focus, seeing: screen)
        _ = await run(focus, seeing: screen)
        #expect(screen.activated == [screen.other])
    }
}
