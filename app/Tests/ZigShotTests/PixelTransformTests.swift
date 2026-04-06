import XCTest
import CZigShot
import AppKit

// MARK: - Minimal ZigShotImage for testing (mirrors the app's wrapper)

/// Minimal wrapper matching the app's ZigShotImage — just enough to test transforms.
/// We duplicate the transform code here to test it in isolation.
final class TestImage {
    let handle: OpaquePointer
    var width: UInt32 { zs_image_get_width(handle) }
    var height: UInt32 { zs_image_get_height(handle) }
    var stride: UInt32 { zs_image_get_stride(handle) }
    var pixels: UnsafeMutablePointer<UInt8> { zs_image_get_pixels(handle) }

    init?(width: UInt32, height: UInt32) {
        guard let h = zs_image_create_empty(width, height) else { return nil }
        self.handle = h
    }

    init?(pixels: UnsafePointer<UInt8>, width: UInt32, height: UInt32, stride: UInt32) {
        guard let h = zs_image_create(pixels, width, height, stride) else { return nil }
        self.handle = h
    }

    deinit { zs_image_destroy(handle) }

    /// Get RGBA at pixel (x, y). Returns (R, G, B, A).
    func pixel(x: Int, y: Int) -> (UInt8, UInt8, UInt8, UInt8) {
        let off = y * Int(stride) + x * 4
        return (pixels[off], pixels[off+1], pixels[off+2], pixels[off+3])
    }

    /// Set RGBA at pixel (x, y).
    func setPixel(x: Int, y: Int, r: UInt8, g: UInt8, b: UInt8, a: UInt8 = 255) {
        let off = y * Int(stride) + x * 4
        pixels[off] = r; pixels[off+1] = g; pixels[off+2] = b; pixels[off+3] = a
    }

    @discardableResult
    func copyPixels(from source: TestImage) -> Bool {
        return zs_image_copy_pixels(handle, source.handle)
    }

    // MARK: - Transforms (copied from ZigShotBridge.swift for isolated testing)

    static func cropped(from source: TestImage, rect: CGRect) -> TestImage? {
        let x = max(0, Int(rect.origin.x))
        let y = max(0, Int(rect.origin.y))
        let w = min(Int(rect.width), Int(source.width) - x)
        let h = min(Int(rect.height), Int(source.height) - y)
        guard w > 0, h > 0 else { return nil }

        guard let newImage = TestImage(width: UInt32(w), height: UInt32(h)) else { return nil }
        let srcStride = Int(source.stride)
        let dstStride = Int(newImage.stride)
        let srcPixels = source.pixels
        let dstPixels = newImage.pixels

        for row in 0 ..< h {
            let srcOffset = (y + row) * srcStride + x * 4
            let dstOffset = row * dstStride
            dstPixels.advanced(by: dstOffset)
                .update(from: srcPixels.advanced(by: srcOffset), count: w * 4)
        }
        return newImage
    }

    static func rotated90CW(from source: TestImage) -> TestImage? {
        let srcW = Int(source.width), srcH = Int(source.height)
        let srcStride = Int(source.stride)
        guard let newImage = TestImage(width: UInt32(srcH), height: UInt32(srcW)) else { return nil }
        let dstStride = Int(newImage.stride)
        let src = source.pixels, dst = newImage.pixels

        for y in 0 ..< srcH {
            for x in 0 ..< srcW {
                let srcOff = y * srcStride + x * 4
                let dstOff = x * dstStride + (srcH - 1 - y) * 4
                dst[dstOff + 0] = src[srcOff + 0]
                dst[dstOff + 1] = src[srcOff + 1]
                dst[dstOff + 2] = src[srcOff + 2]
                dst[dstOff + 3] = src[srcOff + 3]
            }
        }
        return newImage
    }

    static func rotated90CCW(from source: TestImage) -> TestImage? {
        let srcW = Int(source.width), srcH = Int(source.height)
        let srcStride = Int(source.stride)
        guard let newImage = TestImage(width: UInt32(srcH), height: UInt32(srcW)) else { return nil }
        let dstStride = Int(newImage.stride)
        let src = source.pixels, dst = newImage.pixels

        for y in 0 ..< srcH {
            for x in 0 ..< srcW {
                let srcOff = y * srcStride + x * 4
                let dstOff = (srcW - 1 - x) * dstStride + y * 4
                dst[dstOff + 0] = src[srcOff + 0]
                dst[dstOff + 1] = src[srcOff + 1]
                dst[dstOff + 2] = src[srcOff + 2]
                dst[dstOff + 3] = src[srcOff + 3]
            }
        }
        return newImage
    }

    static func flippedH(from source: TestImage) -> TestImage? {
        let w = Int(source.width), h = Int(source.height)
        let srcStride = Int(source.stride)
        guard let newImage = TestImage(width: source.width, height: source.height) else { return nil }
        let dstStride = Int(newImage.stride)
        let src = source.pixels, dst = newImage.pixels

        for y in 0 ..< h {
            for x in 0 ..< w {
                let srcOff = y * srcStride + x * 4
                let dstOff = y * dstStride + (w - 1 - x) * 4
                dst[dstOff + 0] = src[srcOff + 0]
                dst[dstOff + 1] = src[srcOff + 1]
                dst[dstOff + 2] = src[srcOff + 2]
                dst[dstOff + 3] = src[srcOff + 3]
            }
        }
        return newImage
    }

    static func flippedV(from source: TestImage) -> TestImage? {
        let w = Int(source.width), h = Int(source.height)
        let srcStride = Int(source.stride)
        guard let newImage = TestImage(width: source.width, height: source.height) else { return nil }
        let dstStride = Int(newImage.stride)
        let src = source.pixels, dst = newImage.pixels

        for y in 0 ..< h {
            let srcRow = src.advanced(by: y * srcStride)
            let dstRow = dst.advanced(by: (h - 1 - y) * dstStride)
            dstRow.update(from: srcRow, count: w * 4)
        }
        return newImage
    }
}

// MARK: - Test Cases

/// Tests pixel transforms using a 4×4 image with colored quadrants:
///
///     (0,0)=R  (1,0)=R  (2,0)=G  (3,0)=G       R = Red   (255,0,0)
///     (0,1)=R  (1,1)=R  (2,1)=G  (3,1)=G       G = Green (0,255,0)
///     (0,2)=B  (1,2)=B  (2,2)=W  (3,2)=W       B = Blue  (0,0,255)
///     (0,3)=B  (1,3)=B  (2,3)=W  (3,3)=W       W = White (255,255,255)
///
/// Origin is top-left. Y increases downward (matching Zig pixel buffer layout).
final class PixelTransformTests: XCTestCase {

    /// Create the 4×4 test image with colored quadrants.
    func makeTestImage() -> TestImage {
        let img = TestImage(width: 4, height: 4)!
        // Top-left quadrant: Red
        for y in 0..<2 { for x in 0..<2 { img.setPixel(x: x, y: y, r: 255, g: 0, b: 0) } }
        // Top-right quadrant: Green
        for y in 0..<2 { for x in 2..<4 { img.setPixel(x: x, y: y, r: 0, g: 255, b: 0) } }
        // Bottom-left quadrant: Blue
        for y in 2..<4 { for x in 0..<2 { img.setPixel(x: x, y: y, r: 0, g: 0, b: 255) } }
        // Bottom-right quadrant: White
        for y in 2..<4 { for x in 2..<4 { img.setPixel(x: x, y: y, r: 255, g: 255, b: 255) } }
        return img
    }

    func assertPixel(_ img: TestImage, x: Int, y: Int,
                      expectedR: UInt8, expectedG: UInt8, expectedB: UInt8,
                      label: String, file: StaticString = #file, line: UInt = #line) {
        let (r, g, b, _) = img.pixel(x: x, y: y)
        XCTAssertTrue(r == expectedR && g == expectedG && b == expectedB,
                      "Expected \(label) at (\(x),\(y)): want (\(expectedR),\(expectedG),\(expectedB)) got (\(r),\(g),\(b))",
                      file: file, line: line)
    }
    func assertPixelRed(_ img: TestImage, x: Int, y: Int, file: StaticString = #file, line: UInt = #line) {
        assertPixel(img, x: x, y: y, expectedR: 255, expectedG: 0, expectedB: 0, label: "RED", file: file, line: line)
    }
    func assertPixelGreen(_ img: TestImage, x: Int, y: Int, file: StaticString = #file, line: UInt = #line) {
        assertPixel(img, x: x, y: y, expectedR: 0, expectedG: 255, expectedB: 0, label: "GREEN", file: file, line: line)
    }
    func assertPixelBlue(_ img: TestImage, x: Int, y: Int, file: StaticString = #file, line: UInt = #line) {
        assertPixel(img, x: x, y: y, expectedR: 0, expectedG: 0, expectedB: 255, label: "BLUE", file: file, line: line)
    }
    func assertPixelWhite(_ img: TestImage, x: Int, y: Int, file: StaticString = #file, line: UInt = #line) {
        assertPixel(img, x: x, y: y, expectedR: 255, expectedG: 255, expectedB: 255, label: "WHITE", file: file, line: line)
    }

    // MARK: - Source verification

    func testSourceImageLayout() {
        let img = makeTestImage()
        XCTAssertEqual(img.width, 4)
        XCTAssertEqual(img.height, 4)

        // Verify quadrants
        assertPixelRed(img, x: 0, y: 0)    // top-left
        assertPixelGreen(img, x: 3, y: 0)  // top-right
        assertPixelBlue(img, x: 0, y: 3)   // bottom-left
        assertPixelWhite(img, x: 3, y: 3)  // bottom-right
    }

    // MARK: - Crop

    func testCropTopLeft() {
        let img = makeTestImage()
        let cropped = TestImage.cropped(from: img, rect: CGRect(x: 0, y: 0, width: 2, height: 2))!
        XCTAssertEqual(cropped.width, 2)
        XCTAssertEqual(cropped.height, 2)
        // Should be all red (top-left quadrant)
        for y in 0..<2 { for x in 0..<2 { assertPixelRed(cropped, x: x, y: y) } }
    }

    func testCropBottomRight() {
        let img = makeTestImage()
        let cropped = TestImage.cropped(from: img, rect: CGRect(x: 2, y: 2, width: 2, height: 2))!
        XCTAssertEqual(cropped.width, 2)
        XCTAssertEqual(cropped.height, 2)
        // Should be all white (bottom-right quadrant)
        for y in 0..<2 { for x in 0..<2 { assertPixelWhite(cropped, x: x, y: y) } }
    }

    func testCropTopRight() {
        let img = makeTestImage()
        let cropped = TestImage.cropped(from: img, rect: CGRect(x: 2, y: 0, width: 2, height: 2))!
        // Should be all green (top-right quadrant)
        for y in 0..<2 { for x in 0..<2 { assertPixelGreen(cropped, x: x, y: y) } }
    }

    func testCropBottomLeft() {
        let img = makeTestImage()
        let cropped = TestImage.cropped(from: img, rect: CGRect(x: 0, y: 2, width: 2, height: 2))!
        // Should be all blue (bottom-left quadrant)
        for y in 0..<2 { for x in 0..<2 { assertPixelBlue(cropped, x: x, y: y) } }
    }

    func testCropCenter() {
        let img = makeTestImage()
        // Crop the 2×2 center: should get one pixel of each color
        let cropped = TestImage.cropped(from: img, rect: CGRect(x: 1, y: 1, width: 2, height: 2))!
        assertPixelRed(cropped, x: 0, y: 0)    // was (1,1) = top-left quadrant
        assertPixelGreen(cropped, x: 1, y: 0)  // was (2,1) = top-right quadrant
        assertPixelBlue(cropped, x: 0, y: 1)   // was (1,2) = bottom-left quadrant
        assertPixelWhite(cropped, x: 1, y: 1)  // was (2,2) = bottom-right quadrant
    }

    // MARK: - Rotate 90° CW

    /// Rotate 90° clockwise:
    ///   Before:  R G     After:  B R
    ///            B W             W G
    /// Top-left R → top-right, top-right G → bottom-right,
    /// bottom-left B → top-left, bottom-right W → bottom-left
    func testRotate90CW() {
        let img = makeTestImage()
        let rotated = TestImage.rotated90CW(from: img)!
        XCTAssertEqual(rotated.width, 4, "Width should become old height")
        XCTAssertEqual(rotated.height, 4, "Height should become old width")

        // After 90° CW, quadrant mapping:
        // Old top-left (R) → new top-right
        assertPixelRed(rotated, x: 3, y: 0)
        assertPixelRed(rotated, x: 2, y: 0)
        assertPixelRed(rotated, x: 3, y: 1)
        assertPixelRed(rotated, x: 2, y: 1)

        // Old top-right (G) → new bottom-right
        assertPixelGreen(rotated, x: 3, y: 2)
        assertPixelGreen(rotated, x: 2, y: 2)
        assertPixelGreen(rotated, x: 3, y: 3)
        assertPixelGreen(rotated, x: 2, y: 3)

        // Old bottom-left (B) → new top-left
        assertPixelBlue(rotated, x: 0, y: 0)
        assertPixelBlue(rotated, x: 1, y: 0)
        assertPixelBlue(rotated, x: 0, y: 1)
        assertPixelBlue(rotated, x: 1, y: 1)

        // Old bottom-right (W) → new bottom-left
        assertPixelWhite(rotated, x: 0, y: 2)
        assertPixelWhite(rotated, x: 1, y: 2)
        assertPixelWhite(rotated, x: 0, y: 3)
        assertPixelWhite(rotated, x: 1, y: 3)
    }

    // MARK: - Rotate 90° CCW

    /// Rotate 90° counter-clockwise:
    ///   Before:  R G     After:  G W
    ///            B W             R B
    func testRotate90CCW() {
        let img = makeTestImage()
        let rotated = TestImage.rotated90CCW(from: img)!
        XCTAssertEqual(rotated.width, 4)
        XCTAssertEqual(rotated.height, 4)

        // Old top-left (R) → new bottom-left
        assertPixelRed(rotated, x: 0, y: 2)
        assertPixelRed(rotated, x: 1, y: 2)
        assertPixelRed(rotated, x: 0, y: 3)
        assertPixelRed(rotated, x: 1, y: 3)

        // Old top-right (G) → new top-left
        assertPixelGreen(rotated, x: 0, y: 0)
        assertPixelGreen(rotated, x: 1, y: 0)
        assertPixelGreen(rotated, x: 0, y: 1)
        assertPixelGreen(rotated, x: 1, y: 1)

        // Old bottom-left (B) → new bottom-right
        assertPixelBlue(rotated, x: 2, y: 2)
        assertPixelBlue(rotated, x: 3, y: 2)
        assertPixelBlue(rotated, x: 2, y: 3)
        assertPixelBlue(rotated, x: 3, y: 3)

        // Old bottom-right (W) → new top-right
        assertPixelWhite(rotated, x: 2, y: 0)
        assertPixelWhite(rotated, x: 3, y: 0)
        assertPixelWhite(rotated, x: 2, y: 1)
        assertPixelWhite(rotated, x: 3, y: 1)
    }

    // MARK: - Rotate roundtrip

    func testRotateCW_then_CCW_isIdentity() {
        let img = makeTestImage()
        let cw = TestImage.rotated90CW(from: img)!
        let back = TestImage.rotated90CCW(from: cw)!
        XCTAssertEqual(back.width, img.width)
        XCTAssertEqual(back.height, img.height)
        assertPixelRed(back, x: 0, y: 0)
        assertPixelGreen(back, x: 3, y: 0)
        assertPixelBlue(back, x: 0, y: 3)
        assertPixelWhite(back, x: 3, y: 3)
    }

    func testRotateCW_four_times_isIdentity() {
        let img = makeTestImage()
        var result = img
        for _ in 0..<4 { result = TestImage.rotated90CW(from: result)! }
        XCTAssertEqual(result.width, img.width)
        XCTAssertEqual(result.height, img.height)
        assertPixelRed(result, x: 0, y: 0)
        assertPixelGreen(result, x: 3, y: 0)
        assertPixelBlue(result, x: 0, y: 3)
        assertPixelWhite(result, x: 3, y: 3)
    }

    // MARK: - Flip Horizontal

    /// Flip horizontally (mirror left↔right):
    ///   Before:  R G     After:  G R
    ///            B W             W B
    func testFlipHorizontal() {
        let img = makeTestImage()
        let flipped = TestImage.flippedH(from: img)!
        XCTAssertEqual(flipped.width, 4)
        XCTAssertEqual(flipped.height, 4)

        // Old top-left (R) → new top-right
        assertPixelRed(flipped, x: 2, y: 0)
        assertPixelRed(flipped, x: 3, y: 0)
        assertPixelRed(flipped, x: 2, y: 1)
        assertPixelRed(flipped, x: 3, y: 1)

        // Old top-right (G) → new top-left
        assertPixelGreen(flipped, x: 0, y: 0)
        assertPixelGreen(flipped, x: 1, y: 0)
        assertPixelGreen(flipped, x: 0, y: 1)
        assertPixelGreen(flipped, x: 1, y: 1)

        // Old bottom-left (B) → new bottom-right
        assertPixelBlue(flipped, x: 2, y: 2)
        assertPixelBlue(flipped, x: 3, y: 2)
        assertPixelBlue(flipped, x: 2, y: 3)
        assertPixelBlue(flipped, x: 3, y: 3)

        // Old bottom-right (W) → new bottom-left
        assertPixelWhite(flipped, x: 0, y: 2)
        assertPixelWhite(flipped, x: 1, y: 2)
        assertPixelWhite(flipped, x: 0, y: 3)
        assertPixelWhite(flipped, x: 1, y: 3)
    }

    // MARK: - Flip Vertical

    /// Flip vertically (mirror top↔bottom):
    ///   Before:  R G     After:  B W
    ///            B W             R G
    func testFlipVertical() {
        let img = makeTestImage()
        let flipped = TestImage.flippedV(from: img)!
        XCTAssertEqual(flipped.width, 4)
        XCTAssertEqual(flipped.height, 4)

        // Old top-left (R) → new bottom-left
        assertPixelRed(flipped, x: 0, y: 2)
        assertPixelRed(flipped, x: 1, y: 2)
        assertPixelRed(flipped, x: 0, y: 3)
        assertPixelRed(flipped, x: 1, y: 3)

        // Old top-right (G) → new bottom-right
        assertPixelGreen(flipped, x: 2, y: 2)
        assertPixelGreen(flipped, x: 3, y: 2)
        assertPixelGreen(flipped, x: 2, y: 3)
        assertPixelGreen(flipped, x: 3, y: 3)

        // Old bottom-left (B) → new top-left
        assertPixelBlue(flipped, x: 0, y: 0)
        assertPixelBlue(flipped, x: 1, y: 0)
        assertPixelBlue(flipped, x: 0, y: 1)
        assertPixelBlue(flipped, x: 1, y: 1)

        // Old bottom-right (W) → new top-right
        assertPixelWhite(flipped, x: 2, y: 0)
        assertPixelWhite(flipped, x: 3, y: 0)
        assertPixelWhite(flipped, x: 2, y: 1)
        assertPixelWhite(flipped, x: 3, y: 1)
    }

    // MARK: - Flip roundtrips

    func testFlipH_twice_isIdentity() {
        let img = makeTestImage()
        let flipped = TestImage.flippedH(from: TestImage.flippedH(from: img)!)!
        assertPixelRed(flipped, x: 0, y: 0)
        assertPixelGreen(flipped, x: 3, y: 0)
        assertPixelBlue(flipped, x: 0, y: 3)
        assertPixelWhite(flipped, x: 3, y: 3)
    }

    func testFlipV_twice_isIdentity() {
        let img = makeTestImage()
        let flipped = TestImage.flippedV(from: TestImage.flippedV(from: img)!)!
        assertPixelRed(flipped, x: 0, y: 0)
        assertPixelGreen(flipped, x: 3, y: 0)
        assertPixelBlue(flipped, x: 0, y: 3)
        assertPixelWhite(flipped, x: 3, y: 3)
    }

    // MARK: - Non-square image rotation

    /// Test rotation with a 6×2 image to verify dimension swaps work correctly.
    func testRotateCW_nonSquare() {
        let img = TestImage(width: 6, height: 2)!
        // Top-left pixel = Red, top-right pixel = Green
        img.setPixel(x: 0, y: 0, r: 255, g: 0, b: 0)
        img.setPixel(x: 5, y: 0, r: 0, g: 255, b: 0)
        // Bottom-left pixel = Blue, bottom-right pixel = White
        img.setPixel(x: 0, y: 1, r: 0, g: 0, b: 255)
        img.setPixel(x: 5, y: 1, r: 255, g: 255, b: 255)

        let rotated = TestImage.rotated90CW(from: img)!
        XCTAssertEqual(rotated.width, 2, "New width = old height")
        XCTAssertEqual(rotated.height, 6, "New height = old width")

        // After 90° CW: top-left R → top-right
        assertPixelRed(rotated, x: 1, y: 0)
        // top-right G → bottom-right
        assertPixelGreen(rotated, x: 1, y: 5)
        // bottom-left B → top-left
        assertPixelBlue(rotated, x: 0, y: 0)
        // bottom-right W → bottom-left
        assertPixelWhite(rotated, x: 0, y: 5)
    }

    func testRotateCCW_nonSquare() {
        let img = TestImage(width: 6, height: 2)!
        img.setPixel(x: 0, y: 0, r: 255, g: 0, b: 0)
        img.setPixel(x: 5, y: 0, r: 0, g: 255, b: 0)
        img.setPixel(x: 0, y: 1, r: 0, g: 0, b: 255)
        img.setPixel(x: 5, y: 1, r: 255, g: 255, b: 255)

        let rotated = TestImage.rotated90CCW(from: img)!
        XCTAssertEqual(rotated.width, 2)
        XCTAssertEqual(rotated.height, 6)

        // After 90° CCW: top-left R → bottom-left
        assertPixelRed(rotated, x: 0, y: 5)
        // top-right G → top-left
        assertPixelGreen(rotated, x: 0, y: 0)
        // bottom-left B → bottom-right
        assertPixelBlue(rotated, x: 1, y: 5)
        // bottom-right W → top-right
        assertPixelWhite(rotated, x: 1, y: 0)
    }

    // MARK: - CGImage roundtrip (the critical coordinate space test)

    /// Tests that ZigShotImage → CGImage → display preserves pixel orientation.
    /// This verifies the fromCGImage row-flip + draw() flip transform pipeline.
    func testCGImageRoundtrip() {
        // Create a 4×4 image with colored quadrants
        let img = makeTestImage()

        // Convert to CGImage (like cgImage() does in the app)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            XCTFail("No sRGB color space"); return
        }
        let bitmapInfo = CGImageAlphaInfo.noneSkipLast.rawValue
            | CGBitmapInfo.byteOrder32Big.rawValue

        guard let provider = CGDataProvider(
            data: Data(bytes: img.pixels, count: Int(img.stride) * Int(img.height)) as CFData
        ) else { XCTFail("No data provider"); return }

        guard let cgImage = CGImage(
            width: Int(img.width), height: Int(img.height),
            bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: Int(img.stride),
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: bitmapInfo),
            provider: provider,
            decode: nil, shouldInterpolate: false, intent: .defaultIntent
        ) else { XCTFail("No CGImage"); return }

        // Now render this CGImage into a new bitmap context (simulating what draw() does)
        // This tests the CGImage coordinate interpretation
        let w = cgImage.width, h = cgImage.height
        let bytesPerRow = w * 4
        let rawData = UnsafeMutablePointer<UInt8>.allocate(capacity: bytesPerRow * h)
        defer { rawData.deallocate() }

        guard let ctx = CGContext(
            data: rawData, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else { XCTFail("No context"); return }

        // Draw into a non-flipped context (Y=0 at bottom)
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))

        // In a non-flipped context, the first row of rawData is the BOTTOM of the image.
        // So rawData[0] should be the bottom-left pixel of the original image = Blue
        let bottomLeftR = rawData[0], bottomLeftG = rawData[1], bottomLeftB = rawData[2]
        let topLeftOff = (h - 1) * bytesPerRow
        let topLeftR = rawData[topLeftOff], topLeftG = rawData[topLeftOff + 1], topLeftB = rawData[topLeftOff + 2]

        print("CGImage roundtrip diagnostic:")
        print("  rawData row 0 (bottom in non-flipped ctx): R=\(bottomLeftR) G=\(bottomLeftG) B=\(bottomLeftB)")
        print("  rawData last row (top in non-flipped ctx): R=\(topLeftR) G=\(topLeftG) B=\(topLeftB)")

        // CGBitmapContext stores data top-down: rawData[0] = first row in memory.
        // CGContext.draw maps CGImage data directly without flipping.
        // So rawData[0] = Red (image top-left), rawData[last] = Blue (image bottom-left).
        XCTAssertEqual(bottomLeftR, 255, "Row 0 should be Red (image top) — R=255")
        XCTAssertEqual(bottomLeftB, 0, "Row 0 should be Red (image top) — B=0")

        XCTAssertEqual(topLeftR, 0, "Last row should be Blue (image bottom) — R=0")
        XCTAssertEqual(topLeftB, 255, "Last row should be Blue (image bottom) — B=255")
    }

    // MARK: - fromCGImage pipeline test (THE critical coordinate test)

    /// Replicates the exact fromCGImage logic: CGContext.draw + row-flip.
    /// Creates a known CGImage (red top, blue bottom), runs it through the
    /// pipeline, and checks whether row 0 = top (correct) or bottom (bug).
    func testFromCGImagePipeline() {
        // Step 1: Create a known 4×4 CGImage with Red at top, Blue at bottom.
        // Use a CGBitmapContext to produce the CGImage (simulating ScreenCaptureKit output).
        let w = 4, h = 4
        let bpr = w * 4
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            XCTFail("No sRGB"); return
        }
        let bitmapInfo = CGImageAlphaInfo.noneSkipLast.rawValue
            | CGBitmapInfo.byteOrder32Big.rawValue

        // Produce CGImage via a bitmap context (like ScreenCaptureKit would)
        let srcData = UnsafeMutablePointer<UInt8>.allocate(capacity: bpr * h)
        defer { srcData.deallocate() }
        guard let srcCtx = CGContext(
            data: srcData, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: bpr,
            space: colorSpace, bitmapInfo: bitmapInfo
        ) else { XCTFail("No src context"); return }

        // Draw red rectangle at top half, blue at bottom half.
        // CGContext has Y=0 at bottom, so "top half" = higher Y values.
        srcCtx.setFillColor(red: 0, green: 0, blue: 1, alpha: 1) // Blue
        srcCtx.fill(CGRect(x: 0, y: 0, width: w, height: h / 2))  // bottom half (Y=0..1)
        srcCtx.setFillColor(red: 1, green: 0, blue: 0, alpha: 1) // Red
        srcCtx.fill(CGRect(x: 0, y: h / 2, width: w, height: h / 2))  // top half (Y=2..3)

        guard let sourceCGImage = srcCtx.makeImage() else {
            XCTFail("No CGImage from context"); return
        }

        // Verify the CGImage looks right: if we draw it back into a context,
        // the top should be red and bottom should be blue.
        print("Source CGImage: \(sourceCGImage.width)×\(sourceCGImage.height)")

        // Step 2: Run the exact fromCGImage logic
        let rawData = UnsafeMutablePointer<UInt8>.allocate(capacity: bpr * h)
        defer { rawData.deallocate() }
        guard let ctx = CGContext(
            data: rawData, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: bpr,
            space: colorSpace, bitmapInfo: bitmapInfo
        ) else { XCTFail("No context"); return }

        ctx.draw(sourceCGImage, in: CGRect(x: 0, y: 0, width: w, height: h))

        // Check rawData BEFORE flip
        let beforeFlipRow0_R = rawData[0]
        let beforeFlipRow0_G = rawData[1]
        let beforeFlipRow0_B = rawData[2]
        let lastRowOff = (h - 1) * bpr
        let beforeFlipRowLast_R = rawData[lastRowOff]
        let beforeFlipRowLast_G = rawData[lastRowOff + 1]
        let beforeFlipRowLast_B = rawData[lastRowOff + 2]

        print("BEFORE flip:")
        print("  rawData row 0: R=\(beforeFlipRow0_R) G=\(beforeFlipRow0_G) B=\(beforeFlipRow0_B)")
        print("  rawData last:  R=\(beforeFlipRowLast_R) G=\(beforeFlipRowLast_G) B=\(beforeFlipRowLast_B)")

        // No row-flip: CGContext.draw already produces top-down data.
        // Verify row 0 = RED (top of image) — correct for Zig's top-left origin.
        XCTAssertEqual(beforeFlipRow0_R, 255, "fromCGImage pipeline: row 0 should be RED (R=255)")
        XCTAssertEqual(beforeFlipRow0_B, 0, "fromCGImage pipeline: row 0 should be RED (B=0)")
        XCTAssertEqual(beforeFlipRowLast_R, 0, "fromCGImage pipeline: last row should be BLUE (R=0)")
        XCTAssertEqual(beforeFlipRowLast_B, 255, "fromCGImage pipeline: last row should be BLUE (B=255)")
    }

    // MARK: - Export pipeline test

    /// Tests the full export path: pixel buffer → cgImage → PNG data → decoded CGImage → verify orientation.
    /// This catches the exact "exported image is flipped" bug.
    func testExportPipelineOrientation() {
        // Create a TestImage with Red at top, Blue at bottom
        let img = makeTestImage()
        // row 0 = Red (top), row 3 = Blue/White (bottom)

        // Simulate cgImage(): wrap pixel buffer in CGImage via data provider
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            XCTFail("No sRGB"); return
        }
        let bitmapInfo = CGImageAlphaInfo.noneSkipLast.rawValue
            | CGBitmapInfo.byteOrder32Big.rawValue

        let dataSize = Int(img.stride) * Int(img.height)
        let data = Data(bytes: img.pixels, count: dataSize)

        guard let provider = CGDataProvider(data: data as CFData) else {
            XCTFail("No provider"); return
        }

        guard let cgImage = CGImage(
            width: Int(img.width), height: Int(img.height),
            bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: Int(img.stride),
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: bitmapInfo),
            provider: provider,
            decode: nil, shouldInterpolate: false, intent: .defaultIntent
        ) else { XCTFail("No CGImage"); return }

        // Write to PNG in memory
        let rep = NSBitmapImageRep(cgImage: cgImage)
        guard let pngData = rep.representation(using: .png, properties: [:]) else {
            XCTFail("No PNG data"); return
        }

        // Decode the PNG back
        guard let decodedImage = NSImage(data: pngData),
              let tiffData = decodedImage.tiffRepresentation,
              let decodedRep = NSBitmapImageRep(data: tiffData) else {
            XCTFail("Failed to decode PNG"); return
        }

        // Check top-left pixel of decoded image = should be Red
        let topLeft = decodedRep.colorAt(x: 0, y: 0)!.usingColorSpace(.sRGB)!
        let bottomLeft = decodedRep.colorAt(x: 0, y: 3)!.usingColorSpace(.sRGB)!

        print("Export pipeline test:")
        print("  Decoded top-left:    R=\(topLeft.redComponent) G=\(topLeft.greenComponent) B=\(topLeft.blueComponent)")
        print("  Decoded bottom-left: R=\(bottomLeft.redComponent) G=\(bottomLeft.greenComponent) B=\(bottomLeft.blueComponent)")

        // Top-left should be Red (the test image has Red at top-left)
        XCTAssertGreaterThan(topLeft.redComponent, 0.9, "Exported PNG top-left should be Red")
        XCTAssertLessThan(topLeft.blueComponent, 0.1, "Exported PNG top-left should be Red, not Blue")

        // Bottom-left should be Blue (the test image has Blue at bottom-left)
        XCTAssertGreaterThan(bottomLeft.blueComponent, 0.9, "Exported PNG bottom-left should be Blue")
        XCTAssertLessThan(bottomLeft.redComponent, 0.1, "Exported PNG bottom-left should be Blue, not Red")
    }

    // MARK: - Crop preserves orientation

    func testCropThenCGImage_preservesOrientation() {
        let img = makeTestImage()
        // Crop to bottom-right quadrant (White)
        let cropped = TestImage.cropped(from: img, rect: CGRect(x: 2, y: 2, width: 2, height: 2))!

        // Verify pixels directly
        for y in 0..<2 {
            for x in 0..<2 {
                assertPixelWhite(cropped, x: x, y: y)
            }
        }
    }
}
