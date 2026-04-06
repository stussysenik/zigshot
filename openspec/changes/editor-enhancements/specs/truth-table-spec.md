# Truth Table Specification

## Overview
This specification details the implementation of truth table generation and visualization for the ZigShot annotation editor. The feature will allow users to create and export truth tables for logical operations, providing a valuable tool for digital logic design and educational purposes.

## Requirements

### Functional Requirements
1. **Truth Table Generation**: Generate truth tables for logical operations
2. **Logical Operations**: Support basic operations (AND, OR, NOT, XOR, NAND, NOR)
3. **Variable Count**: Support 2-4 input variables
4. **Table Visualization**: Display truth tables in a clear, readable format
5. **Export Functionality**: Export tables as text, CSV, image, or PDF
6. **Customization**: Allow customization of table appearance
7. **Input Validation**: Validate logical expressions and handle errors
8. **Interactive Interface**: Provide user-friendly interface for table creation

### Non-Functional Requirements
1. **Performance**: Table generation should be instantaneous for 2-4 variables
2. **Accuracy**: Ensure correct truth table calculations
3. **Memory Usage**: Efficient memory usage for table generation
4. **Compatibility**: Work across different macOS versions
5. **Accessibility**: Support keyboard navigation and screen reader announcements
6. **Export Quality**: High-quality exports in all formats

## Implementation Details

### Truth Table Generator
```swift
class TruthTableGenerator {
    enum LogicalOperation {
        case and
        case or
        case not
        case xor
        case nand
        case nor
        
        var symbol: String {
            switch self {
            case .and: return "∧"
            case .or: return "∨"
            case .not: return "¬"
            case .xor: return "⊕"
            case .nand: return "↑"
            case .nor: return "↓"
            }
        }
    }
    
    struct TruthTable {
        let variables: [String]
        let operations: [LogicalOperation]
        let results: [[Bool]]
        let headers: [String]
    }
    
    func generateTable(variables: [String], operations: [LogicalOperation]) -> TruthTable {
        let variableCount = variables.count
        let rowCount = Int(pow(2, Double(variableCount)))
        
        // Generate all possible input combinations
        var inputs: [[Bool]] = []
        for i in 0..<rowCount {
            var row: [Bool] = []
            for j in 0..<variableCount {
                let bit = (i >> j) & 1
                row.append(bit == 1)
            }
            inputs.append(row)
        }
        
        // Calculate results for each operation
        var results: [[Bool]] = []
        for row in inputs {
            var rowResults: [Bool] = []
            
            for operation in operations {
                switch operation {
                case .and:
                    let result = row.reduce(true) { $0 && $1 }
                    rowResults.append(result)
                case .or:
                    let result = row.reduce(false) { $0 || $1 }
                    rowResults.append(result)
                case .not:
                    // NOT applies to the first variable only
                    let result = !row[0]
                    rowResults.append(result)
                case .xor:
                    let result = row.reduce(false) { $0 != $1 }
                    rowResults.append(result)
                case .nand:
                    let result = !(row.reduce(true) { $0 && $1 })
                    rowResults.append(result)
                case .nor:
                    let result = !(row.reduce(false) { $0 || $1 })
                    rowResults.append(result)
                }
            }
            
            results.append(rowResults)
        }
        
        // Create headers
        var headers: [String] = variables
        for operation in operations {
            headers.append("\(operation.symbol) Result")
        }
        
        return TruthTable(variables: variables, operations: operations, results: results, headers: headers)
    }
}
```

### Truth Table Tool Integration
```swift
class TruthTableTool: AnnotationTool {
    private var isConfiguring: Bool = false
    private var configuration: TruthTableConfiguration = TruthTableConfiguration()
    private var generatedTable: TruthTable?
    
    func beginConfiguration() {
        isConfiguring = true
        showConfigurationDialog()
    }
    
    func generateTable() {
        let generator = TruthTableGenerator()
        generatedTable = generator.generateTable(
            variables: configuration.variables,
            operations: configuration.operations
        )
        showTablePreview()
    }
    
    func exportTable(format: ExportFormat) {
        guard let table = generatedTable else { return }
        
        switch format {
        case .text:
            exportAsText(table)
        case .csv:
            exportAsCSV(table)
        case .image:
            exportAsImage(table)
        case .pdf:
            exportAsPDF(table)
        }
    }
    
    private func showConfigurationDialog() {
        let dialog = TruthTableConfigurationDialog { [weak self] config in
            self?.configuration = config
            self?.generateTable()
        }
        dialog.show()
    }
    
    private func showTablePreview() {
        guard let table = generatedTable else { return }
        
        let preview = TruthTablePreviewDialog(table: table) { [weak self] format in
            self?.exportTable(format: format)
        }
        preview.show()
    }
}
```

### Configuration Dialog
```swift
class TruthTableConfigurationDialog: NSViewController {
    private var variablesField: NSTextField!
    private var operationsField: NSTextField!
    private var generateButton: NSButton!
    
    init(completion: @escaping (TruthTableConfiguration) -> Void) {
        super.init(nibName: nil, bundle: nil)
        self.completion = completion
    }
    
    override func loadView() {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        
        // Variables input
        let variablesLabel = NSTextField(labelWithString: "Variables (comma-separated):")
        variablesField = NSTextField(string: "A, B")
        variablesField.placeholderString = "e.g., A, B, C"
        
        // Operations input
        let operationsLabel = NSTextField(labelWithString: "Operations (comma-separated):")
        operationsField = NSTextField(string: "AND, OR")
        operationsField.placeholderString = "e.g., AND, OR, NOT, XOR"
        
        // Generate button
        generateButton = NSButton(title: "Generate Truth Table", target: self, action: #selector(generate))
        
        // Layout
        view.addSubview(variablesLabel)
        view.addSubview(variablesField)
        view.addSubview(operationsLabel)
        view.addSubview(operationsField)
        view.addSubview(generateButton)
        
        self.view = view
    }
    
    @objc func generate() {
        let variables = variablesField.stringValue.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        let operations = operationsField.stringValue.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        
        let config = TruthTableConfiguration(
            variables: variables,
            operations: operations.map { operationString in
                switch operationString.lowercased() {
                case "and": return .and
                case "or": return .or
                case "not": return .not
                case "xor": return .xor
                case "nand": return .nand
                case "nor": return .nor
                default: return .and // Default fallback
                }
            }
        )
        
        completion(config)
        dismiss(self)
    }
}
```

### Table Preview and Export
```swift
class TruthTablePreviewDialog: NSViewController {
    private let table: TruthTable
    private let exportHandler: (ExportFormat) -> Void
    
    init(table: TruthTable, exportHandler: @escaping (ExportFormat) -> Void) {
        self.table = table
        self.exportHandler = exportHandler
        super.init(nibName: nil, bundle: nil)
    }
    
    override func loadView() {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        
        // Table display
        let tableView = NSTableView()
        tableView.dataSource = self
        tableView.delegate = self
        
        // Export buttons
        let textButton = NSButton(title: "Export as Text", target: self, action: #selector(exportText))
        let csvButton = NSButton(title: "Export as CSV", target: self, action: #selector(exportCSV))
        let imageButton = NSButton(title: "Export as Image", target: self, action: #selector(exportImage))
        let pdfButton = NSButton(title: "Export as PDF", target: self, action: #selector(exportPDF))
        
        // Layout
        view.addSubview(tableView)
        view.addSubview(textButton)
        view.addSubview(csvButton)
        view.addSubview(imageButton)
        view.addSubview(pdfButton)
        
        self.view = view
    }
    
    @objc func exportText() {
        exportHandler(.text)
    }
    
    @objc func exportCSV() {
        exportHandler(.csv)
    }
    
    @objc func exportImage() {
        exportHandler(.image)
    }
    
    @objc func exportPDF() {
        exportHandler(.pdf)
    }
}

// Table view data source
extension TruthTablePreviewDialog: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        return table.results.count + 1 // +1 for header
    }
    
    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        if row == 0 {
            return table.headers[tableColumn?.identifier.rawValue.toInt() ?? 0]
        } else {
            let rowIndex = row - 1
            let columnIndex = tableColumn?.identifier.rawValue.toInt() ?? 0
            return table.results[rowIndex][columnIndex] ? "True" : "False"
        }
    }
}
```

### Export Formats
```swift
enum ExportFormat {
    case text
    case csv
    case image
    case pdf
}

func exportAsText(_ table: TruthTable) {
    var text = ""
    
    // Add headers
    text += table.headers.joined(separator: "\t") + "
"
    
    // Add separator
    text += Array(repeating: "-", count: table.headers.count).joined(separator: "\t") + "
"
    
    // Add rows
    for row in table.results {
        let rowText = row.map { $0 ? "True" : "False" }.joined(separator: "\t")
        text += rowText + "
"
    }
    
    // Save or show text
    showExportResult(text, format: .text)
}

func exportAsCSV(_ table: TruthTable) {
    var csv = ""
    
    // Add headers
    csv += table.headers.joined(separator: ",") + "
"
    
    // Add rows
    for row in table.results {
        let rowCSV = row.map { $0 ? "TRUE" : "FALSE" }.joined(separator: ",")
        csv += rowCSV + "
"
    }
    
    showExportResult(csv, format: .csv)
}

func exportAsImage(_ table: TruthTable) {
    // Create image from table
    let image = createImageFromTable(table)
    saveImage(image, format: .png)
}

func exportAsPDF(_ table: TruthTable) {
    // Create PDF from table
    let pdfData = createPDFFromTable(table)
    savePDF(pdfData)
}
```

## Testing Requirements

### Unit Tests
1. **Table Generation**: Test truth table generation with various inputs
2. **Logical Operations**: Verify correct calculation of all logical operations
3. **Variable Count**: Test table generation with 2-4 variables
4. **Error Handling**: Test invalid input handling
5. **Export Formats**: Verify all export formats work correctly
6. **Performance**: Test table generation performance with maximum variables

### Integration Tests
1. **Tool Integration**: Test truth table tool workflow from configuration to export
2. **Dialog Functionality**: Verify configuration and preview dialogs work correctly
3. **Export Workflow**: Test export functionality in all formats
4. **User Interface**: Test table display and interaction
5. **Edge Cases**: Test boundary conditions and error scenarios

### Performance Tests
1. **Large Tables**: Test performance with maximum variable count
2. **Complex Operations**: Test performance with multiple operations
3. **Memory Usage**: Monitor memory usage during table generation
4. **Export Performance**: Measure export time for different formats
5. **Concurrent Operations**: Test multiple table generations

## Success Criteria

- Truth table generation works correctly for all logical operations
- Support for 2-4 input variables
- Clear and readable table visualization
- All export formats (text, CSV, image, PDF) work correctly
- User-friendly configuration interface
- Accurate logical calculations
- Good performance with no noticeable lag
- Comprehensive error handling
- All edge cases handled properly
- Comprehensive test coverage
- No regression in existing functionality
- User experience is improved with truth table capabilities