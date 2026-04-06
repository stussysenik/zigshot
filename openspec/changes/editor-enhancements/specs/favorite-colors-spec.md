# Favorite Colors Specification

## Overview
This specification details the implementation of a favorite colors system for the ZigShot annotation editor. The feature will allow users to save and manage custom color presets for consistent annotation work, improving the user experience and workflow efficiency.

## Requirements

### Functional Requirements
1. **Color Preset Management**: Allow users to save custom colors as favorites
2. **Persistent Storage**: Save favorite colors between app sessions using UserDefaults
3. **Color Picker Integration**: Add favorite colors to the color picker in annotation tools
4. **Add/Remove Functionality**: Support adding new colors and removing existing favorites
5. **Color Limit**: Support up to 5 custom favorite colors (plus 5 built-in colors)
6. **Visual Feedback**: Provide clear visual indication of favorite colors
7. **Right-click Menu**: Allow removing custom colors via right-click context menu
8. **Color History**: Track recently used colors for quick access

### Non-Functional Requirements
1. **Performance**: Color management should be responsive with no noticeable lag
2. **Memory Usage**: Efficient storage and retrieval of color data
3. **Consistency**: Maintain consistent color application across all tools
4. **Accessibility**: Support keyboard navigation and screen reader announcements
5. **Compatibility**: Work across different macOS versions
6. **User Experience**: Intuitive and easy-to-use color management

## Implementation Details

### Color Management System
```swift
class ColorManager {
    static let shared = ColorManager()
    
    private let userDefaults = UserDefaults.standard
    private let favoriteColorsKey = "zigshot.favoriteColors"
    private let recentColorsKey = "zigshot.recentColors"
    
    private(set) var favoriteColors: [NSColor] = []
    private(set) var recentColors: [NSColor] = []
    
    private let builtInColors: [NSColor] = [
        .red, .yellow, .blue, .green, .black
    ]
    
    private let maxFavoriteColors = 5
    private let maxRecentColors = 10
    
    init() {
        loadFavoriteColors()
        loadRecentColors()
    }
    
    func loadFavoriteColors() {
        if let hexColors = userDefaults.array(forKey: favoriteColorsKey) as? [String] {
            favoriteColors = hexColors.compactMap { NSColor.from(hex: $0) }
        }
    }
    
    func loadRecentColors() {
        if let hexColors = userDefaults.array(forKey: recentColorsKey) as? [String] {
            recentColors = hexColors.compactMap { NSColor.from(hex: $0) }
        }
    }
    
    func saveFavoriteColors() {
        let hexColors = favoriteColors.map { $0.hexString }
        userDefaults.set(hexColors, forKey: favoriteColorsKey)
    }
    
    func saveRecentColors() {
        let hexColors = recentColors.map { $0.hexString }
        userDefaults.set(hexColors, forKey: recentColorsKey)
    }
    
    func addFavoriteColor(_ color: NSColor) {
        // Remove if already exists
        favoriteColors.removeAll { $0.hexString == color.hexString }
        
        // Add to beginning of array
        favoriteColors.insert(color, at: 0)
        
        // Limit to max count
        if favoriteColors.count > maxFavoriteColors {
            favoriteColors.removeLast()
        }
        
        saveFavoriteColors()
    }
    
    func removeFavoriteColor(_ color: NSColor) {
        favoriteColors.removeAll { $0.hexString == color.hexString }
        saveFavoriteColors()
    }
    
    func addRecentColor(_ color: NSColor) {
        // Remove if already exists
        recentColors.removeAll { $0.hexString == color.hexString }
        
        // Add to beginning of array
        recentColors.insert(color, at: 0)
        
        // Limit to max count
        if recentColors.count > maxRecentColors {
            recentColors.removeLast()
        }
        
        saveRecentColors()
    }
    
    func getAllColors() -> [NSColor] {
        return builtInColors + favoriteColors
    }
    
    func getColor(at index: Int) -> NSColor? {
        let allColors = getAllColors()
        guard index < allColors.count else { return nil }
        return allColors[index]
    }
}
```

### Color Picker Integration
```swift
class ColorPickerView: NSView {
    private let colorManager = ColorManager.shared
    private var colorButtons: [NSButton] = []
    private var addButton: NSButton!
    
    func setupColorPicker() {
        // Clear existing buttons
        colorButtons.forEach { $0.removeFromSuperview() }
        colorButtons.removeAll()
        
        // Create color buttons for all colors
        let allColors = colorManager.getAllColors()
        for (index, color) in allColors.enumerated() {
            let button = createColorButton(color, index: index)
            colorButtons.append(button)
            addSubview(button)
        }
        
        // Add button for adding new colors
        addButton = createAddButton()
        addSubview(addButton)
        
        // Layout the buttons
        layoutColorButtons()
    }
    
    private func createColorButton(_ color: NSColor, index: Int) -> NSButton {
        let button = NSButton()
        button.wantsLayer = true
        button.layer?.backgroundColor = color.cgColor
        button.layer?.cornerRadius = 8
        button.tag = index
        
        // Add right-click menu for removing custom colors
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Remove Color", action: #selector(removeColor), keyEquivalent: ""))
        button.menu = menu
        
        // Add action for selecting color
        button.action = #selector(selectColor)
        button.target = self
        
        return button
    }
    
    private func createAddButton() -> NSButton {
        let button = NSButton()
        button.title = "+"
        button.bezelStyle = .smallSquare
        button.font = NSFont.systemFont(ofSize: 12)
        button.action = #selector(addNewColor)
        button.target = self
        return button
    }
    
    @objc private func selectColor(_ sender: NSButton) {
        let index = sender.tag
        let color = colorManager.getColor(at: index)
        if let color = color {
            didSelectColor(color)
        }
    }
    
    @objc private func removeColor(_ sender: NSMenuItem) {
        guard let button = sender.representedObject as? NSButton,
              let index = colorButtons.firstIndex(of: button) else { return }
        
        let color = colorManager.getColor(at: index)
        if let color = color, colorManager.favoriteColors.contains(where: { $0.hexString == color.hexString }) {
            colorManager.removeFavoriteColor(color)
            setupColorPicker() // Refresh the picker
        }
    }
    
    @objc private func addNewColor() {
        // Show color picker dialog
        let colorPanel = NSColorPanel.shared
        colorPanel.setAction(#selector(didSelectNewColor))
        colorPanel.setTarget(self)
        colorPanel.makeKeyAndOrderFront(nil)
    }
    
    @objc private func didSelectNewColor(_ sender: NSColorPanel) {
        let newColor = sender.color
        colorManager.addFavoriteColor(newColor)
        colorManager.addRecentColor(newColor)
        setupColorPicker() // Refresh the picker
    }
    
    private func didSelectColor(_ color: NSColor) {
        // Notify the parent view of color selection
        NotificationCenter.default.post(name: .colorSelected, object: color)
    }
    
    private func layoutColorButtons() {
        // Simple grid layout for color buttons
        let buttonSize: CGFloat = 32
        let spacing: CGFloat = 8
        let columns = 5
        
        var x: CGFloat = spacing
        var y: CGFloat = spacing
        
        for (index, button) in colorButtons.enumerated() {
            button.frame = CGRect(x: x, y: y, width: buttonSize, height: buttonSize)
            
            x += buttonSize + spacing
            if (index + 1) % columns == 0 {
                x = spacing
                y += buttonSize + spacing
            }
        }
        
        // Position add button
        addButton.frame = CGRect(x: spacing, y: y + spacing, width: buttonSize, height: buttonSize)
    }
}
```

### Toolbar Integration
```swift
class AnnotationToolbar: NSView {
    private var colorPicker: ColorPickerView!
    
    func setupColorControls() {
        colorPicker = ColorPickerView()
        colorPicker.didSelectColor = { [weak self] color in
            self?.editor.currentColor = color
            self?.updateColorUI()
        }
        
        addSubview(colorPicker)
        colorPicker.translatesAutoresizingMaskIntoConstraints = false
        
        // Add constraints
        NSLayoutConstraint.activate([
            colorPicker.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            colorPicker.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            colorPicker.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            colorPicker.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8)
        ])
        
        // Update initial state
        updateColorUI()
    }
    
    func updateColorUI() {
        let currentColor = editor.currentColor
        colorPicker.setupColorPicker() // Refresh to show current color selection
        
        // Update any other color-related UI elements
        for button in colorPicker.colorButtons {
            if let index = colorPicker.colorButtons.firstIndex(of: button),
               let color = colorPicker.colorManager.getColor(at: index),
               color.hexString == currentColor.hexString {
                button.layer?.borderWidth = 2
                button.layer?.borderColor = NSColor.systemBlue.cgColor
            } else {
                button.layer?.borderWidth = 0
            }
        }
    }
}
```

### Color Extensions
```swift
extension NSColor {
    var hexString: String {
        guard let rgbColor = usingColorSpace(.sRGB) else { return "#000000" }
        
        let red = Int(round(rgbColor.redComponent * 255))
        let green = Int(round(rgbColor.greenComponent * 255))
        let blue = Int(round(rgbColor.blueComponent * 255))
        
        return String(format: "#%02X%02X%02X", red, green, blue)
    }
    
    static func from(hex: String) -> NSColor? {
        var hex = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        
        if hex.hasPrefix("#") {
            hex.remove(at: hex.startIndex)
        }
        
        guard hex.count == 6 else { return nil }
        
        var rgbValue: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&rgbValue)
        
        return NSColor(
            red: CGFloat((rgbValue & 0xFF0000) >> 16) / 255.0,
            green: CGFloat((rgbValue & 0x00FF00) >> 8) / 255.0,
            blue: CGFloat(rgbValue & 0x0000FF) / 255.0,
            alpha: 1.0
        )
    }
}
```

## Testing Requirements

### Unit Tests
1. **Color Management**: Test adding, removing, and persisting favorite colors
2. **Color Loading**: Test loading colors from UserDefaults
3. **Color Limits**: Test that color limits are enforced correctly
4. **Color Conversion**: Test hex string conversion and parsing
5. **Recent Colors**: Test recent colors tracking and management
6. **Built-in Colors**: Test built-in color availability and ordering

### Integration Tests
1. **Color Picker Integration**: Test color picker functionality with toolbar
2. **Color Selection**: Verify color selection updates the current color
3. **Right-click Menu**: Test removing colors via context menu
4. **Add Button**: Test adding new colors via color picker
5. **UI Updates**: Verify UI updates when colors are added/removed
6. **Persistence**: Test that colors persist between app launches

### User Experience Tests
1. **Color Selection**: Test that users can easily select colors
2. **Add/Remove**: Verify add and remove functionality works as expected
3. **Visual Feedback**: Test visual indicators for selected colors
4. **Accessibility**: Test keyboard navigation and screen reader support
5. **Error Handling**: Test error conditions and user feedback

## Success Criteria

- Favorite colors system works with persistent storage
- Users can add and remove custom colors
- Color picker integrates seamlessly with annotation tools
- Visual feedback indicates selected colors
- Right-click menu works for removing custom colors
- Recent colors are tracked and displayed
- All edge cases handled properly
- Comprehensive test coverage
- No regression in existing functionality
- User experience is improved with color management capabilities