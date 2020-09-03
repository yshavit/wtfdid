// whatdid?

import Cocoa

class MainMenu: NSWindowController, NSWindowDelegate, NSMenuDelegate {
    
    private let POPUP_INTERVAL_MINUTES = 10
    private let POPUP_INTERVAL_JITTER_MINUTES = 2
    
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    
    private var taskAdditionsPane : PtnViewController!
    private var windowContents = WindowContents.ptn
    private var opener : OpenCloseHelper<WindowContents>!
    private var cancelClose = false
    
    enum WindowContents: Int, Comparable {
        /// The Project/Task/Notes window
        case ptn
        /// The end-of-day report
        case dailyEnd
        
        static func < (lhs: MainMenu.WindowContents, rhs: MainMenu.WindowContents) -> Bool {
            return lhs.rawValue < rhs.rawValue
        }
    }
    
    func open(_ item: WindowContents, reason: OpenReason) {
        opener.open(item, reason: reason)
    }
    
    override func close() {
        cancelClose = false
        opener.didClose()
        if !cancelClose {
            super.close()
        }
    }

    override func awakeFromNib() {
        super.awakeFromNib()
        window?.level = .floating
        taskAdditionsPane = PtnViewController()
        taskAdditionsPane.closeAction = {
            DispatchQueue.main.async {
                self.close()
            }
        }
        window?.contentViewController = taskAdditionsPane
        window?.delegate = self
        window?.standardWindowButton(.closeButton)?.isHidden = true
        window?.isMovable = false
        window?.standardWindowButton(.closeButton)?.isHidden = true
        window?.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window?.standardWindowButton(.zoomButton)?.isHidden = true
        
        statusItem.button?.title = "✐"
        statusItem.button?.target = self
        statusItem.button?.action = #selector(handleStatusItemPress)
        
        opener = OpenCloseHelper<WindowContents>(
            onOpen: {contents, reason in
                NSLog("MainMenu handling \(reason) open request for \(contents)")
                self.open(contents)
                if reason == .manual {
                    self.focus()
                }
            },
            onSchedule: self.schedule)
    }
    
    @objc private func handleStatusItemPress() {
        if window?.isVisible ?? false {
            close()
        } else {
            let showWhat = NSEvent.modifierFlags.contains(.option)
                ? WindowContents.dailyEnd
                : WindowContents.ptn
            opener.open(showWhat, reason: .manual)
        }
    }
    
    private func open(_ contents: WindowContents) {
        switch (contents) {
        case .dailyEnd:
            window?.contentViewController = DayEndReportController()
            window?.title = "Here's what you've been doing"
        case .ptn:
            window?.contentViewController = taskAdditionsPane
            window?.title = "What are you working on?"
        }
        
        window!.setContentSize(window!.contentViewController!.view.fittingSize)
        if let mainFrame = NSScreen.main?.visibleFrame, let button = statusItem.button {
            let buttonBoundsAbsolute = button.window?.convertToScreen(button.bounds)
            var pos = NSPoint(
                x: buttonBoundsAbsolute?.minX ?? .zero,
                y: mainFrame.origin.y + mainFrame.height)
            if let myWindow = window {
                if let screen = myWindow.screen {
                    let tooFarLeftBy = (pos.x + myWindow.frame.width) - screen.frame.width
                    if tooFarLeftBy > 0 {
                        pos.x -= tooFarLeftBy
                    }
                }
                window?.setFrameTopLeftPoint(pos)
            }
        }
        if window?.isVisible ?? false {
            cancelClose = true
        } else {
            showWindow(self)
        }
        RunLoop.current.perform {
            self.statusItem.button?.isHighlighted = true
        }
        if let theWindow = window, let theScreen = theWindow.screen {
            NSLog("Opened \(contents) window at \(theWindow.frame) within screen \(theScreen.frame)")
        } else {
            NSLog("No window or screen. Window \(window == nil ? "is" : "is not") nil, and screen \(window?.screen == nil ? "is" : "is not") nil")
        }
    }
    
    func focus() {
        if !NSApp.isActive {
            NSApp.activate(ignoringOtherApps: true)
        }
        if !(window?.isVisible ?? false) {
            open(.ptn)
        }
        window?.makeKeyAndOrderFront(self)
        if window?.contentView == taskAdditionsPane.view {
            taskAdditionsPane.grabFocus()
        }
    }
    
    func windowWillClose(_ notification: Notification) {
        NSApp.hide(self)
        statusItem.button?.isHighlighted = false
    }

    func schedule(_ contents: WindowContents) {
        switch contents {
        case .ptn:
            let jitterMinutes = Int.random(in: -POPUP_INTERVAL_JITTER_MINUTES...POPUP_INTERVAL_JITTER_MINUTES)
            let minutes = Double(POPUP_INTERVAL_MINUTES + jitterMinutes)
            NSLog("Scheduling a popup in %.0f minutes", minutes)
            DefaultScheduler.instance.schedule(after: minutes * 60.0) {
                self.opener.open(.ptn, reason: .scheduled)
            }
        case .dailyEnd:
            AppDelegate.instance.scheduleEndOfDaySummary()
        }
    }
    
    func snooze(until date: Date) {
        NSLog("Snoozing until %@", AppDelegate.DEBUG_DATE_FORMATTER.string(from: date))
        opener.snooze()
        close()
        DefaultScheduler.instance.schedule(after: date.timeIntervalSinceWhatdidNow, self.opener.unSnooze)
    }
}
