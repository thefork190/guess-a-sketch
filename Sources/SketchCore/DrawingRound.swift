import Foundation
import Observation

@MainActor @Observable public final class DrawingRound {
    public enum Phase: Equatable { case ready, drawing, matched, timedOut }
    public struct Guess: Identifiable {
        public let id = UUID()
        public let text: String
        public let seconds: Double
    }
    public private(set) var drawing = Drawing()
    public private(set) var prompt: DrawPrompt
    public var noTimerForNextRound = false
    public private(set) var isUntimed = false
    public var ink: Ink = .black
    public private(set) var phase: Phase = .ready
    public private(set) var remaining = 60
    public private(set) var history: [Guess] = []
    public private(set) var busy = false
    public private(set) var error: String?
    public private(set) var unavailable: String?
    @ObservationIgnored private let guesser: any SketchGuesser
    @ObservationIgnored private let now: () -> ContinuousClock.Instant
    @ObservationIgnored private var deadline: ContinuousClock.Instant?
    @ObservationIgnored private var nextGuess: ContinuousClock.Instant?
    @ObservationIgnored private var lastSent: Drawing?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var request: Task<Void, Never>?

    public init(guesser: any SketchGuesser = AppleSketchGuesser(),
                prompt: DrawPrompt = DrawPrompt.all.randomElement()!,
                now: @escaping () -> ContinuousClock.Instant = { .now }) {
        self.guesser = guesser; self.prompt = prompt; self.now = now
        refreshAvailability()
    }

    public func refreshAvailability() { unavailable = guesser.unavailableReason }

    public func start() {
        generation = UUID()
        request?.cancel()
        // Cancellation is advisory. Only the actual request's completion releases busy.
        drawing.clear(); history = []; lastSent = nil; error = nil; ink = .black
        remaining = 60; phase = .drawing
        let instant = now()
        isUntimed = noTimerForNextRound
        deadline = isUntimed ? nil : instant.advanced(by: .seconds(60))
        nextGuess = instant.advanced(by: .seconds(4))
        refreshAvailability()
    }

    public func newRound() {
        prompt = DrawPrompt.all.filter { $0 != prompt }.randomElement()!
        start()
    }

    public func edit(_ value: Drawing) {
        expireIfNeeded()
        guard phase == .drawing else { return }
        drawing = value
    }
    public func undo() { var value = drawing; value.undo(); edit(value) }
    public func clear() { edit(Drawing()) }

    private func expireIfNeeded() {
        guard phase == .drawing, let deadline else { return }
        let instant = now()
        if instant >= deadline {
            remaining = 0; phase = .timedOut; generation = UUID(); request?.cancel()
        } else {
            remaining = Int(ceil(seconds(instant.duration(to: deadline))))
        }
    }

    private func seconds(_ duration: Duration) -> Double {
        let parts = duration.components
        return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
    }

    /// Called frequently for the clock; submission cadence is independently limited to 4s.
    @discardableResult public func tick() -> Task<Void, Never>? {
        expireIfNeeded()
        guard phase == .drawing, !busy, let nextGuess, now() >= nextGuess else { return nil }
        refreshAvailability()
        guard unavailable == nil, !drawing.strokes.isEmpty, drawing != lastSent else { return nil }
        guard let bitmap = drawing.bitmap() else { error = "Could not render the canvas."; return nil }
        lastSent = drawing
        self.nextGuess = now().advanced(by: .seconds(4))
        busy = true; error = nil
        let token = generation
        let start = now()
        let task = Task { [self] in
            defer { busy = false; request = nil }
            do {
                let answer = try await guesser.guess(image: bitmap)
                expireIfNeeded()
                guard token == generation, phase == .drawing else { return }
                history.insert(Guess(text: answer, seconds: seconds(start.duration(to: now()))), at: 0)
                history = Array(history.prefix(4))
                if prompt.matches(answer) { phase = .matched }
            } catch {
                expireIfNeeded()
                guard token == generation, phase == .drawing else { return }
                self.error = "Couldn’t guess: \(error.localizedDescription)"
            }
        }
        request = task
        return task
    }
}
