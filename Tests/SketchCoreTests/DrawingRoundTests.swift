import CoreGraphics
import Testing
@testable import SketchCore

@MainActor private final class TestClock {
    var instant = ContinuousClock.now
    func advance(_ seconds: Int) { instant = instant.advanced(by: .seconds(seconds)) }
}

// Deliberately ignores task cancellation, like a model service that keeps running.
@MainActor private final class DeferredGuesser: SketchGuesser {
    var unavailableReason: String?
    var calls = 0
    var active = 0
    var maximumActive = 0
    var continuation: CheckedContinuation<String, any Error>?
    func guess(image: CGImage) async throws -> String {
        calls += 1; active += 1; maximumActive = max(active, maximumActive)
        defer { active -= 1 }
        return try await withCheckedThrowingContinuation { continuation = $0 }
    }
    func finish(_ answer: String) { let pending = continuation; continuation = nil; pending?.resume(returning: answer) }
    func fail() { let pending = continuation; continuation = nil; pending?.resume(throwing: GuessError.emptyResponse) }
}

private func mark(_ x: CGFloat = 0.2) -> Drawing {
    var drawing = Drawing()
    drawing.strokes = [Stroke([CGPoint(x: x, y: 0.2)])]
    return drawing
}

@Test @MainActor func cadenceChangedCanvasAndHistory() async throws {
    let clock = TestClock(), guesser = DeferredGuesser()
    let round = DrawingRound(guesser: guesser, prompt: DrawPrompt("cat"), now: { clock.instant })
    round.start()
    round.edit(mark())
    clock.advance(3)
    #expect(round.tick() == nil) // Not yet due.
    round.clear()
    clock.advance(1)
    #expect(round.tick() == nil) // Empty canvas.
    round.edit(mark())
    let first = try #require(round.tick())
    await Task.yield()
    #expect(guesser.calls == 1)
    #expect(round.tick() == nil)
    round.edit(mark(0.3)) // Drawing remains editable during a real pending request.
    #expect(round.drawing == mark(0.3))
    round.edit(mark())
    guesser.finish("tree"); await first.value
    clock.advance(4)
    #expect(round.tick() == nil) // Identical bitmap is not resubmitted.
    for n in 1...5 {
        round.edit(mark(CGFloat(n) / 10))
        let task = try #require(round.tick())
        await Task.yield()
        guesser.finish("guess \(n)"); await task.value
        clock.advance(4)
    }
    #expect(round.history.count == 4)
    #expect(round.history.first?.text == "guess 5")
    #expect(guesser.maximumActive == 1)
}

@Test @MainActor func resetDoesNotOverlapCancellationIgnoringRequest() async throws {
    let clock = TestClock(), guesser = DeferredGuesser()
    let round = DrawingRound(guesser: guesser, prompt: DrawPrompt("cat"), now: { clock.instant })
    round.start(); round.edit(mark()); clock.advance(4)
    let old = try #require(round.tick()); await Task.yield()
    round.start(); round.edit(mark(0.5)); clock.advance(4)
    #expect(round.busy)
    #expect(round.tick() == nil)
    guesser.finish("cat"); await old.value
    #expect(round.phase == .drawing)
    #expect(round.history.isEmpty)
    let current = try #require(round.tick()); await Task.yield()
    guesser.finish("cat"); await current.value
    #expect(round.phase == .matched)
    #expect(round.history.count == 1)
    #expect(round.tick() == nil)
    #expect(guesser.maximumActive == 1)
}

@Test @MainActor func deadlineRejectsLateResponseWithoutTimerTick() async throws {
    let clock = TestClock(), guesser = DeferredGuesser()
    let round = DrawingRound(guesser: guesser, prompt: DrawPrompt("cat"), now: { clock.instant })
    round.start(); round.edit(mark()); clock.advance(4)
    let task = try #require(round.tick()); await Task.yield()
    clock.advance(56)
    guesser.finish("cat"); await task.value
    #expect(round.phase == .timedOut)
    #expect(round.remaining == 0)
    #expect(round.history.isEmpty)
    round.edit(mark(0.9))
    #expect(round.drawing == mark())
}

@Test @MainActor func noTimerAppliesOnlyToNewRound() async throws {
    let clock = TestClock(), guesser = DeferredGuesser()
    let round = DrawingRound(guesser: guesser, prompt: DrawPrompt("cat"), now: { clock.instant })
    #expect(!round.noTimerForNextRound)
    round.start(); round.noTimerForNextRound = true
    clock.advance(59); round.tick()
    #expect(round.remaining == 1)
    clock.advance(1); round.tick()
    #expect(round.phase == .timedOut)
    round.start(); round.noTimerForNextRound = false
    clock.advance(3600); round.tick()
    #expect(round.isUntimed && round.phase == .drawing)
    round.edit(mark())
    let task = try #require(round.tick()); await Task.yield()
    guesser.finish("cat"); await task.value
    #expect(round.phase == .matched)
    round.start()
    #expect(!round.isUntimed && round.remaining == 60)
}

@Test @MainActor func unavailableAndErrorRecovery() async throws {
    let clock = TestClock(), guesser = DeferredGuesser()
    guesser.unavailableReason = "Not ready"
    let round = DrawingRound(guesser: guesser, now: { clock.instant })
    round.start(); round.edit(mark()); clock.advance(4)
    #expect(round.tick() == nil)
    #expect(round.unavailable == "Not ready")
    guesser.unavailableReason = nil
    let task = try #require(round.tick()); await Task.yield()
    guesser.fail(); await task.value
    #expect(round.error != nil && !round.busy)
    clock.advance(4)
    #expect(round.tick() == nil)
    round.edit(mark(0.7))
    let retry = try #require(round.tick()); await Task.yield()
    guesser.finish("unknown"); await retry.value
    #expect(round.error == nil && round.history.count == 1)
}

@Test @MainActor func staleErrorAfterUntimedResetIsIgnored() async throws {
    let clock = TestClock(), guesser = DeferredGuesser()
    let round = DrawingRound(guesser: guesser, now: { clock.instant })
    round.noTimerForNextRound = true
    round.start(); round.edit(mark()); clock.advance(4)
    let task = try #require(round.tick()); await Task.yield()
    round.newRound(); round.edit(mark(0.8)); clock.advance(3600)
    #expect(round.tick() == nil)
    #expect(round.busy && round.phase == .drawing)
    guesser.fail(); await task.value
    #expect(round.error == nil && round.history.isEmpty && !round.busy)
    #expect(guesser.maximumActive == 1)
}

@Test func coloredStrokesAndDotsSurviveExport() throws {
    var drawing = Drawing()
    drawing.strokes = [Stroke([CGPoint(x: 0.25, y: 0.25)], ink: .red),
                       Stroke([CGPoint(x: 0.5, y: 0.5), CGPoint(x: 0.8, y: 0.5)], ink: .blue)]
    let image = try #require(drawing.bitmap())
    let data = try #require(image.dataProvider?.data)
    let bytes = try #require(CFDataGetBytePtr(data))
    let red = 150 * image.bytesPerRow + 150 * 4
    let blue = 300 * image.bytesPerRow + 360 * 4
    #expect(Int(bytes[red]) > 2 * Int(bytes[red + 1]) && Int(bytes[red]) > 2 * Int(bytes[red + 2]))
    #expect(bytes[blue + 2] > 200 && bytes[blue] < 50)
    drawing.undo()
    #expect(drawing.strokes.first?.ink == .red)
    #expect(Stroke([]).ink == .black)
}
