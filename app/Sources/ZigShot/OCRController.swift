import AppKit
import Vision

/// Extracts text from images using Vision framework's VNRecognizeTextRequest.
/// Results are copied to the system clipboard.
enum OCRController {

    /// Extract all text from the given CGImage and copy to clipboard.
    /// Calls completion on the main thread with the extracted text (nil if none found).
    static func extractText(from cgImage: CGImage, completion: @escaping (String?) -> Void) {
        let request = VNRecognizeTextRequest { request, error in
            guard let observations = request.results as? [VNRecognizedTextObservation] else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            let text = observations
                .compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: "\n")
            DispatchQueue.main.async {
                completion(text.isEmpty ? nil : text)
            }
        }
        request.recognitionLevel = .accurate

        let handler = VNImageRequestHandler(cgImage: cgImage)
        DispatchQueue.global(qos: .userInitiated).async {
            try? handler.perform([request])
        }
    }

    /// Extract text and copy to clipboard, with a brief console log.
    static func extractAndCopy(from cgImage: CGImage) {
        extractText(from: cgImage) { text in
            guard let text = text else {
                print("[ZigShot] OCR: no text found")
                return
            }
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            print("[ZigShot] OCR: copied \(text.count) characters to clipboard")
        }
    }
}
