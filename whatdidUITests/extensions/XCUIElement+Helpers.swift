// whatdidUITests?

import XCTest

extension XCUIElement {
    
    func grabFocus() {
        if !hasFocus {
            click()
        }
    }
    
    var hasFocus: Bool {
        return (self.value(forKey: "hasKeyboardFocus") as? Bool) ?? false
    }
    
    var focusedChild: XCUIElement {
        get {
            let focusedElems = children(matching: .any).matching(NSPredicate(format: "hasKeyboardFocus = true")).allElementsBoundByIndex
            XCTAssertEqual(focusedElems.count, 1)
            return focusedElems[0]
        }
    }
    
    var focusedDescendant: XCUIElement {
        get {
            let focusedElems = descendants(matching: .any).matching(NSPredicate(format: "hasKeyboardFocus = true")).allElementsBoundByIndex
            XCTAssertEqual(focusedElems.count, 1)
            return focusedElems[0]
        }
    }
    
    var stringValue: String {
        return value as! String
    }
    
    var boolValue: Bool {
        return value as! Bool
    }
    
    func backtab() {
        typeKey(.tab, modifierFlags: .shift)
    }
    
    /// Basically a safer version of `isHittable` that also checks if the element exists at all.
    var isVisible: Bool {
        get {
            return exists && isHittable
        }
    }
    
    var humanReadableIdentifier: String {
        var result = elementType.description
        if !identifier.isEmpty {
            result += " \(identifier)"
        } else if !title.isEmpty {
            result += " \(title)"
        } else if !stringValue.isEmpty {
            result += " with stringValue=\"\(stringValue)\""
        }
        return result
    }
    
    func click(using method: ElementClickMethod) {
        switch method {
        case .builtin:
            click()
        case .frame(let xInlay, let yInlay):
            let myFrame = frame
            let point = CGPoint(
                x: myFrame.minX + (frame.width * xInlay),
                y: myFrame.minY + (frame.height * yInlay))
            
            XCTestCase.clickEvent(.leftMouseDown, at: point, with: [])
            XCTestCase.clickEvent(.leftMouseUp, at: point, with: [])
        }
    }
    
    func deleteText(andReplaceWith replacement: String? = nil) {
        let message = replacement == nil
            ? "Delete text in \(humanReadableIdentifier)"
            : "Replace text in \(humanReadableIdentifier)"
        XCTContext.runActivity(named: message) {context in
            if replacement != nil {
                context.add(XCTAttachment(string: replacement!))
            }
            grabFocus()
            typeKey("a", modifierFlags: .command)
            typeKey(.delete)
            if let replacementToType = replacement {
                typeText(replacementToType)
            }
        }
    }
    
    func typeKey(_ key: XCUIKeyboardKey) {
        typeKey(key, modifierFlags: [])
    }
    
    func assertVisible() {
        _ = frame // just trying to get it will fail if the element isn't visible
    }
    
    var simpleDescription: String {
        var result = "\(elementType.description) id=\"\(identifier)\""
        if !title.isEmpty {
            result += ", title=\"\(title)\""
        }
        if !label.isEmpty {
            result += ", label=\"\(title)\""
        }
        var firstProperty = true
        func add(_ text: String, if set: Bool = true) {
            if set {
                if firstProperty {
                    firstProperty = false
                } else {
                    result += ", "
                }
                result += "\(text)"
            }
        }
        result += " ["
        add("exists", if: exists)
        add("hittable", if: isHittable) // <-- causes infinite loop when looking up the ScrollView
        let children = self.children(matching: .any)
        add(children.count == 1 ? "1 child" : "\(children.count) children", if: children.count > 0)
        result += "]"
        if let theValue = value {
            result += " ==> \"\(theValue)\""
        }
        return result
    }
    
    func printAccessibilityTree() {
        func buildTree(_ curr: XCUIElement, to resultLines: inout [String], depth: Int = 0) {
            let indent = String(repeating: " ", count: depth * 4)
            if depth > 5 {
                resultLines.append("\(indent)...")
            } else {
                resultLines.append("\(indent)\(curr.simpleDescription)")
                curr.children(matching: .any).allElementsBoundByIndex.forEach { buildTree($0, to: &resultLines, depth: depth + 1) }
            }
        }
        let header = String(repeating: "=", count: 72)
        var lines = [String]()
        buildTree(self, to: &lines)
        print(header)
        lines.forEach { print($0) }
        print(header)
    }
}

enum ElementClickMethod {
    /// click using the built-in `XCUIElement.click()` method.
    case builtin
    /// Clicks by manually creating mousedown and mouseup events within the element's frame.
    ///
    /// Some elements don't handle the builtin approach well, so this method can be more consistent for those.
    ///
    /// I don't actually know why that is, so, insert-shrug-emoji-here.
    ///
    /// The events are at a point that's `xInlay`% into the frame by width, and `yInlay`% by height.
    /// For instance, to click right in the middle (the default), use `(0.5, 0.5)`. To click near the top-left
    /// of the element, you might do smoething like (0.1, 0.1).
    case frame(xInlay: CGFloat=0.5, yInlay: CGFloat=0.5)
}

extension XCUIElement.ElementType {
    var description: String {
        switch self {
        case .activityIndicator: return "activityIndicator"
        case .alert: return "alert"
        case .any: return "any"
        case .application: return "application"
        case .browser: return "browser"
        case .button: return "button"
        case .cell: return "cell"
        case .checkBox: return "checkBox"
        case .collectionView: return "collectionView"
        case .colorWell: return "colorWell"
        case .comboBox: return "comboBox"
        case .datePicker: return "datePicker"
        case .decrementArrow: return "decrementArrow"
        case .dialog: return "dialog"
        case .disclosureTriangle: return "disclosureTriangle"
        case .dockItem: return "dockItem"
        case .drawer: return "drawer"
        case .grid: return "grid"
        case .group: return "group"
        case .handle: return "handle"
        case .helpTag: return "helpTag"
        case .icon: return "icon"
        case .image: return "image"
        case .incrementArrow: return "incrementArrow"
        case .key: return "key"
        case .keyboard: return "keyboard"
        case .layoutArea: return "layoutArea"
        case .layoutItem: return "layoutItem"
        case .levelIndicator: return "levelIndicator"
        case .link: return "link"
        case .map: return "map"
        case .matte: return "matte"
        case .menu: return "menu"
        case .menuBar: return "menuBar"
        case .menuBarItem: return "menuBarItem"
        case .menuButton: return "menuButton"
        case .menuItem: return "menuItem"
        case .navigationBar: return "navigationBar"
        case .other: return "other"
        case .outline: return "outline"
        case .outlineRow: return "outlineRow"
        case .pageIndicator: return "pageIndicator"
        case .picker: return "picker"
        case .pickerWheel: return "pickerWheel"
        case .popUpButton: return "popUpButton"
        case .popover: return "popover"
        case .progressIndicator: return "progressIndicator"
        case .radioButton: return "radioButton"
        case .radioGroup: return "radioGroup"
        case .ratingIndicator: return "ratingIndicator"
        case .relevanceIndicator: return "relevanceIndicator"
        case .ruler: return "ruler"
        case .rulerMarker: return "rulerMarker"
        case .scrollBar: return "scrollBar"
        case .scrollView: return "scrollView"
        case .searchField: return "searchField"
        case .secureTextField: return "secureTextField"
        case .segmentedControl: return "segmentedControl"
        case .sheet: return "sheet"
        case .slider: return "slider"
        case .splitGroup: return "splitGroup"
        case .splitter: return "splitter"
        case .staticText: return "staticText"
        case .statusBar: return "statusBar"
        case .statusItem: return "statusItem"
        case .stepper: return "stepper"
        case .`switch`: return "`switch`"
        case .tab: return "tab"
        case .tabBar: return "tabBar"
        case .tabGroup: return "tabGroup"
        case .table: return "table"
        case .tableColumn: return "tableColumn"
        case .tableRow: return "tableRow"
        case .textField: return "textField"
        case .textView: return "textView"
        case .timeline: return "timeline"
        case .toggle: return "toggle"
        case .toolbar: return "toolbar"
        case .toolbarButton: return "toolbarButton"
        case .valueIndicator: return "valueIndicator"
        case .webView: return "webView"
        case .window: return "window"
        case .touchBar: return "touchBar"

        @unknown default:
            return "(unknown type)"
        }
    }
}
