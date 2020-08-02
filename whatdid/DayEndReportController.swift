// whatdid?

import Cocoa

class DayEndReportController: NSViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do view setup here.
    }
    /// I don't know how to programatically make a nice disclosure button, so I'll just let the xib do it for me :-)
    @IBOutlet var disclosurePrototype: ButtonWithClosure!
    // The serialized version of `disclosurePrototype`
    private static var disclosureArchive : Data!
    
    @IBOutlet weak var maxViewHeight: NSLayoutConstraint!
    @IBOutlet weak var projectsScroll: NSScrollView!
    @IBOutlet weak var projectsScrollHeight: NSLayoutConstraint!
    @IBOutlet weak var projectsContainer: NSStackView!
    
    @IBOutlet weak var entryStartDatePicker: NSDatePicker!
    
    override func awakeFromNib() {
        if #available(OSX 10.15.4, *) {
            entryStartDatePicker.presentsCalendarOverlay = true
        }
        do {
            DayEndReportController.disclosureArchive = try NSKeyedArchiver.archivedData(withRootObject: disclosurePrototype!, requiringSecureCoding: false)
            disclosurePrototype = nil // free it up
        } catch {
            NSLog("Couldn't archive disclosure button: %@", error as NSError)
        }
    }
    
    private static func createDisclosure(state: NSButton.StateValue)  -> ButtonWithClosure {
        do {
            // TODO eventually I should look at the xib xml and just figure out what it's doing
            let new = try NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(disclosureArchive)
            let button = new as! ButtonWithClosure
            button.state = state
            return button
        } catch {
            NSLog("error: %@", error as NSError) // TODO return default?
            fatalError("error: \(error)")
        }
    }
    
    override func viewWillAppear() {
        // Set the window's max height, using the golden ratio.
        if let screenHeight = view.window?.screen?.frame.height {
            maxViewHeight.constant = screenHeight * 0.61802903
            NSLog("set max height to %.1f (screen height is %.1f)", maxViewHeight.constant, screenHeight)
        }
        // Set up the date picker
        let now = Date()
        let defaultStartingTime = now.addingTimeInterval(-86400) // only used if we can't compute it correctly
        entryStartDatePicker.maxDate = now
        var thisMorning = Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: now) ?? defaultStartingTime
        if thisMorning > now {
            // This morning is tomorrow morning! Bump it back a day
            thisMorning = Calendar.current.date(byAdding: DateComponents(day: -1), to: thisMorning) ?? defaultStartingTime
        }
        entryStartDatePicker.dateValue = thisMorning
        updateEntries()
    }
    
    @IBAction func userChangedEntryStartDate(_ sender: Any) {
        animate(
            {
                projectsContainer.subviews.forEach {$0.removeFromSuperview()}
                let spinner = NSProgressIndicator()
                projectsContainer.addArrangedSubview(spinner)
                spinner.startAnimation(self)
                spinner.isIndeterminate = true
                spinner.style = .spinning
                spinner.leadingAnchor.constraint(equalTo: projectsContainer.leadingAnchor).isActive = true
                spinner.trailingAnchor.constraint(equalTo: projectsContainer.trailingAnchor).isActive = true
        },
            
            duration: 0.25,
            andThen: {
                self.animate({ self.updateEntries() })
            }
        )
    }
    
    private func updateEntries() {
        let since = entryStartDatePicker.dateValue
        NSLog("Updating entries since %@", since as NSDate)
        projectsContainer.subviews.forEach {$0.removeFromSuperview()}
        
        let projects = Model.GroupedProjects(from: AppDelegate.instance.model.listEntries(since: since))
        let allProjectsTotalTime = projects.totalTime
        projects.forEach {project in
            // The vstack group for the whole project
            let projectVStack = NSStackView()
            projectsContainer.addArrangedSubview(projectVStack)
            projectVStack.spacing = 2
            projectVStack.orientation = .vertical
            projectVStack.widthAnchor.constraint(equalTo: projectsContainer.widthAnchor, constant: -2).isActive = true
            projectVStack.leadingAnchor.constraint(equalTo: projectsContainer.leadingAnchor).isActive = true
            
            let projectHeader = ExpandableProgressBar(addTo: projectVStack, labeled: project.name, withDuration: project.totalTime, outOf: allProjectsTotalTime)
            
            // Tasks box
            let tasksBox = NSBox()
            projectVStack.addArrangedSubview(tasksBox)
            tasksBox.title = "Tasks for \(project.name)"
            tasksBox.titlePosition = .noTitle
            tasksBox.leadingAnchor.constraint(equalTo: projectVStack.leadingAnchor, constant: 3).isActive = true
            tasksBox.trailingAnchor.constraint(equalTo: projectVStack.trailingAnchor, constant: -3).isActive = true
            setUpDisclosureExpansion(disclosure: projectHeader.disclosure, details: tasksBox)
            
            let tasksStack = NSStackView()
            tasksStack.spacing = 0
            tasksStack.orientation = .vertical
            tasksBox.contentView = tasksStack
            
            let timeFormatter = DateFormatter()
            timeFormatter.locale = Locale(identifier: "en_US_POSIX")
            timeFormatter.dateFormat = "HH:mma"
            timeFormatter.timeZone = .autoupdatingCurrent
            timeFormatter.amSymbol = "am"
            timeFormatter.pmSymbol = "pm"
            var previousDetailsBottomAnchor : NSLayoutYAxisAnchor?
            project.forEach {task in
                let taskHeader = ExpandableProgressBar(addTo: tasksStack, labeled: task.name, withDuration: task.totalTime, outOf: allProjectsTotalTime)
                taskHeader.progressBar.leadingAnchor.constraint(equalTo: projectHeader.progressBar.leadingAnchor).isActive = true
                taskHeader.progressBar.trailingAnchor.constraint(equalTo: projectHeader.progressBar.trailingAnchor).isActive = true
                previousDetailsBottomAnchor?.constraint(equalTo: taskHeader.topView.topAnchor, constant: -5).isActive = true
                var details = ""
                task.forEach {entry in
                    details += timeFormatter.string(from: entry.from)
                    details += " - "
                    details += timeFormatter.string(from: entry.to)
                    details += ": "
                    details += entry.notes ?? "(no notes entered)"
                    details += "\n"
                }
                let taskDetailsView = NSTextField(labelWithString: details.trimmingCharacters(in: .newlines))
                tasksStack.addArrangedSubview(taskDetailsView)
                taskDetailsView.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
                taskDetailsView.leadingAnchor.constraint(equalTo: taskHeader.progressBar.leadingAnchor).isActive = true
                previousDetailsBottomAnchor = taskDetailsView.bottomAnchor
                setUpDisclosureExpansion(disclosure: taskHeader.disclosure, details: taskDetailsView)
            }
        }
    }
    
    private func animate(_ action: () -> Void, duration: Double = 0.5, andThen: (() -> Void)? = nil) {
        NSAnimationContext.runAnimationGroup(
            {context in
                context.duration = duration
                context.allowsImplicitAnimation = true
                action()
                self.projectsScrollHeight.constant = self.projectsContainer.fittingSize.height
                self.view.layoutSubtreeIfNeeded()
                let newFrame = self.view.frame
                self.view.window?.setContentSize(NSSize(width: newFrame.width, height: newFrame.height))
            },
            completionHandler: andThen
        )
    }
    
    private func setUpDisclosureExpansion(disclosure: ButtonWithClosure, details: NSView) {
        
        disclosure.onPress {button in
            self.animate({ details.isHidden = button.state == .off })
        }
        
        details.isHidden = disclosure.state == .off
        self.projectsScrollHeight.constant = self.projectsContainer.fittingSize.height
        self.view.layoutSubtreeIfNeeded()
    }
    
    struct ExpandableProgressBar {
        let topView: NSView
        let disclosure: ButtonWithClosure
        let progressBar: NSProgressIndicator
        
        init(addTo enclosing: NSStackView, labeled label: String, withDuration duration: TimeInterval, outOf: TimeInterval) {
            let projectLabel = NSTextField(labelWithString: label)
            enclosing.addArrangedSubview(projectLabel)
            projectLabel.leadingAnchor.constraint(equalTo: enclosing.leadingAnchor).isActive = true
            
            let headerHStack = NSStackView()
            enclosing.addArrangedSubview(headerHStack)
            headerHStack.spacing = 2
            headerHStack.orientation = .horizontal
            headerHStack.widthAnchor.constraint(equalTo: enclosing.widthAnchor).isActive = true
            headerHStack.leadingAnchor.constraint(equalTo: enclosing.leadingAnchor).isActive = true
            // disclosure button
            disclosure = createDisclosure(state: .off)
            headerHStack.addArrangedSubview(disclosure)
            disclosure.leadingAnchor.constraint(equalTo: headerHStack.leadingAnchor).isActive = true
            
            // progress bar
            progressBar = NSProgressIndicator()
            headerHStack.addArrangedSubview(progressBar)
            progressBar.isIndeterminate = false
            progressBar.minValue = 0
            progressBar.maxValue = outOf
            progressBar.doubleValue = duration
            progressBar.trailingAnchor.constraint(lessThanOrEqualTo: headerHStack.trailingAnchor).isActive = true
            
            topView = projectLabel
        }
    }
    
    private func getEntries() -> [Model.FlatEntry] {
        func d(_ hh: Int, _ mm: Int) -> Date {
            let dateFormatter = DateFormatter()
            dateFormatter.locale = Locale(identifier: "en_US_POSIX")
            dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss-4:00"
            return dateFormatter.date(from: String(format: "2020-07-31T%02d:%02d:00-4:00", hh, mm))!
        }
        var fakeEntries = [
            Model.FlatEntry(from: d(10, 00), to: d(10, 15), project: "Project1", task: "Task 1", notes: "entry 1"),
            Model.FlatEntry(from: d(10, 15), to: d(10, 30), project: "Project1", task: "Task 1", notes: "entry 2"),
            Model.FlatEntry(from: d(10, 30), to: d(10, 45), project: "Project1", task: "Task 2", notes: "entry 3"),
            Model.FlatEntry(from: d(10, 45), to: d(11, 00), project: "Project2", task: "Task 1", notes: "entry 4"),
            Model.FlatEntry(from: d(10, 45), to: d(10, 55), project: String(repeating: "long project ", count: 30), task: String(repeating: "long task", count: 20), notes: String(repeating: "long entry", count: 20)),
        ]
        (0..<10).forEach {hh in
            (0..<4).forEach {qh in // quarter hour
                fakeEntries.append(Model.FlatEntry(
                    from: d(12 + hh, qh * 15),
                    to: d(12 + hh, qh * 15 + 14),
                    project: "Marathon project",
                    task: "big task #\(qh)",
                    notes: "session \(hh)"))
            }
            
        }
        return fakeEntries.shuffled() // to make it interesting :)
    }
}
