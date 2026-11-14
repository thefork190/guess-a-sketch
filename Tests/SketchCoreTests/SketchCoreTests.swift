import CoreGraphics
import Testing
@testable import SketchCore

@Test func matchingIsConservative() {
    let prompt = DrawPrompt("bicycle", aliases: ["bike"])
    #expect(prompt.matches("A bike!"))
    #expect(prompt.matches("BICYCLE"))
    #expect(!prompt.matches("motorbike"))
    #expect(!prompt.matches("bike or cat"))
    #expect(!prompt.matches(""))
}

@Test func undoAndClear() {
    var drawing = Drawing()
    drawing.undo()
    drawing.strokes = [[CGPoint(x: 0.2, y: 0.2)], [CGPoint(x: 0.8, y: 0.8)]]
    drawing.undo()
    #expect(drawing.strokes.count == 1)
    drawing.clear()
    #expect(drawing.strokes.isEmpty)
}

@Test func bitmapContainsOnlyDrawingWithCorrectOrientation() throws {
    var drawing = Drawing()
    drawing.strokes = [[CGPoint(x: 0.25, y: 0.25)]]
    let image = try #require(drawing.bitmap())
    #expect(image.width == 600 && image.height == 600)
    let data = try #require(image.dataProvider?.data)
    let bytes = try #require(CFDataGetBytePtr(data))
    // Top-left mark is present, corresponding bottom-left pixel remains white.
    #expect(bytes[150 * image.bytesPerRow + 150 * 4] < 100)
    #expect(bytes[450 * image.bytesPerRow + 150 * 4] == 255)
    #expect(bytes[0] == 255 && bytes[3] == 255)
}
