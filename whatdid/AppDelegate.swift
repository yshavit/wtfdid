// whatdid?

import Cocoa
import HotKey

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {
    public static let instance = NSApplication.shared.delegate as! AppDelegate
    public static let DEBUG_DATE_FORMATTER = ISO8601DateFormatter()

    public let model = Model()
    @IBOutlet weak var mainMenu: MainMenu!
    let focusHotKey = HotKey(key: .x, modifiers: [.command, .shift])
    private var deactivationHooks : Atomic<[() -> Void]> = Atomic(wrappedValue: [])
    
    func onDeactivation(_ block: @escaping () -> Void) {
        deactivationHooks.modifyInPlace {arr in
            arr.append(block)
        }
    }
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        #if UI_TEST
        if CommandLine.arguments.compactMap({DebugMode(fromStringIfWithPrefix: $0)}).contains(.buttonWithClosure) {
            print("Found debug mode")
        }
        #endif
        
        NSLog("Starting whatdid with build %@", Version.pretty)
        AppDelegate.DEBUG_DATE_FORMATTER.timeZone = TimeZone.autoupdatingCurrent
        // Our Info.plist starts us off as background. Now that we're started, become an accessory app.
        // This approach lets us start the app deactivated.
        NSApp.setActivationPolicy(.accessory)
        focusHotKey.keyDownHandler = { self.mainMenu.focus() }
        mainMenu.schedulePopup()
        scheduleEndOfDaySummary()
    }
    
    func scheduleEndOfDaySummary() {
        let plusOrMinus : TimeInterval = 30
        let scheduleEndOfDay = TimeUtil.dateForTime(.next, hh: 18, mm: 30).addingTimeInterval(-plusOrMinus)
        let timer = Timer(fire: scheduleEndOfDay, interval: 0, repeats: false, block: {_ in
            self.mainMenu.show(.dailyEnd)
            self.scheduleEndOfDaySummary()
        })
        timer.tolerance = plusOrMinus * 2
        NSLog("Scheduling summary at %@, +/- %.0fs", scheduleEndOfDay.debugDescription, plusOrMinus)
        RunLoop.current.add(timer, forMode: .default)
    }
    
    func applicationDidResignActive(_ notification: Notification) {
        let oldHooks = deactivationHooks.getAndSet([])
        oldHooks.forEach {hook in
            hook()
        }
    }
    
    func snooze(until date: Date) {
        self.mainMenu.snooze(until: date)
    }
    
    static func keyComboString(keyEquivalent: String, keyEquivalentMask: NSEvent.ModifierFlags) -> String {
        var keyAdjusted = keyEquivalent
        var maskAdjusted = keyEquivalentMask
        if keyEquivalent.count == 1, let firstKey = keyEquivalent.first {
            keyAdjusted = keyAdjusted.uppercased()
            if firstKey.isUppercase {
                maskAdjusted = NSEvent.ModifierFlags(arrayLiteral: keyEquivalentMask)
                maskAdjusted.insert(.shift)
            }
        }
        return "\(maskAdjusted)\(keyAdjusted)"
    }
}
