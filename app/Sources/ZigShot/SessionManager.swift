import AppKit

/// Persists the last editor session (original image + annotations) for re-open.
/// Also manages capture history with thumbnails.
enum SessionManager {

    private static let appSupportDir: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ZigShot", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private static var sessionsDir: URL {
        let dir = appSupportDir.appendingPathComponent("sessions", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static var historyDir: URL {
        let dir = appSupportDir.appendingPathComponent("history", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Last Session

    struct SessionData: Codable {
        let annotations: [AnnotationDescriptor]
        let timestamp: Date
        let imageWidth: Int
        let imageHeight: Int
    }

    static func saveSession(originalImage: ZigShotImage, annotations: [AnnotationDescriptor]) {
        let imagePath = sessionsDir.appendingPathComponent("last-original.png")
        _ = originalImage.savePNG(to: imagePath, dpi: 144)

        let session = SessionData(
            annotations: annotations,
            timestamp: Date(),
            imageWidth: Int(originalImage.width),
            imageHeight: Int(originalImage.height)
        )
        let jsonPath = sessionsDir.appendingPathComponent("last.json")
        if let data = try? JSONEncoder().encode(session) {
            try? data.write(to: jsonPath)
        }
    }

    static func loadLastSession() -> (image: ZigShotImage, annotations: [AnnotationDescriptor])? {
        let imagePath = sessionsDir.appendingPathComponent("last-original.png")
        let jsonPath = sessionsDir.appendingPathComponent("last.json")

        guard FileManager.default.fileExists(atPath: imagePath.path),
              FileManager.default.fileExists(atPath: jsonPath.path),
              let jsonData = try? Data(contentsOf: jsonPath),
              let session = try? JSONDecoder().decode(SessionData.self, from: jsonData),
              let imageData = try? Data(contentsOf: imagePath),
              let nsImage = NSImage(data: imageData),
              let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let zigImage = ZigShotImage.fromCGImage(cgImage)
        else { return nil }

        return (zigImage, session.annotations)
    }

    static var hasLastSession: Bool {
        FileManager.default.fileExists(atPath: sessionsDir.appendingPathComponent("last.json").path)
    }

    // MARK: - Capture History

    struct HistoryEntry: Codable {
        let id: String
        let timestamp: Date
        let imageWidth: Int
        let imageHeight: Int
        let annotationCount: Int
    }

    static func addToHistory(originalImage: ZigShotImage, annotations: [AnnotationDescriptor]) {
        let id = UUID().uuidString
        let entryDir = historyDir.appendingPathComponent(id, isDirectory: true)
        try? FileManager.default.createDirectory(at: entryDir, withIntermediateDirectories: true)

        // Save original image
        let imagePath = entryDir.appendingPathComponent("original.png")
        _ = originalImage.savePNG(to: imagePath, dpi: 144)

        // Save thumbnail (max 300px wide)
        if let cgImage = originalImage.cgImage() {
            let maxWidth: CGFloat = 300
            let scale = min(maxWidth / CGFloat(originalImage.width), 1.0)
            let thumbW = Int(CGFloat(originalImage.width) * scale)
            let thumbH = Int(CGFloat(originalImage.height) * scale)
            let thumbRect = CGRect(x: 0, y: 0, width: thumbW, height: thumbH)
            if let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
               let ctx = CGContext(data: nil, width: thumbW, height: thumbH,
                                   bitsPerComponent: 8, bytesPerRow: thumbW * 4,
                                   space: colorSpace,
                                   bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) {
                ctx.draw(cgImage, in: thumbRect)
                if let thumbImage = ctx.makeImage() {
                    let thumbPath = entryDir.appendingPathComponent("thumb.png")
                    if let dest = CGImageDestinationCreateWithURL(thumbPath as CFURL, "public.png" as CFString, 1, nil) {
                        CGImageDestinationAddImage(dest, thumbImage, nil)
                        CGImageDestinationFinalize(dest)
                    }
                }
            }
        }

        // Save annotations
        if let data = try? JSONEncoder().encode(annotations) {
            try? data.write(to: entryDir.appendingPathComponent("annotations.json"))
        }

        // Save metadata
        let entry = HistoryEntry(
            id: id, timestamp: Date(),
            imageWidth: Int(originalImage.width),
            imageHeight: Int(originalImage.height),
            annotationCount: annotations.count
        )
        if let data = try? JSONEncoder().encode(entry) {
            try? data.write(to: entryDir.appendingPathComponent("meta.json"))
        }
    }

    static func recentCaptures(limit: Int = 10) -> [HistoryEntry] {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: historyDir, includingPropertiesForKeys: nil
        ) else { return [] }

        var entries: [HistoryEntry] = []
        for dir in contents where dir.hasDirectoryPath {
            let metaPath = dir.appendingPathComponent("meta.json")
            if let data = try? Data(contentsOf: metaPath),
               let entry = try? JSONDecoder().decode(HistoryEntry.self, from: data) {
                entries.append(entry)
            }
        }
        return entries.sorted { $0.timestamp > $1.timestamp }.prefix(limit).map { $0 }
    }

    static func loadHistoryEntry(id: String) -> (image: ZigShotImage, annotations: [AnnotationDescriptor])? {
        let entryDir = historyDir.appendingPathComponent(id)
        let imagePath = entryDir.appendingPathComponent("original.png")
        guard let imageData = try? Data(contentsOf: imagePath),
              let nsImage = NSImage(data: imageData),
              let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let zigImage = ZigShotImage.fromCGImage(cgImage)
        else { return nil }

        var annotations: [AnnotationDescriptor] = []
        let annotPath = entryDir.appendingPathComponent("annotations.json")
        if let data = try? Data(contentsOf: annotPath),
           let decoded = try? JSONDecoder().decode([AnnotationDescriptor].self, from: data) {
            annotations = decoded
        }
        return (zigImage, annotations)
    }

    static func thumbnailImage(for id: String) -> NSImage? {
        let thumbPath = historyDir.appendingPathComponent(id).appendingPathComponent("thumb.png")
        return NSImage(contentsOf: thumbPath)
    }

    static func pruneHistory(maxEntries: Int = 50) {
        let all = recentCaptures(limit: Int.max)
        guard all.count > maxEntries else { return }
        let toRemove = all.suffix(from: maxEntries)
        for entry in toRemove {
            let dir = historyDir.appendingPathComponent(entry.id)
            try? FileManager.default.removeItem(at: dir)
        }
    }
}
