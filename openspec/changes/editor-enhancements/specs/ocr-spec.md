# OCR Specification

## Overview
This specification details the implementation of Optical Character Recognition (OCR) functionality for the ZigShot annotation editor. The feature will allow users to extract text from images and add it as annotations, providing enhanced text processing capabilities.

## Requirements

### Functional Requirements
1. **Text Extraction**: Extract text from selected image regions using OCR
2. **Language Support**: Support multiple languages for text recognition
3. **Bounding Box Selection**: Allow users to draw bounding boxes around text regions
4. **Text Editing**: Enable editing of extracted text before adding as annotation
5. **Text Formatting**: Preserve text formatting and structure where possible
6. **Extraction Progress**: Show progress during OCR processing
7. **Error Handling**: Handle OCR failures and provide user feedback
8. **Result Preview**: Display extracted text with preview before adding as annotation

### Non-Functional Requirements
1. **Performance**: OCR processing should be reasonably fast (target: <5 seconds for typical images)
2. **Accuracy**: High text recognition accuracy (target: >90% for clear text)
3. **Memory Usage**: Efficient memory usage during OCR processing
4. **Compatibility**: Work across different image types and qualities
5. **Accessibility**: Support keyboard navigation and screen reader announcements
6. **Privacy**: Process images locally without sending data to external services

## Implementation Details

### OCR Framework Selection
```swift
enum OCRFramework {
    case vision      // Apple's Vision framework
    case tesseract   // Tesseract OCR engine
    case hybrid      // Vision for initial detection, Tesseract for accuracy
}

class OCRManager {
    private let framework: OCRFramework = .vision
    private let supportedLanguages: [String] = ["en", "es", "fr", "de", "zh", "ja", "ko"]
    
    func extractText(from image: CGImage, in region: CGRect, language: String) -> Result<String, OCRError> {
        switch framework {
        case .vision:
            return extractWithVision(from: image, in: region, language: language)
        case .tesseract:
            return extractWithTesseract(from: image, in: region, language: language)
        case .hybrid:
            return extractWithHybrid(from: image, in: region, language: language)
        }
    }
}
```

### Vision Framework Integration
```swift
func extractWithVision(from image: CGImage, in region: CGRect, language: String) -> Result<String, OCRError> {
    let requestHandler = VNImageRequestHandler(cgImage: image, options: [:])
    let request = VNRecognizeTextRequest { (request, error) in
        guard error == nil else {
            return .failure(.recognitionFailed(error!))
        }
        
        guard let observations = request.results as? [VNRecognizedTextObservation] else {
            return .failure(.noResults)
        }
        
        let recognizedText = observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
        return .success(recognizedText)
    }
    
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    request.recognitionLanguages = [language]
    
    do {
        try requestHandler.perform([request])
        return .success(request.results?.first?.topCandidates(1).first?.string ?? "")
    } catch {
        return .failure(.processingError(error))
    }
}
```

### Tesseract Integration (Fallback)
```swift
func extractWithTesseract(from image: CGImage, in region: CGRect, language: String) -> Result<String, OCRError> {
    // Convert CGImage to format suitable for Tesseract
    let tesseractImage = convertToTesseractFormat(image, region: region)
    
    let tesseract = G8Tesseract(language: language)
    tesseract?.image = tesseractImage
    tesseract?.recognitionTimeout = 30.0
    tesseract?.engineMode = .tesseractCubeCombined
    
    guard tesseract?.recognize() == true else {
        return .failure(.recognitionFailed(tesseract?.error as? Error ?? OCRError.unknown))
    }
    
    return .success(tesseract?.recognizedText ?? "")
}
```

### OCR Tool Integration
```swift
class OCRTool: AnnotationTool {
    private var isSelecting: Bool = false
    private var selectionRect: CGRect = .zero
    private var extractedText: String = ""
    
    func beginSelection(at point: CGPoint) {
        isSelecting = true
        selectionRect = CGRect(origin: point, size: .zero)
    }
    
    func updateSelection(to point: CGPoint) {
        if isSelecting {
            selectionRect = CGRect(origin: selectionRect.origin, 
                                size: CGSize(width: point.x - selectionRect.origin.x,
                                          height: point.y - selectionRect.origin.y))
        }
    }
    
    func endSelection() {
        isSelecting = false
        performOCR()
    }
    
    private func performOCR() {
        guard let image = editor.currentImage else { return }
        
        // Convert selection rect to image coordinates
        let imageRect = convertToImageCoordinates(selectionRect)
        
        // Show progress indicator
        showProgressIndicator()
        
        // Perform OCR in background
        DispatchQueue.global(qos: .userInitiated).async {
            let result = self.ocrManager.extractText(from: image, in: imageRect, language: "en")
            
            DispatchQueue.main.async {
                self.hideProgressIndicator()
                self.handleOCRResult(result)
            }
        }
    }
    
    private func handleOCRResult(_ result: Result<String, OCRError>) {
        switch result {
        case .success(let text):
            self.extractedText = text
            self.showTextPreview(text)
        case .failure(let error):
            self.showOCRError(error)
        }
    }
    
    private func showTextPreview(_ text: String) {
        // Show preview dialog with extracted text
        let preview = OCRPreviewDialog(text: text) { [weak self] in
            self?.addExtractedTextAsAnnotation(text)
        }
        preview.show()
    }
    
    private func addExtractedTextAsAnnotation(_ text: String) {
        let annotation = AnnotationDescriptor.text(
            at: selectionRect.center,
            text: text,
            fontName: "Helvetica",
            isBold: false,
            isItalic: false,
            alignment: .left,
            color: .black
        )
        editor.addAnnotation(annotation)
    }
}
```

### Language Support
```swift
struct Language {
    let code: String
    let name: String
    let tesseractModel: String?
    
    static let supportedLanguages: [Language] = [
        Language(code: "en", name: "English", tesseractModel: "eng"),
        Language(code: "es", name: "Spanish", tesseractModel: "spa"),
        Language(code: "fr", name: "French", tesseractModel: "fra"),
        Language(code: "de", name: "German", tesseractModel: "deu"),
        Language(code: "zh", name: "Chinese", tesseractModel: "chi_sim"),
        Language(code: "ja", name: "Japanese", tesseractModel: "jpn"),
        Language(code: "ko", name: "Korean", tesseractModel: "kor")
    ]
}
```

### Error Handling
```swift
enum OCRError: Error, LocalizedError {
    case recognitionFailed(Error)
    case noResults
    case processingError(Error)
    case languageNotSupported(String)
    case imageTooLarge
    case imageTooSmall
    case poorImageQuality
    case unknown
    
    var errorDescription: String? {
        switch self {
        case .recognitionFailed(let error):
            return "Text recognition failed: \(error.localizedDescription)"
        case .noResults:
            return "No text could be recognized in the selected area"
        case .processingError(let error):
            return "OCR processing error: \(error.localizedDescription)"
        case .languageNotSupported(let language):
            return "Language '\(language)' is not supported for OCR"
        case .imageTooLarge:
            return "Selected area is too large for OCR processing"
        case .imageTooSmall:
            return "Selected area is too small for OCR processing"
        case .poorImageQuality:
            return "Image quality is too poor for accurate text recognition"
        case .unknown:
            return "An unknown OCR error occurred"
        }
    }
}
```

### Toolbar Integration
```swift
class AnnotationToolbar: NSView {
    private var ocrButton: NSButton!
    
    func setupOCRControls() {
        ocrButton = createToolButton(.ocr, icon: "ocr-icon") {
            self.editor.selectTool(.ocr)
        }
        
        addSubview(ocrButton)
        
        // Update button state based on tool selection
        editor.toolSelectionHandler = { [weak self] tool in
            self?.ocrButton.isSelected = (tool == .ocr)
        }
    }
}
```

## Testing Requirements

### Unit Tests
1. **Text Extraction**: Test OCR text extraction with various image types
2. **Language Support**: Verify language detection and switching
3. **Bounding Box Selection**: Test selection rectangle handling
4. **Error Handling**: Test error conditions and recovery
5. **Performance**: Measure OCR processing time with different image sizes
6. **Result Accuracy**: Test text recognition accuracy with sample images

### Integration Tests
1. **Tool Integration**: Test OCR tool workflow from selection to annotation
2. **Progress Indicators**: Verify progress display during processing
3. **Text Preview**: Test text preview dialog functionality
4. **Annotation Addition**: Verify extracted text is added as annotation correctly
5. **Language Switching**: Test language selection and recognition
6. **Error Scenarios**: Test error handling and user feedback

### Performance Tests
1. **Large Images**: Test OCR performance with high-resolution images
2. **Complex Text**: Test recognition of complex layouts and fonts
3. **Memory Usage**: Monitor memory usage during OCR processing
4. **Concurrent Processing**: Test multiple OCR operations
5. **Timeout Handling**: Verify timeout and cancellation functionality

## Success Criteria

- OCR functionality works with keyboard and toolbar controls
- Text extraction is accurate and reasonably fast
- Multiple languages are supported
- Users can select regions and preview extracted text
- Extracted text can be edited and added as annotations
- Progress indicators and error handling work correctly
- Performance is acceptable with no significant lag
- All edge cases and error conditions are handled
- Comprehensive test coverage
- No regression in existing functionality
- User experience is improved with OCR capabilities