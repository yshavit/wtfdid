// whatdid?

import Cocoa

class PtnViewController: NSViewController {
    private static let TIME_UNTIL_NEW_SESSION_PROMPT = TimeInterval(6 * 60 * 60)
    @IBOutlet var topStack: NSStackView!
    
    @IBOutlet var headerText: NSTextField!
    
    @IBOutlet weak var prefsButton: NSButton!
    @IBOutlet weak var projectField: AutoCompletingField!
    @IBOutlet weak var taskField: AutoCompletingField!
    @IBOutlet weak var noteField: NSTextField!
    @IBOutlet weak var skipButton: NSButton!
    
    @IBOutlet weak var snoozeButton: NSButton!
    private var snoozeUntil : Date?
    @IBOutlet weak var snoozeExtraOptions: NSPopUpButton!
    private var snoozeOptionsUpdateSpinner: NSProgressIndicator?
    
    private var optionIsPressed = false
    
    var closeAction: () -> Void = {}
    var forceReschedule: () -> Void = {}
    
    var scheduler: Scheduler = DefaultScheduler.instance
    
    override func viewDidLoad() {
        super.viewDidLoad()
        projectField.textField.placeholderString = "project"
        taskField.textField.placeholderString = "task"
        for field in [projectField.textField, taskField.textField, noteField] {
            if let plainString = field?.placeholderString {
                field?.placeholderAttributedString = NSAttributedString(
                    string: plainString,
                    attributes: [.foregroundColor: NSColor.secondarySelectedControlColor])
            }
        }
        projectField.optionsLookupOnFocus = {
            AppDelegate.instance.model.listProjects()
        }
        taskField.optionsLookupOnFocus = {
            AppDelegate.instance.model.listTasks(project: self.projectField.textField.stringValue)
        }
        projectField.onTextChange = {
            self.taskField.textField.stringValue = ""
        }
        projectField.action = self.projectOrTaskAction
        taskField.action = self.projectOrTaskAction
        
        headerText.placeholderString = headerText.stringValue
        
        #if UI_TEST
        addJsonFlatEntryField()
        #endif
    }
    
    func reset() {
        noteField.stringValue = ""
        if projectField.textField.stringValue.isEmpty {
            taskField.textField.stringValue = ""
        }
    }
    
    override func viewDidAppear() {
        super.viewDidAppear()
        
        projectField.nextKeyView = taskField
        taskField.nextKeyView = noteField
        noteField.nextKeyView = projectField
        
        if timeInterval(since: AppDelegate.instance.model.lastEntryDate) > PtnViewController.TIME_UNTIL_NEW_SESSION_PROMPT {
            showNewSessionPrompt()
        } else {
            scheduler.schedule("new session prompt", after: PtnViewController.TIME_UNTIL_NEW_SESSION_PROMPT, showNewSessionPrompt)
        }

        func scheduleUpdateHeaderText() {
            scheduler.schedule("per-minute update header", after: 60) {
                self.updateHeaderText()
                scheduleUpdateHeaderText()
            }
        }
        scheduleUpdateHeaderText()
        showTutorial()
    }
    
    private func timeInterval(since date: Date) -> TimeInterval {
        return scheduler.now.timeIntervalSince(date)
    }
    
    override func viewWillAppear() {
        super.viewWillAppear()
        noteField.stringValue = ""
        setUpSnoozeButton()
        updateHeaderText()
        grabFocus()
    }
    
    private func setUpSnoozeButton(untilTomorrowSettings: (hhMm: HoursAndMinutes, includeWeekends: Bool)? = nil) {
        if let activeSpinner = snoozeOptionsUpdateSpinner {
            activeSpinner.removeFromSuperview()
            snoozeOptionsUpdateSpinner = nil
        }
        snoozeButton.isEnabled = true
        if let alreadySnoozedUntil = AppDelegate.instance.snoozedUntil {
            snoozeButton.title = "Snoozing until \(TimeUtil.formatSuccinctly(date: alreadySnoozedUntil))..."
            snoozeExtraOptions.isEnabled = false
            scheduler.schedule("Snooze options refresh", at: alreadySnoozedUntil, updateSnoozeButton)
        } else {
            // Set up the snooze button. We'll have 4 options at half-hour increments, starting 10 minutes from now.
            // The 10 minutes is so that if it's currently 2:29:59, you won't be annoyed with a "snooze until 2:30" button.
            let bufferMinutes = 10
            let snoozeIntervalMinutes = 30.0
            
            let now = scheduler.now
            var snoozeUntil = now.addingTimeInterval(TimeInterval(bufferMinutes * 60))
            // Round it up (always up) to the nearest half-hour
            let incrementInterval = Double(snoozeIntervalMinutes * 60.0)
            snoozeUntil = Date(timeIntervalSince1970: (snoozeUntil.timeIntervalSince1970 / incrementInterval).rounded(.up) * incrementInterval)

            snoozeButton.title = "Snooze until \(TimeUtil.formatSuccinctly(date: snoozeUntil))   " // extra space for the pulldown option
            self.snoozeUntil = Date(timeIntervalSince1970: snoozeUntil.timeIntervalSince1970)
            let refreshOptionsAt = snoozeUntil.addingTimeInterval(-300)
            var latestDate = snoozeUntil
            snoozeExtraOptions.isEnabled = true
            for menuItem in snoozeExtraOptions.itemArray[1...] {
                if menuItem.isSeparatorItem {
                    break
                }
                snoozeUntil.addTimeInterval(incrementInterval)
                menuItem.title = TimeUtil.formatSuccinctly(date: snoozeUntil)
                latestDate = Date(timeIntervalSince1970: snoozeUntil.timeIntervalSince1970)
                menuItem.representedObject = latestDate
            }
            let nextSessionHhMm = untilTomorrowSettings?.hhMm ?? Prefs.dayStartTime
            let nextSessionWeekends = untilTomorrowSettings?.includeWeekends ?? Prefs.daysIncludeWeekends
            let nextSessionDate = nextSessionHhMm.map {hh, mm in
                TimeUtil.dateForTime(.next, hh: hh, mm: mm, excludeWeekends: !nextSessionWeekends, assumingNow: latestDate)}
            if let nextSessionItem = snoozeExtraOptions.lastItem {
                nextSessionItem.title = TimeUtil.formatSuccinctly(date: nextSessionDate)
                nextSessionItem.representedObject = nextSessionDate
            }
            
            scheduler.schedule("Snooze options refresh", at: refreshOptionsAt, updateSnoozeButton)
        }
        
        #if UI_TEST
        populateJsonFlatEntryField()
        #endif
    }
    
    private func updateSnoozeButton() {
        if let snoozeParent = snoozeButton.superview {
            // Disable the snooze button, and set a spinner
            snoozeButton.isEnabled = false
            snoozeExtraOptions.isEnabled = false
            if snoozeOptionsUpdateSpinner == nil {
                let newSpinner = NSProgressIndicator()
                snoozeOptionsUpdateSpinner = newSpinner
                newSpinner.useAutoLayout()
                snoozeParent.addSubview(newSpinner)
                newSpinner.startAnimation(self)
                newSpinner.isIndeterminate = true
                newSpinner.style = .spinning
                newSpinner.centerYAnchor.constraint(equalTo: snoozeButton.centerYAnchor).isActive = true
                newSpinner.centerXAnchor.constraint(equalTo: snoozeButton.centerXAnchor).isActive = true
                newSpinner.heightAnchor.constraint(equalTo: snoozeButton.heightAnchor).isActive = true
            }
            // Wait a second, and then update the options and set a new spinner
            scheduler.schedule("Set the new snooze options", after: 1) {
                self.setUpSnoozeButton()
            }
        }
    }
    
    private func updateHeaderText() {
        let lastEntryDate = AppDelegate.instance.model.lastEntryDate
        headerText.stringValue = headerText.placeholderString!.replacingBracketedPlaceholders(with: [
            "TIME": TimeUtil.formatSuccinctly(date: lastEntryDate),
            "DURATION": TimeUtil.daysHoursMinutes(for: timeInterval(since: lastEntryDate))
        ])
    }
    
    @IBAction private func snoozeButtonPressed(_ sender: NSControl) {
        if let _ = AppDelegate.instance.snoozedUntil {
            let unsnoozePopover = NSPopover()
            unsnoozePopover.behavior = .transient
            
            let unsnoozeViewController = NSViewController()
            let button = ButtonWithClosure(label: "Unsnooze") {_ in
                AppDelegate.instance.unSnooze()
                self.setUpSnoozeButton()
                unsnoozePopover.close()
            }
            button.font = snoozeButton.font
            button.focusRingType = .none
            button.bezelStyle = .roundRect
            button.bezelColor = NSColor.controlAccentColor
            button.contentTintColor = NSColor.controlAccentColor
            
            unsnoozeViewController.view = button
            let buttonSize = button.intrinsicContentSize
            unsnoozePopover.contentSize = NSSize(width: buttonSize.width * 1.4, height: buttonSize.height * 1.5)
            
            unsnoozePopover.contentViewController = unsnoozeViewController
            unsnoozePopover.show(relativeTo: snoozeButton.bounds, of: snoozeButton, preferredEdge: .minY)
        } else {
            snooze(until: snoozeUntil)
        }
    }
    
    @IBAction func snoozeExtraOptionsSelected(_ sender: NSPopUpButton) {
        snooze(until: sender.selectedItem?.representedObject)
    }
    
    private func snooze(until: Any?) {
        if let date = until as? Date {
            AppDelegate.instance.snooze(until: date)
        } else {
            NSLog("error: date not set up (was \(until ?? "nil"))")
        }
    }
    
    @IBAction func preferenceButtonPressed(_ sender: NSButton) {
        if let viewWindow = view.window {
            let prefsWindow = NSWindow(contentRect: viewWindow.frame, styleMask: [.titled], backing: .buffered, defer: true)
            prefsWindow.backgroundColor = NSColor.windowBackgroundColor
            
            let prefsViewController = PrefsViewController(nibName: "PrefsViewController", bundle: nil)
            prefsViewController.setSize(width: viewWindow.frame.width, minHeight: viewWindow.frame.height)
            prefsViewController.ptnScheduleChanged = forceReschedule
            prefsWindow.contentViewController = prefsViewController
            viewWindow.beginSheet(prefsWindow, completionHandler: {reason in
                if reason == .stop {
                    NSApp.terminate(self)
                }
                self.setUpSnoozeButton(untilTomorrowSettings: prefsViewController.snoozeUntilTomorrowInfo)
            })
        }
    }
    
    func grabFocus() {
        if (view.window?.sheets ?? []).isEmpty {
            grabFocusEvenIfHasSheet()
        }
    }
    
    private func grabFocusEvenIfHasSheet() {
        perform(#selector(grabFocusNow), with: nil, afterDelay: TimeInterval.zero, inModes: [RunLoop.Mode.common])
    }
    
    @objc private func grabFocusNow() {
        var firstResponder = noteField
        if projectField.textField.stringValue.isEmpty {
            firstResponder = projectField.textField
        } else if taskField.textField.stringValue.isEmpty {
            firstResponder = taskField.textField
        }
        if firstResponder != nil {
            view.window?.makeFirstResponder(firstResponder)
        }
    }
    
    func projectOrTaskAction(_ sender: AutoCompletingField) {
        if let nextView = sender.nextValidKeyView {
            view.window?.makeFirstResponder(nextView)
        }
    }
    
    @IBAction func notesFieldAction(_ sender: NSTextField) {
        AppDelegate.instance.model.addEntryNow(
            project: projectField.textField.stringValue,
            task: taskField.textField.stringValue,
            notes: noteField.stringValue,
            callback: {
                self.forceReschedule()
                self.closeAction()
            }
        )
    }
    
    @IBAction func skipButtonPressed(_ sender: Any) {
        AppDelegate.instance.model.setLastEntryDateToNow()
        closeAction()
    }
    
    override func viewWillDisappear() {
        if let window = view.window {
            for sheet in window.sheets {
                window.endSheet(sheet, returnCode: .abort)
            }
        }
        super.viewWillDisappear()
    }
    
    private func showNewSessionPrompt() {
        if let window = view.window {
            let sheet = NSWindow(contentRect: window.contentView!.frame, styleMask: [], backing: .buffered, defer: true)
            let mainStack = NSStackView()
            mainStack.orientation = .vertical
            mainStack.useAutoLayout()
            mainStack.edgeInsets = NSEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
            sheet.contentView = mainStack
            
            let headerLabel = NSTextField(labelWithString: "It's been a while since you last checked in.")
            headerLabel.font = NSFont.boldSystemFont(ofSize: NSFont.labelFontSize * 1.25)
            mainStack.addArrangedSubview(headerLabel)
            
            let optionsStack = NSStackView()
            optionsStack.useAutoLayout()
            mainStack.addArrangedSubview(optionsStack)
            optionsStack.orientation = .horizontal
            optionsStack.widthAnchor.constraint(equalTo: mainStack.widthAnchor).isActive = true
            optionsStack.addView(
                ButtonWithClosure(label: "Start new session") {_ in
                    window.endSheet(sheet, returnCode: .OK)
                },
                in: .center)
            optionsStack.addView(
                ButtonWithClosure(label: "Continue with current session") {_ in
                    window.endSheet(sheet, returnCode: .continue)
                },
            in: .center)
            
            window.makeFirstResponder(nil)
            window.beginSheet(sheet) {response in
                let startNewSession: Bool
                switch(response) {
                case .OK:
                    NSLog("Starting new session")
                    startNewSession = true
                case .continue:
                    NSLog("Continuing with existing session")
                    startNewSession = false
                case .abort:
                    NSLog("Aborting window (probably because user closed it via status menu item)")
                    startNewSession = false
                default:
                    NSLog("Unexpected response: \(response.rawValue). Will start new session session.")
                    startNewSession = false
                }
                if startNewSession {
                    AppDelegate.instance.model.setLastEntryDateToNow()
                    self.forceReschedule()
                    self.closeAction()
                } else {
                    self.grabFocusEvenIfHasSheet()
                }
            }
        }
    }
    
    private func showTutorial() {
        let tutorial = TutorialViewController(nibName: "TutorialViewController", bundle: nil)
        tutorial.add(
            .init(
                title: "\"Whatdid I do all day?!\"",
                text: [
                    "This window will pop up every so often to ask you what you've been up to.",
                    "At the end of the day, it'll aggregate all of the checkins and let you see all you've accomplished."
                ],
                pointingTo: view,
                atEdge: .minX),
            .init(
                title: "Projects",
                text: [
                    "Enter the project you've been working on.",
                    "A good general rule is that a project will take 1-2 months.",
                    "This is most useful when looking at reports over months or a year, to see what you accomplished at a high level.",
                    "This can also be a catch-all, like \"general office work\" or even \"break\"."
                ],
                pointingTo: projectField,
                atEdge: .minY),
            .init(
                title: "Tasks",
                text: [
                    "A typical task takes 1-5 days.",
                    "In daily or weekly views, you can use this to see what tasks took up each project's time.",
                    "For a project like \"general office work\" a task might be \"email\" or \"scheduling my day\"."
                ],
                pointingTo: taskField,
                atEdge: .minY),
            .init(
                title: "Notes",
                text: [
                    "You can optionally enter notes about your work on this task.",
                    "This is most useful when looking at a daily report, to see the progression of your day."
                ],
                pointingTo: noteField,
                atEdge: .minY),
            .init(
                title: "Snooze",
                text: [
                    "You can pause notifications for a while, or even until tomorrow.",
                    "While Whatdid is snoozing, its timer is still going. When you check in after the snooze, "
                        + "it'll include the snooze time.",
                    "This is a useful way to prevent interruptions during meetings."
                ],
                pointingTo: snoozeButton,
                atEdge: .minX),
            .init(
                title: "Settings",
                text: [
                    "Configure settings like popup frequency or keyboard shortcuts.",
                    "You can also use this to quit Whatdid.",
                    "There are also links to drop us feedback!"
                ],
                pointingTo: prefsButton,
                atEdge: .minY),
            .init(
                title: "Skip a session",
                text: [
                    "Sometimes you're off the clock!",
                    "Use this to tell Whatdid to just ignore the current session.",
                    "(Tip: Use this sparingly! For most breaks, create a project called \"break\" so you "
                        + "can keep track of how many breaks you take throughout the day.)"
                ],
                pointingTo: skipButton,
                atEdge: .minX),
            .init(
                title: "That's it", text: [
                    "I hope you like Whatdid!"
                ],
                pointingTo: view,
                atEdge: .minX)
        )
        tutorial.show()
    }
}
