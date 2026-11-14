import AppKit
import SwiftUI
import SketchCore

@main
struct GuessASketchApp: App {
    var body: some Scene {
        WindowGroup { GameView() }
            .windowResizability(.contentSize)
    }
}

@MainActor
struct GameView: View {
    let guesser: any SketchGuesser
    @State private var drawing = Drawing()
    @State private var prompt = DrawPrompt.all.randomElement()!
    @State private var busy = false
    @State private var result: String?
    @State private var matched = false
    @State private var latency: Double?
    @State private var error: String?
    @State private var unavailable: String?
    @Environment(\.scenePhase) private var scenePhase

    init(guesser: any SketchGuesser = AppleSketchGuesser()) { self.guesser = guesser }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Guess a Sketch").font(.largeTitle.bold())
                    Text("Draw it. Let your Mac take a guess.").foregroundStyle(.secondary)
                }
                Spacer()
                Label("On device", systemImage: "desktopcomputer").font(.caption)
            }
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("YOUR SECRET PROMPT").font(.caption.bold()).foregroundStyle(.secondary)
                    Text(prompt.name.capitalized).font(.title2.bold())
                }
                Spacer()
                Button("New prompt") {
                    prompt = DrawPrompt.all.filter { $0 != prompt }.randomElement()!
                    drawing.clear(); resetResult()
                }.disabled(busy)
            }
            DrawingCanvas(drawing: $drawing, enabled: !busy, onEdit: resetResult)
                .frame(width: 600, height: 600)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(.gray.opacity(0.3)))
                .accessibilityLabel("Drawing canvas. Drag with your mouse or trackpad to draw.")
            HStack {
                Button("Undo", systemImage: "arrow.uturn.backward") { drawing.undo(); resetResult() }
                    .keyboardShortcut("z", modifiers: .command)
                    .disabled(drawing.strokes.isEmpty || busy)
                Button("Clear", systemImage: "trash") { drawing.clear(); resetResult() }
                    .disabled(drawing.strokes.isEmpty || busy)
                Spacer()
                if busy { ProgressView().controlSize(.small); Text("Guessing…").foregroundStyle(.secondary) }
                Button("Guess", systemImage: "sparkle.magnifyingglass") { Task { await makeGuess() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(drawing.strokes.isEmpty || busy || unavailable != nil)
            }
            VStack(alignment: .leading, spacing: 6) {
                if let unavailable {
                    Text(unavailable).foregroundStyle(.orange)
                    Button("Retry availability") { self.unavailable = guesser.unavailableReason }
                } else if let error {
                    Text(error).foregroundStyle(.red).textSelection(.enabled)
                } else if let result {
                    HStack {
                        Text("Guess: \(result)").font(.headline)
                        Spacer()
                        Label(matched ? "Match!" : "Not a match", systemImage: matched ? "checkmark.circle.fill" : "xmark.circle")
                            .foregroundStyle(matched ? .green : .orange)
                    }
                } else {
                    Text("Use your mouse or trackpad. Press Guess when you’re ready.").foregroundStyle(.secondary)
                }
                if let latency { Text(String(format: "Inference: %.2f s", latency)).font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
                Text("Only the canvas goes to the model. Your secret prompt stays out of its input.")
                    .font(.caption).foregroundStyle(.secondary)
            }.frame(minHeight: 62, alignment: .topLeading)
        }
        .padding(24)
        .frame(width: 648)
        .onAppear { unavailable = guesser.unavailableReason }
        .onChange(of: scenePhase) { _, phase in if phase == .active { unavailable = guesser.unavailableReason } }
    }

    private func resetResult() { result = nil; error = nil; latency = nil }

    private func makeGuess() async {
        guard !busy, !drawing.strokes.isEmpty else { return }
        unavailable = guesser.unavailableReason
        guard unavailable == nil else { return }
        resetResult()
        guard let bitmap = drawing.bitmap() else { error = "Could not render the canvas. Please try again."; return }
        busy = true
        defer { busy = false }
        let start = ContinuousClock.now
        do {
            let answer = try await guesser.guess(image: bitmap)
            result = answer
            matched = prompt.matches(answer)
        } catch { self.error = "Couldn’t guess: \(error.localizedDescription)" }
        let duration = start.duration(to: .now).components
        latency = Double(duration.seconds) + Double(duration.attoseconds) / 1e18
    }
}

struct DrawingCanvas: NSViewRepresentable {
    @Binding var drawing: Drawing
    let enabled: Bool
    let onEdit: () -> Void
    func makeNSView(context: Context) -> SketchView { SketchView() }
    func updateNSView(_ view: SketchView, context: Context) {
        view.drawing = drawing
        view.enabled = enabled
        view.onChange = { drawing = $0; onEdit() }
        view.needsDisplay = true
    }
}

final class SketchView: NSView {
    var drawing = Drawing()
    var enabled = true
    var onChange: ((Drawing) -> Void)?
    private var trackingStroke = false
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        drawing.render(in: context, size: bounds.size)
    }
    private func point(_ event: NSEvent) -> CGPoint {
        let p = convert(event.locationInWindow, from: nil)
        return CGPoint(x: min(1, max(0, p.x / bounds.width)), y: min(1, max(0, p.y / bounds.height)))
    }
    override func mouseDown(with event: NSEvent) {
        guard enabled else { return }
        trackingStroke = true
        drawing.strokes.append([point(event)])
        changed()
    }
    override func mouseDragged(with event: NSEvent) {
        guard enabled, trackingStroke, !drawing.strokes.isEmpty else { return }
        drawing.strokes[drawing.strokes.count - 1].append(point(event))
        changed()
    }
    override func mouseUp(with event: NSEvent) { trackingStroke = false }
    private func changed() { needsDisplay = true; onChange?(drawing) }
}
