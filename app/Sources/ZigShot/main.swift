import AppKit
import CZigShot

// Test ZigShotBridge
print("Testing ZigShotBridge...")

if let img = ZigShotImage(width: 200, height: 100) {
    // Draw a red arrow
    img.drawArrow(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 190, y: 90), color: .red)

    // Draw a blue rectangle outline
    img.drawRect(CGRect(x: 20, y: 20, width: 160, height: 60), color: .blue)

    // Measure with ruler
    let distance = img.drawRuler(from: CGPoint(x: 0, y: 50), to: CGPoint(x: 200, y: 50), color: .cyan)
    print("Ruler distance: \(distance) px")

    // Export as PNG
    let tmpURL = URL(fileURLWithPath: "/tmp/zigshot-test.png")
    if img.savePNG(to: tmpURL) {
        print("Saved test image to \(tmpURL.path)")
    }

    print("Bridge test passed: \(img.width)x\(img.height)")
} else {
    print("ERROR: ZigShotImage creation failed")
}
