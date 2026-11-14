import CoreGraphics
import Foundation

public struct Drawing {
    public var strokes: [[CGPoint]] = []
    public init() {}
    public mutating func undo() { if !strokes.isEmpty { strokes.removeLast() } }
    public mutating func clear() { strokes.removeAll() }

    // Normalized coordinates keep display and bitmap identical across view sizes.
    public func render(in context: CGContext, size: CGSize) {
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(origin: .zero, size: size))
        context.setStrokeColor(CGColor(gray: 0.08, alpha: 1))
        context.setFillColor(CGColor(gray: 0.08, alpha: 1))
        let width = size.width / 150
        context.setLineWidth(width)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        for stroke in strokes {
            guard let first = stroke.first else { continue }
            let point = CGPoint(x: first.x * size.width, y: first.y * size.height)
            if stroke.count == 1 {
                context.fillEllipse(in: CGRect(x: point.x - width/2, y: point.y - width/2, width: width, height: width))
            } else {
                context.beginPath()
                context.move(to: point)
                for p in stroke.dropFirst() { context.addLine(to: CGPoint(x: p.x * size.width, y: p.y * size.height)) }
                context.strokePath()
            }
        }
    }

    public func bitmap() -> CGImage? {
        guard let context = CGContext(data: nil, width: 600, height: 600, bitsPerComponent: 8,
                                      bytesPerRow: 2400, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.translateBy(x: 0, y: 600)
        context.scaleBy(x: 1, y: -1)
        render(in: context, size: CGSize(width: 600, height: 600))
        return context.makeImage()
    }
}

public struct DrawPrompt: Equatable, Sendable {
    public let name: String
    public let aliases: [String]
    public init(_ name: String, aliases: [String] = []) { self.name = name; self.aliases = aliases }
    public func matches(_ guess: String) -> Bool {
        let value = Self.normalize(guess)
        return ([name] + aliases).contains { Self.normalize($0) == value }
    }
    private static func normalize(_ text: String) -> String {
        var words = text.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        if let first = words.first, ["a", "an", "the"].contains(first) { words.removeFirst() }
        return words.joined(separator: " ")
    }
    public static let all: [DrawPrompt] = [
        .init("cat", aliases: ["kitten"]), .init("bicycle", aliases: ["bike"]),
        .init("umbrella"), .init("pizza", aliases: ["pizza slice", "slice of pizza"]),
        .init("tree"), .init("sailboat", aliases: ["sail boat"]), .init("sun"),
        .init("house", aliases: ["home"]), .init("butterfly"), .init("guitar"),
        .init("rocket", aliases: ["rocket ship"]), .init("coffee cup", aliases: ["mug", "cup"])
    ]
}
