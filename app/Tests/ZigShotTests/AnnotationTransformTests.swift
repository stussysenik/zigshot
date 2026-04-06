import XCTest
import AppKit

// Since ZigShot is an executable target, we cannot @testable import it.
// Instead, we duplicate the minimal AnnotationDescriptor enum and translated()
// logic here to verify the coordinate transform math in isolation.

// MARK: - Minimal AnnotationDescriptor (test-only copy)

private enum TestAnnotation: Equatable {
    case arrow(from: CGPoint, to: CGPoint)
    case line(from: CGPoint, to: CGPoint)
    case ruler(from: CGPoint, to: CGPoint)
    case rectangle(rect: CGRect)
    case blur(rect: CGRect)
    case highlight(rect: CGRect)
    case numbering(position: CGPoint, number: Int)
    case text(position: CGPoint, content: String, fontSize: CGFloat)

    /// Translate all coordinates by (dx, dy). Returns nil if outside clipRect.
    /// This mirrors AnnotationDescriptor.translated(by:dy:clippedTo:).
    func translated(by dx: CGFloat, dy: CGFloat, clippedTo clipRect: CGRect? = nil) -> TestAnnotation? {
        func offsetPoint(_ p: CGPoint) -> CGPoint {
            CGPoint(x: p.x + dx, y: p.y + dy)
        }

        func offsetRect(_ r: CGRect) -> CGRect {
            CGRect(x: r.origin.x + dx, y: r.origin.y + dy, width: r.width, height: r.height)
        }

        func pointInside(_ p: CGPoint) -> Bool {
            guard let clip = clipRect else { return true }
            return clip.contains(p)
        }

        func rectIntersects(_ r: CGRect) -> Bool {
            guard let clip = clipRect else { return true }
            return clip.intersects(r)
        }

        func lineIntersects(_ a: CGPoint, _ b: CGPoint) -> Bool {
            guard let clip = clipRect else { return true }
            let lineBounds = CGRect(
                x: min(a.x, b.x), y: min(a.y, b.y),
                width: abs(b.x - a.x), height: abs(b.y - a.y)
            )
            return clip.intersects(lineBounds)
        }

        switch self {
        case let .arrow(from, to):
            let newFrom = offsetPoint(from)
            let newTo = offsetPoint(to)
            guard lineIntersects(newFrom, newTo) else { return nil }
            return .arrow(from: newFrom, to: newTo)

        case let .line(from, to):
            let newFrom = offsetPoint(from)
            let newTo = offsetPoint(to)
            guard lineIntersects(newFrom, newTo) else { return nil }
            return .line(from: newFrom, to: newTo)

        case let .ruler(from, to):
            let newFrom = offsetPoint(from)
            let newTo = offsetPoint(to)
            guard lineIntersects(newFrom, newTo) else { return nil }
            return .ruler(from: newFrom, to: newTo)

        case let .rectangle(rect):
            let newRect = offsetRect(rect)
            guard rectIntersects(newRect) else { return nil }
            return .rectangle(rect: newRect)

        case let .blur(rect):
            let newRect = offsetRect(rect)
            guard rectIntersects(newRect) else { return nil }
            return .blur(rect: newRect)

        case let .highlight(rect):
            let newRect = offsetRect(rect)
            guard rectIntersects(newRect) else { return nil }
            return .highlight(rect: newRect)

        case let .numbering(position, number):
            let newPos = offsetPoint(position)
            guard pointInside(newPos) else { return nil }
            return .numbering(position: newPos, number: number)

        case let .text(position, content, fontSize):
            let newPos = offsetPoint(position)
            guard pointInside(newPos) else { return nil }
            return .text(position: newPos, content: content, fontSize: fontSize)
        }
    }
}

// MARK: - Tests

final class AnnotationTransformTests: XCTestCase {

    // MARK: - Basic point translation

    func testPointTranslation() {
        let original = CGPoint(x: 100, y: 200)
        let cropOrigin = CGPoint(x: 50, y: 80)
        let transformed = CGPoint(x: original.x - cropOrigin.x, y: original.y - cropOrigin.y)
        XCTAssertEqual(transformed.x, 50, accuracy: 0.001)
        XCTAssertEqual(transformed.y, 120, accuracy: 0.001)
    }

    // MARK: - Arrow translation

    func testArrowTranslation() {
        let arrow = TestAnnotation.arrow(from: CGPoint(x: 100, y: 150),
                                          to: CGPoint(x: 200, y: 250))
        // Simulate crop at (50, 50) with size 300x300
        let result = arrow.translated(by: -50, dy: -50,
                                       clippedTo: CGRect(x: 0, y: 0, width: 300, height: 300))
        XCTAssertNotNil(result)
        if case let .arrow(from, to) = result! {
            XCTAssertEqual(from.x, 50, accuracy: 0.001)
            XCTAssertEqual(from.y, 100, accuracy: 0.001)
            XCTAssertEqual(to.x, 150, accuracy: 0.001)
            XCTAssertEqual(to.y, 200, accuracy: 0.001)
        } else {
            XCTFail("Expected arrow annotation")
        }
    }

    func testArrowOutsideCropReturnsNil() {
        let arrow = TestAnnotation.arrow(from: CGPoint(x: 500, y: 500),
                                          to: CGPoint(x: 600, y: 600))
        // Crop at (0,0) size 200x200 — arrow is at 500,500 which after -0,-0 offset is still outside
        let result = arrow.translated(by: 0, dy: 0,
                                       clippedTo: CGRect(x: 0, y: 0, width: 200, height: 200))
        XCTAssertNil(result)
    }

    // MARK: - Rectangle translation

    func testRectangleTranslation() {
        let rect = TestAnnotation.rectangle(rect: CGRect(x: 100, y: 100, width: 50, height: 50))
        let result = rect.translated(by: -80, dy: -80,
                                      clippedTo: CGRect(x: 0, y: 0, width: 200, height: 200))
        XCTAssertNotNil(result)
        if case let .rectangle(r) = result! {
            XCTAssertEqual(r.origin.x, 20, accuracy: 0.001)
            XCTAssertEqual(r.origin.y, 20, accuracy: 0.001)
            XCTAssertEqual(r.width, 50, accuracy: 0.001)
            XCTAssertEqual(r.height, 50, accuracy: 0.001)
        } else {
            XCTFail("Expected rectangle annotation")
        }
    }

    func testRectOutsideCropReturnsNil() {
        let rect = TestAnnotation.rectangle(rect: CGRect(x: 500, y: 500, width: 100, height: 100))
        let cropBounds = CGRect(x: 0, y: 0, width: 200, height: 200)
        let result = rect.translated(by: 0, dy: 0, clippedTo: cropBounds)
        XCTAssertNil(result)
    }

    func testRectInsideCrop() {
        let rect = TestAnnotation.rectangle(rect: CGRect(x: 50, y: 50, width: 100, height: 100))
        let cropBounds = CGRect(x: 0, y: 0, width: 200, height: 200)
        let result = rect.translated(by: 0, dy: 0, clippedTo: cropBounds)
        XCTAssertNotNil(result)
    }

    func testRectPartiallyOverlappingCropSurvives() {
        // Rectangle straddles the crop boundary — should survive since it intersects
        let rect = TestAnnotation.rectangle(rect: CGRect(x: 150, y: 150, width: 100, height: 100))
        let cropBounds = CGRect(x: 0, y: 0, width: 200, height: 200)
        let result = rect.translated(by: 0, dy: 0, clippedTo: cropBounds)
        XCTAssertNotNil(result, "Rectangle partially inside crop should survive")
    }

    // MARK: - Blur translation

    func testBlurTranslation() {
        let blur = TestAnnotation.blur(rect: CGRect(x: 60, y: 40, width: 30, height: 20))
        let result = blur.translated(by: -10, dy: -10,
                                      clippedTo: CGRect(x: 0, y: 0, width: 100, height: 100))
        XCTAssertNotNil(result)
        if case let .blur(r) = result! {
            XCTAssertEqual(r.origin.x, 50, accuracy: 0.001)
            XCTAssertEqual(r.origin.y, 30, accuracy: 0.001)
        } else {
            XCTFail("Expected blur annotation")
        }
    }

    // MARK: - Highlight translation

    func testHighlightTranslation() {
        let hl = TestAnnotation.highlight(rect: CGRect(x: 100, y: 100, width: 200, height: 30))
        let result = hl.translated(by: -50, dy: -50,
                                    clippedTo: CGRect(x: 0, y: 0, width: 300, height: 300))
        XCTAssertNotNil(result)
        if case let .highlight(r) = result! {
            XCTAssertEqual(r.origin.x, 50, accuracy: 0.001)
            XCTAssertEqual(r.origin.y, 50, accuracy: 0.001)
            XCTAssertEqual(r.width, 200, accuracy: 0.001)
        } else {
            XCTFail("Expected highlight annotation")
        }
    }

    // MARK: - Numbering translation

    func testNumberingTranslation() {
        let num = TestAnnotation.numbering(position: CGPoint(x: 100, y: 100), number: 3)
        let result = num.translated(by: -30, dy: -30,
                                     clippedTo: CGRect(x: 0, y: 0, width: 200, height: 200))
        XCTAssertNotNil(result)
        if case let .numbering(pos, n) = result! {
            XCTAssertEqual(pos.x, 70, accuracy: 0.001)
            XCTAssertEqual(pos.y, 70, accuracy: 0.001)
            XCTAssertEqual(n, 3)
        } else {
            XCTFail("Expected numbering annotation")
        }
    }

    func testNumberingOutsideCropReturnsNil() {
        let num = TestAnnotation.numbering(position: CGPoint(x: 300, y: 300), number: 1)
        let result = num.translated(by: -50, dy: -50,
                                     clippedTo: CGRect(x: 0, y: 0, width: 100, height: 100))
        XCTAssertNil(result)
    }

    // MARK: - Text translation

    func testTextTranslation() {
        let text = TestAnnotation.text(position: CGPoint(x: 80, y: 90), content: "Hello", fontSize: 16)
        let result = text.translated(by: -20, dy: -20,
                                      clippedTo: CGRect(x: 0, y: 0, width: 200, height: 200))
        XCTAssertNotNil(result)
        if case let .text(pos, content, fontSize) = result! {
            XCTAssertEqual(pos.x, 60, accuracy: 0.001)
            XCTAssertEqual(pos.y, 70, accuracy: 0.001)
            XCTAssertEqual(content, "Hello")
            XCTAssertEqual(fontSize, 16, accuracy: 0.001)
        } else {
            XCTFail("Expected text annotation")
        }
    }

    func testTextOutsideCropReturnsNil() {
        let text = TestAnnotation.text(position: CGPoint(x: 400, y: 400), content: "Offscreen", fontSize: 12)
        let result = text.translated(by: 0, dy: 0,
                                      clippedTo: CGRect(x: 0, y: 0, width: 200, height: 200))
        XCTAssertNil(result)
    }

    // MARK: - Translation without clipping

    func testTranslationWithoutClipAlwaysSucceeds() {
        let arrow = TestAnnotation.arrow(from: CGPoint(x: 1000, y: 1000),
                                          to: CGPoint(x: 2000, y: 2000))
        let result = arrow.translated(by: -500, dy: -500, clippedTo: nil)
        XCTAssertNotNil(result, "Without clip rect, translation should always succeed")
        if case let .arrow(from, to) = result! {
            XCTAssertEqual(from.x, 500, accuracy: 0.001)
            XCTAssertEqual(to.x, 1500, accuracy: 0.001)
        } else {
            XCTFail("Expected arrow annotation")
        }
    }

    // MARK: - Simulated crop workflow

    func testCropWorkflowPreservesAnnotationsInside() {
        // Simulate: image is 400x400, annotations at various positions,
        // crop to (100, 100, 200, 200)
        let cropRect = CGRect(x: 100, y: 100, width: 200, height: 200)
        let dx = -cropRect.origin.x
        let dy = -cropRect.origin.y
        let newBounds = CGRect(x: 0, y: 0, width: cropRect.width, height: cropRect.height)

        let annotations: [TestAnnotation] = [
            .arrow(from: CGPoint(x: 150, y: 150), to: CGPoint(x: 250, y: 250)),  // Inside
            .rectangle(rect: CGRect(x: 120, y: 120, width: 60, height: 60)),      // Inside
            .numbering(position: CGPoint(x: 50, y: 50), number: 1),               // Outside
            .text(position: CGPoint(x: 200, y: 200), content: "Test", fontSize: 14), // Inside
            .blur(rect: CGRect(x: 350, y: 350, width: 40, height: 40)),           // Outside
        ]

        var surviving: [TestAnnotation] = []
        for ann in annotations {
            if let transformed = ann.translated(by: dx, dy: dy, clippedTo: newBounds) {
                surviving.append(transformed)
            }
        }

        // Should keep 3 (arrow, rectangle, text) and discard 2 (numbering at 50,50; blur at 350,350)
        XCTAssertEqual(surviving.count, 3)

        // Verify arrow was transformed correctly
        if case let .arrow(from, to) = surviving[0] {
            XCTAssertEqual(from.x, 50, accuracy: 0.001)  // 150 - 100
            XCTAssertEqual(from.y, 50, accuracy: 0.001)  // 150 - 100
            XCTAssertEqual(to.x, 150, accuracy: 0.001)   // 250 - 100
            XCTAssertEqual(to.y, 150, accuracy: 0.001)   // 250 - 100
        } else {
            XCTFail("First surviving should be arrow")
        }

        // Verify text was transformed correctly
        if case let .text(pos, content, _) = surviving[2] {
            XCTAssertEqual(pos.x, 100, accuracy: 0.001)  // 200 - 100
            XCTAssertEqual(pos.y, 100, accuracy: 0.001)  // 200 - 100
            XCTAssertEqual(content, "Test")
        } else {
            XCTFail("Third surviving should be text")
        }
    }

    // MARK: - Line tool

    func testLineTranslation() {
        let line = TestAnnotation.line(from: CGPoint(x: 50, y: 50), to: CGPoint(x: 150, y: 150))
        let result = line.translated(by: -25, dy: -25,
                                      clippedTo: CGRect(x: 0, y: 0, width: 200, height: 200))
        XCTAssertNotNil(result)
        if case let .line(from, to) = result! {
            XCTAssertEqual(from.x, 25, accuracy: 0.001)
            XCTAssertEqual(to.x, 125, accuracy: 0.001)
        } else {
            XCTFail("Expected line annotation")
        }
    }

    // MARK: - Ruler tool

    func testRulerTranslation() {
        let ruler = TestAnnotation.ruler(from: CGPoint(x: 60, y: 60), to: CGPoint(x: 160, y: 60))
        let result = ruler.translated(by: -30, dy: -30,
                                       clippedTo: CGRect(x: 0, y: 0, width: 200, height: 200))
        XCTAssertNotNil(result)
        if case let .ruler(from, to) = result! {
            XCTAssertEqual(from.x, 30, accuracy: 0.001)
            XCTAssertEqual(from.y, 30, accuracy: 0.001)
            XCTAssertEqual(to.x, 130, accuracy: 0.001)
        } else {
            XCTFail("Expected ruler annotation")
        }
    }
}
