import AppKit
import SwiftUI
import SketchCore

@main
struct GuessASketchApp: App {
    @State private var round = DrawingRound()
    var body: some Scene {
        Window("Guess a Sketch", id: "game") { GameView(round: round) }
            .windowResizability(.contentSize)
            .commands {
                CommandMenu("Debug") {
                    Toggle("No Timer (next round)", isOn: $round.noTimerForNextRound)
                }
            }
    }
}

@MainActor
struct GameView: View {
    @Bindable var round: DrawingRound
    @Environment(\.scenePhase) private var scenePhase

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
                    Text(round.prompt.name.capitalized).font(.title2.bold())
                }
                Spacer()
                Text(round.isUntimed ? "No Timer" : "\(round.remaining)s").font(.title2.monospacedDigit())
                if round.phase == .ready {
                    Button("Start round") { round.start() }.buttonStyle(.borderedProminent)
                } else {
                    Button("New round") { round.newRound() }
                }
            }
            DrawingCanvas(drawing: Binding(get: { round.drawing }, set: { round.edit($0) }),
                          enabled: round.phase == .drawing, ink: round.ink)
                .frame(width: 600, height: 600)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(.gray.opacity(0.3)))
                .accessibilityLabel("Drawing canvas. Drag with your mouse or trackpad to draw.")
            HStack {
                Button("Undo", systemImage: "arrow.uturn.backward") { round.undo() }
                    .keyboardShortcut("z", modifiers: .command)
                    .disabled(round.drawing.strokes.isEmpty || round.phase != .drawing)
                Button("Clear", systemImage: "trash") { round.clear() }
                    .disabled(round.drawing.strokes.isEmpty || round.phase != .drawing)
                ForEach(Ink.allCases, id: \.self) { ink in
                    Button { round.ink = ink } label: {
                        Circle().fill(Color(cgColor: ink.cgColor)).frame(width: 18, height: 18)
                            .padding(3)
                            .overlay(Circle().stroke(round.ink == ink ? Color.accentColor : .clear, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(ink.rawValue.capitalized) ink")
                    .accessibilityAddTraits(round.ink == ink ? .isSelected : [])
                    .disabled(round.phase != .drawing)
                }
                Spacer()
                if round.busy { ProgressView().controlSize(.small) }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(status).font(.headline)
                if let unavailable = round.unavailable {
                    Text(unavailable).foregroundStyle(.orange)
                    Button("Retry availability") { round.refreshAvailability() }
                }
                if let error = round.error { Text(error).foregroundStyle(.red) }
                ForEach(round.history) { guess in
                    HStack {
                        Text(guess.text)
                        Spacer()
                        Text(String(format: "%.2f s", guess.seconds)).foregroundStyle(.secondary)
                    }.font(.caption)
                }
                Text("Only the canvas goes to the model. Your secret prompt stays out of its input.")
                    .font(.caption).foregroundStyle(.secondary)
            }.frame(minHeight: 100, alignment: .topLeading)
        }
        .padding(24)
        .frame(width: 648)
        .task {
            while !Task.isCancelled {
                round.tick()
                do { try await Task.sleep(for: .milliseconds(100)) } catch { break }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { round.refreshAvailability(); round.tick() }
        }
    }

    private var status: String {
        switch round.phase {
        case .ready: "Start a 60-second round when you’re ready."
        case .drawing: round.busy ? "Guessing… keep drawing!" : "Draw away — guesses update about every 4 seconds."
        case .matched: "Match!"
        case .timedOut: "Time’s up!"
        }
    }
}

struct DrawingCanvas: NSViewRepresentable {
    @Binding var drawing: Drawing
    let enabled: Bool
    let ink: Ink
    func makeNSView(context: Context) -> SketchView { SketchView() }
    func updateNSView(_ view: SketchView, context: Context) {
        view.drawing = drawing
        view.enabled = enabled
        view.ink = ink
        if !enabled || drawing.strokes.isEmpty { view.trackingStroke = false }
        view.onChange = { drawing = $0 }
        view.needsDisplay = true
    }
}

final class SketchView: NSView {
    var drawing = Drawing()
    var enabled = true
    var onChange: ((Drawing) -> Void)?
    var ink: Ink = .black
    var trackingStroke = false
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
        drawing.strokes.append(Stroke([point(event)], ink: ink))
        changed()
    }
    override func mouseDragged(with event: NSEvent) {
        guard enabled, trackingStroke, !drawing.strokes.isEmpty else { return }
        drawing.strokes[drawing.strokes.count - 1].points.append(point(event))
        changed()
    }
    override func mouseUp(with event: NSEvent) { trackingStroke = false }
    private func changed() { needsDisplay = true; onChange?(drawing) }
}
