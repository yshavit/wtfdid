// whatdid?

import Cocoa

class AutoCompletingField: NSTextField, NSTextViewDelegate {
    
    private static let PINNED_OPTIONS_COUNT = 3
    var previousAutocompleteHeadLength = 0
    var shouldAutocompleteOnTextChange = false
    
    private var pulldownButton: NSButton!
    private var popupManager: PopupManager!
    var optionsLookupOnFocus: (() -> [String])?
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }
    
    private func commonInit() {
        useAutoLayout()
        
        let textFieldCell = ShrunkenTextFieldCell(textCell: "")
        self.cell = textFieldCell
        self.isBordered = true
        self.backgroundColor = .white
        self.isBezeled = true
        self.bezelStyle = .squareBezel
        self.isEnabled = true
        self.isEditable = true
        self.isSelectable = true
        self.placeholderString = "placeholder"
        
        pulldownButton = NoKeyButton()
        pulldownButton.useAutoLayout()
        addSubview(pulldownButton)
        // button styling
        pulldownButton.imageScaling = .scaleProportionallyDown
        pulldownButton.bezelStyle = .smallSquare
        pulldownButton.state = .off
        pulldownButton.setButtonType(.momentaryPushIn)
        pulldownButton.imagePosition = .imageOnly
        pulldownButton.image = NSImage(named: NSImage.touchBarGoDownTemplateName)
        if let pulldownCell = pulldownButton.cell as? NSButtonCell {
            pulldownCell.isBordered = false
            pulldownCell.backgroundColor = .controlAccentColor
        }
        // button positioning
        pulldownButton.topAnchor.constraint(equalTo: topAnchor).isActive = true
        pulldownButton.bottomAnchor.constraint(equalTo: bottomAnchor).isActive = true
        pulldownButton.widthAnchor.constraint(equalTo: pulldownButton.heightAnchor, multiplier: 0.75).isActive = true
        pulldownButton.trailingAnchor.constraint(equalTo: trailingAnchor).isActive = true
        textFieldCell.widthAdjustment = { self.pulldownButton.frame.width }
        // button behavior
        pulldownButton.target = self
        pulldownButton.action = #selector(self.buttonClicked)
        
        let pulldownButtonTracker = NSTrackingArea(
            rect: frame,
            options: [.inVisibleRect, .mouseMoved, .activeAlways],
            owner: self)
        addTrackingArea(pulldownButtonTracker)
        
        popupManager = PopupManager(parent: self)
    }
    
    var options: [String] {
        get {
            return popupManager.options
        }
        set (values) {
            popupManager.options = values
        }
    }
    
    /// Set the cursor to the arrow (instead of NSTextField's default I-beam) when hovering over the button
    override func mouseMoved(with event: NSEvent) {
        if pulldownButton.frame.contains(convert(event.locationInWindow, from: nil)) {
            NSCursor.arrow.set()
        } else {
            super.cursorUpdate(with: event)
        }
    }
    
    override func becomeFirstResponder() -> Bool {
        let succeeded = super.becomeFirstResponder()
        if let optionsLookup = optionsLookupOnFocus {
            options = optionsLookup()
        }
        if succeeded {
            showOptions()
        }
        return succeeded
    }
    
    func textViewDidChangeSelection(_ notification: Notification) {
        let selectedRange = currentEditor()!.selectedRange
        let currentSelectionIsTail = selectedRange.location + selectedRange.length == stringValue.count
        if currentSelectionIsTail {
            let currentAutocompleteHeadLength = selectedRange.location
            shouldAutocompleteOnTextChange = currentAutocompleteHeadLength > previousAutocompleteHeadLength
            previousAutocompleteHeadLength = currentAutocompleteHeadLength
        } else {
            previousAutocompleteHeadLength = 0
            shouldAutocompleteOnTextChange = false
        }
    }
    
    override func textDidChange(_ notification: Notification) {
        super.textDidChange(notification)
        let maybeAutocomplete = popupManager.match(stringValue)
        // If the selection is at the tail of the string, fill in the autocomplete.
        if shouldAutocompleteOnTextChange, let autoComplete = maybeAutocomplete {
            let charsToAutocomplete = autoComplete.count - stringValue.count
            if charsToAutocomplete > 0 {
                let autocompleTail = String(autoComplete.dropFirst(stringValue.count))
                let stringCountBeforeAutocomplete = stringValue.count
                stringValue += autocompleTail
                currentEditor()!.selectedRange = NSRange(location: stringCountBeforeAutocomplete, length: charsToAutocomplete)
            }
        }
    }
    
    override func textDidEndEditing(_ notification: Notification) {
        super.textDidEndEditing(notification)
        popupManager.close()
    }
    
    @objc private func buttonClicked() {
        if popupManager.windowIsVisible {
            // Note: we shouldn't ever actually get here, but I'm putting it just in case.
            // If the popup is open, any click outside of it (including to this button) will close it.
            NSLog("Unexpectedly saw button press while options popup was open on \(idForLogging)")
            popupManager.close()
        } else {
            if !(window?.makeFirstResponder(self) ?? false) {
                NSLog("Couldn't make first responder: \(idForLogging)")
            }
            showOptions()
        }
    }
    
    private var idForLogging: String {
        return accessibilityLabel() ?? "unidentifed field at \(frame.debugDescription)"
    }
    
    private func showOptions() {
        let originWithinWindow = superview!.convert(frame.origin, to: nil)
        let originWithinScreen = window!.convertPoint(toScreen: originWithinWindow)
        popupManager.show(
            minWidth: frame.width,
            matching: stringValue,
            atTopLeft: originWithinScreen) // window!.convertPoint(toScreen: frame.origin))
    }
    
    private class PopupManager: NSObject, NSWindowDelegate {
        private var activeEventMonitors = [Any?]()
        private let optionsPopup: NSPanel
        private let parent: AutoCompletingField
        private var matchedSectionSeparators = [NSView]()
        private let mainStack: NSStackView
        private var setWidth: ((CGFloat) -> Void)!
        
        init(parent: AutoCompletingField) {
            self.parent = parent
            optionsPopup = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 200, height: 90),
                styleMask: [.fullSizeContentView],
                backing: .buffered,
                defer: false)
            optionsPopup.hasShadow = true
            mainStack = NSStackView()
            mainStack.orientation = .vertical
            
            super.init()
            optionsPopup.delegate = self
            mainStack.useAutoLayout()
            mainStack.edgeInsets.bottom = 4
            mainStack.orientation = .vertical
            mainStack.alignment = .leading
            mainStack.spacing = 0
            
            // Put the main stack inside a scroll
            let scroll = NSScrollView()
            scroll.useAutoLayout()
            scroll.contentView.anchorAllSides(to: scroll)
            scroll.drawsBackground = false
            scroll.hasVerticalScroller = true
            scroll.hasHorizontalScroller = true

            let flipped = FlippedView()
            flipped.useAutoLayout()
            flipped.addSubview(mainStack)
            mainStack.anchorAllSides(to: flipped)
            scroll.documentView = flipped

            // Try to have the scroll's content view be as big as the mainstack; but cap it at 150.
            // Also create a constraint for the width, which we'll set as we open the popup.
            scroll.contentView.heightAnchor.constraint(lessThanOrEqualTo: mainStack.heightAnchor).isActive = true
            scroll.heightAnchor.constraint(lessThanOrEqualToConstant: 150).isActive = true
            let widthConstraint = scroll.contentView.widthAnchor.constraint(equalToConstant: 100) // any ol' value will do
            widthConstraint.isActive = true
            setWidth = { widthConstraint.constant = $0 } // ha, a mutable constant!

            scroll.contentView.widthAnchor.constraint(lessThanOrEqualTo: mainStack.widthAnchor).isActive = true
            optionsPopup.contentView = scroll
            optionsPopup.level = .popUpMenu
        }
        
        var options: [String] {
            get {
                return optionFields.map { $0.stringValue }
            }
            set (values) {
                mainStack.views.forEach { $0.removeFromSuperview() }
                mainStack.subviews.forEach { $0.removeFromSuperview() }
                matchedSectionSeparators.removeAll()
                if values.isEmpty {
                    /*

                     .foregroundColor: NSColor.selectedTextColor,
                     .backgroundColor: NSColor.selectedTextBackgroundColor,
                     .underlineColor: NSColor.findHighlightColor,
                     .underlineStyle: NSUnderlineStyle.single.rawValue,
                     */
                    let labelString = NSAttributedString(string: "(no previous entries)", attributes: [
                        NSAttributedString.Key.foregroundColor: NSColor.systemGray,
                    ])
                    let noneLabel = NSTextField(labelWithAttributedString: labelString)
                    noneLabel.useAutoLayout()
                    noneLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
                    mainStack.addArrangedSubview(noneLabel)
                    noneLabel.widthAnchor.constraint(equalTo: mainStack.widthAnchor).isActive = true
                    return
                }
                for (i, optionText) in values.enumerated() {
                    if i == AutoCompletingField.PINNED_OPTIONS_COUNT {
                        let separator = NSBox()
                        mainStack.addArrangedSubview(separator)
                        separator.widthAnchor.constraint(equalTo: mainStack.widthAnchor).isActive = true
                        separator.boxType = .separator
                        matchedSectionSeparators.append(separator)
                        matchedSectionSeparators.append(addGroupingLabel(text: "matched", under: separator.topAnchor))
                    }
                    let option = Option()
                    option.stringValue = optionText
                    mainStack.addArrangedSubview(option)
                    option.widthAnchor.constraint(equalTo: mainStack.widthAnchor).isActive = true
                }
                if !values.isEmpty {
                    _ = addGroupingLabel(text: "recent", under: mainStack.topAnchor)
                }
            }
        }
        
        private var optionFields: [Option] {
            return mainStack.arrangedSubviews.compactMap { $0 as? Option }
        }
        
        var windowIsVisible: Bool {
            return optionsPopup.isVisible
        }
        
        func close() {
            optionsPopup.close()
        }
        
        func match(_ lookFor: String) -> String? {
            let originalFrame = optionsPopup.frame
            let optionFields = self.optionFields
            var shortestPrefixMatch: String?
            var greatestMatchedIndex = -1
            for i in 0..<optionFields.count {
                let item = optionFields[i]
                let matched = SubsequenceMatcher.matches(lookFor: lookFor, inString: item.stringValue)
                if matched.isEmpty && (!lookFor.isEmpty) {
                    if i < AutoCompletingField.PINNED_OPTIONS_COUNT {
                        item.setMatches([])
                    } else {
                        item.isHidden = true
                    }
                } else {
                    let itemValue = item.stringValue
                    if itemValue.starts(with: lookFor) {
                        let useItemValueAsShortestPrefixMatch: Bool
                        if let existing = shortestPrefixMatch {
                            useItemValueAsShortestPrefixMatch = itemValue.count < existing.count
                        } else {
                            useItemValueAsShortestPrefixMatch = true
                        }
                        if useItemValueAsShortestPrefixMatch {
                            shortestPrefixMatch = itemValue
                        }
                    }
                    greatestMatchedIndex = max(greatestMatchedIndex, i)
                    item.isHidden = false
                    item.setMatches(matched)
                }
            }
            let showMatchedSectionSeparators = greatestMatchedIndex >= AutoCompletingField.PINNED_OPTIONS_COUNT
            matchedSectionSeparators.forEach { $0.isHidden = !showMatchedSectionSeparators }
            optionsPopup.setContentSize(mainStack.fittingSize)
            let newFrame = optionsPopup.frame
            optionsPopup.setFrameOrigin(originalFrame.offsetBy(dx: 0, dy: originalFrame.height - newFrame.height).origin)
            return shortestPrefixMatch
        }
        
        func show(minWidth: CGFloat, matching lookFor: String, atTopLeft: CGPoint) {
            guard !windowIsVisible else {
                return
            }
            setWidth(minWidth)
            var popupOrigin = atTopLeft
            popupOrigin.y -= (optionsPopup.frame.height + 2)
            optionsPopup.setFrameOrigin(popupOrigin)
            _ = match(lookFor)
            optionsPopup.display()
            optionsPopup.setIsVisible(true)
            
            let eventMask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
            activeEventMonitors.append(
                NSEvent.addLocalMonitorForEvents(matching: eventMask.union(.leftMouseUp)) {event in
                    return self.trackClick(event: event) ? event : nil
                })
            activeEventMonitors.append(
                NSEvent.addGlobalMonitorForEvents(matching: eventMask) {event in
                    _ = self.trackClick(event: event)
                })
        }
        
        func windowWillClose(_ notification: Notification) {
            activeEventMonitors.compactMap{$0}.forEach { NSEvent.removeMonitor($0) }
            activeEventMonitors.removeAll()
        }
        
        private func addGroupingLabel(text: String, under topAnchor: NSLayoutAnchor<NSLayoutYAxisAnchor>) -> NSView {
            let label = NSTextField(labelWithString: "")
            label.useAutoLayout()
            mainStack.addSubview(label)
            label.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
            label.textColor = NSColor.systemGray
            label.topAnchor.constraint(equalTo: topAnchor).isActive = true
            label.trailingAnchor.constraint(equalTo: mainStack.trailingAnchor, constant: -4).isActive = true
            
            let attributedValue = NSMutableAttributedString(string: text)
            attributedValue.applyFontTraits(.italicFontMask, range: attributedValue.string.fullNsRange())
            label.attributedStringValue = attributedValue
            return label
        }
        
        private func trackClick(event: NSEvent) -> Bool {
            if let eventWindow = event.window, eventWindow == optionsPopup {
                // If the event is a mouse event within the popup, then it's either a mouseup to finish a click
                // (including a long click, and even including one that's actually a drag under the hood) or it's
                // an event to start the click. If we start the click, ignore the event. If it's the end of the
                // click, we'll handle the select.
                if event.type != .leftMouseUp {
                    return false
                }
                // We can't just let the Option handle this. If the user holds down on one element and then
                // "drags" to another, the mouseup belongs to the first element; we really want it to belong
                // to where the cursor ended up. So, we'll get the location and find the view there, and then
                // walk up the superview chain until we get to an Option (whose stringValue we then get) or
                // see that there's nothing there
                let locationInSuperview = mainStack.superview!.convert(event.locationInWindow, from: nil)
                if let hitItem = mainStack.hitTest(locationInSuperview) {
                    var viewSearch: NSView? = hitItem
                    while viewSearch != nil {
                        if let option = viewSearch as? Option {
                            parent.stringValue = option.stringValue
                            if let editor = parent.currentEditor() {
                                editor.insertNewline(nil)
                            } else {
                                NSLog("Couldn't find editor")
                            }
                            break
                        }
                        viewSearch = viewSearch?.superview
                    }
                }
                close()
                return false
            }

            var shouldClose = true // Most clicks close the popups; the only exception is clicking in the text field
            var continueProcessingEvent = true // See below for the one exception.
            let closeButton = parent.pulldownButton!
            if let eventWindow = event.window, eventWindow == closeButton.window {
                // If the click was on the button that opens this popup, we want to suppress the event. Otherwise,
                // the button will just open the popup back up.
                if closeButton.contains(pointInWindowCoordinates: event.locationInWindow) {
                    parent.window?.makeFirstResponder(nil)
                    continueProcessingEvent = false
                } else if parent.contains(pointInWindowCoordinates: event.locationInWindow) {
                    shouldClose = false
                }
            }
            if shouldClose {
                close()
            }
            return continueProcessingEvent
        }
        
        class Option: NSView {
            static let paddingH: CGFloat = 4.0
            static let paddingV: CGFloat = 2.0
            private var label: NSTextField!
            private var highlightOverlay: NSVisualEffectView!
            
            override init(frame frameRect: NSRect) {
                super.init(frame: frameRect)
                commonInit()
            }
            
            required init?(coder: NSCoder) {
                super.init(coder: coder)
                commonInit()
            }
            
            private func commonInit() {
                highlightOverlay = NSVisualEffectView()
                highlightOverlay.useAutoLayout()
                highlightOverlay.state = .active
                highlightOverlay.material = .selection
                highlightOverlay.isEmphasized = true
                highlightOverlay.blendingMode = .behindWindow
                highlightOverlay.isHidden = true
                addSubview(highlightOverlay)
                highlightOverlay.anchorAllSides(to: self)
                
                let labelPadding = NSView()
                addSubview(labelPadding)
                labelPadding.anchorAllSides(to: self)
                
                label = NSTextField(labelWithString: "")
                label.useAutoLayout()
                labelPadding.addSubview(label)
                labelPadding.leadingAnchor.constraint(equalTo: label.leadingAnchor, constant: -Option.paddingH).isActive = true
                labelPadding.trailingAnchor.constraint(equalTo: label.trailingAnchor, constant: Option.paddingH).isActive = true
                labelPadding.topAnchor.constraint(equalTo: label.topAnchor, constant: -Option.paddingV).isActive = true
                labelPadding.bottomAnchor.constraint(equalTo: label.bottomAnchor, constant: Option.paddingV).isActive = true
                
                let pulldownButtonTracker = NSTrackingArea(
                    rect: frame,
                    options: [.inVisibleRect, .mouseEnteredAndExited, .activeAlways, .enabledDuringMouseDrag],
                    owner: self)
                addTrackingArea(pulldownButtonTracker)
            }
            
            var stringValue: String {
                get {
                    return label.stringValue
                }
                set(value) {
                    label.stringValue = value
                }
            }
            
            func setMatches(_ matched: [NSRange]) {
                let attributedLabel = NSMutableAttributedString(string: stringValue)
                matched.forEach {range in
                    attributedLabel.addAttributes(
                        [
                            .foregroundColor: NSColor.selectedTextColor,
                            .backgroundColor: NSColor.selectedTextBackgroundColor,
                            .underlineColor: NSColor.findHighlightColor,
                            .underlineStyle: NSUnderlineStyle.single.rawValue,
                        ],
                        range: range)
                }
                label.attributedStringValue = attributedLabel
            }
            
            override func mouseEntered(with event: NSEvent) {
                highlightOverlay.isHidden = false
            }
            
            override func mouseExited(with event: NSEvent) {
                highlightOverlay.isHidden = true
            }
        }
    }
    
    private class NoKeyButton: NSButton {
        override var canBecomeKeyView: Bool {
            return false
        }
    }
    
    /// An NSTextFieldCell with a smaller frame, to accommodate the popup button.
    private class ShrunkenTextFieldCell: NSTextFieldCell {
        
        fileprivate var widthAdjustment: () -> CGFloat = { 0 }
        
        override func drawingRect(forBounds rect: NSRect) -> NSRect {
            let fromSuper = super.drawingRect(forBounds: rect)
            return NSRect(x: fromSuper.minX, y: fromSuper.minY, width: fromSuper.width - widthAdjustment(), height: fromSuper.height)
        }
    }
}
