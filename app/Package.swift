// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ZigShot",
    platforms: [.macOS(.v14)],
    targets: [
        // C wrapper target: provides the zigshot.h header to Swift
        .target(
            name: "CZigShot",
            path: "Sources/CZigShot",
            publicHeadersPath: "include"
        ),
        // Swift app target
        .executableTarget(
            name: "ZigShot",
            dependencies: ["CZigShot"],
            linkerSettings: [
                .unsafeFlags(["-L/Users/s3nik/Desktop/zigshot/zig-out/lib"]),
                .linkedLibrary("zigshot"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("AppKit"),
                .linkedFramework("ImageIO"),
                .linkedFramework("QuartzCore"),
            ]
        ),
    ]
)
