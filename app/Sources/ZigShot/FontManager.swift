import AppKit
import CoreText

/// Manages user-imported custom fonts for annotation text.
/// Fonts are stored in ~/Library/Application Support/ZigShot/fonts/ and
/// registered at process scope via CTFontManager.
enum FontManager {

    private static let fontsDir: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ZigShot", isDirectory: true)
            .appendingPathComponent("fonts", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// Names of successfully registered custom fonts (PostScript names).
    private(set) static var customFontNames: [String] = []

    // MARK: - Load all on launch

    /// Scan the fonts directory and register all .ttf/.otf files.
    static func loadAllFonts() {
        customFontNames.removeAll()
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: fontsDir, includingPropertiesForKeys: nil
        ) else { return }

        for file in files {
            let ext = file.pathExtension.lowercased()
            guard ext == "ttf" || ext == "otf" else { continue }
            if let name = registerFont(at: file) {
                customFontNames.append(name)
            }
        }
    }

    // MARK: - Import

    /// Import a font file, copying it to the fonts directory and registering it.
    /// Returns the font's PostScript name on success, nil on failure.
    @discardableResult
    static func importFont(from sourceURL: URL) -> String? {
        let destURL = fontsDir.appendingPathComponent(sourceURL.lastPathComponent)

        // Copy if not already there
        if !FileManager.default.fileExists(atPath: destURL.path) {
            do {
                try FileManager.default.copyItem(at: sourceURL, to: destURL)
            } catch {
                print("[ZigShot] Failed to copy font: \(error)")
                return nil
            }
        }

        guard let name = registerFont(at: destURL) else {
            // Clean up failed import
            try? FileManager.default.removeItem(at: destURL)
            return nil
        }
        if !customFontNames.contains(name) {
            customFontNames.append(name)
        }
        return name
    }

    // MARK: - Remove

    /// Remove an imported font by PostScript name.
    static func removeFont(name: String) {
        customFontNames.removeAll { $0 == name }

        // Find and remove the file
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: fontsDir, includingPropertiesForKeys: nil
        ) else { return }

        for file in files {
            if let descriptors = CTFontManagerCreateFontDescriptorsFromURL(file as CFURL) as? [CTFontDescriptor] {
                for desc in descriptors {
                    if let psName = CTFontDescriptorCopyAttribute(desc, kCTFontNameAttribute) as? String,
                       psName == name {
                        var error: Unmanaged<CFError>?
                        CTFontManagerUnregisterFontsForURL(file as CFURL, .process, &error)
                        try? FileManager.default.removeItem(at: file)
                        return
                    }
                }
            }
        }
    }

    // MARK: - Available fonts for picker

    /// All font names available for the picker: custom fonts + common system fonts.
    static func availableFontNames() -> (custom: [String], system: [String]) {
        let systemFonts = [
            "SF Pro", "Helvetica Neue", "Menlo", "Monaco", "Courier New",
            "Georgia", "Times New Roman", "Arial", "Verdana", "Futura",
        ].filter { NSFont(name: $0, size: 12) != nil }
        return (customFontNames, systemFonts)
    }

    // MARK: - Private

    private static func registerFont(at url: URL) -> String? {
        var error: Unmanaged<CFError>?
        if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
            // Already registered is OK — continue to get the name
            let isAlreadyRegistered: Bool
            if let cfError = error?.takeRetainedValue() {
                isAlreadyRegistered = CFErrorGetCode(cfError) == CTFontManagerError.alreadyRegistered.rawValue
            } else {
                isAlreadyRegistered = false
            }
            if !isAlreadyRegistered {
                print("[ZigShot] Failed to register font \(url.lastPathComponent)")
                return nil
            }
        }

        // Get PostScript name
        guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
              let desc = descriptors.first,
              let psName = CTFontDescriptorCopyAttribute(desc, kCTFontNameAttribute) as? String
        else { return nil }

        return psName
    }
}
