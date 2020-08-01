// whatdid?

import Cocoa

class Model {
    
    private static let BUILTIN_PROJECT = "\0__built_in"
    private static let BREAK_TASK = "break"
    private static let BREAK_TASK_NOTES = ""
    private static let NO_BUILTINS = NSPredicate(format: "project != %@", BUILTIN_PROJECT)
    
    @Atomic private var lastEntryDate : Date
    
    init() {
        lastEntryDate = Date()
    }
    
    private lazy var container: NSPersistentContainer = {
        let localContainer = NSPersistentContainer(name: "Model")
        localContainer.loadPersistentStores { description, error in
            if let error = error {
                fatalError("Unable to load persistent stores: \(error)")
            }
        }
        localContainer.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        return localContainer
    }()
    
    func setLastEntryDateToNow() {
        lastEntryDate = Date()
    }
    
    func listProjects() -> [Project] {
        var result : [Project]!
        container.viewContext.performAndWait {
            let request = NSFetchRequest<Project>(entityName: "Project")
            do {
                request.predicate = Model.NO_BUILTINS
                result = try request.execute()
            } catch {
                NSLog("couldn't load projects: %@", error as NSError)
                result = []
            }
        }
        return result
    }
    
    func listProjects(prefix: String) -> [String] {
        var results : [String]!
        container.viewContext.performAndWait {
            let request = NSFetchRequest<Project>(entityName: "Project")
            
            let projects : [Project]
            do {
                request.sortDescriptors = [
                    .init(key: "lastUsed", ascending: false),
                    .init(key: "project", ascending: true)
                ]
                request.predicate = prefix.isEmpty
                    ? Model.NO_BUILTINS
                    : NSPredicate(format: "project BEGINSWITH %@", prefix)
                request.fetchLimit = 10
                projects = try request.execute()
            } catch {
                NSLog("couldn't load projects: %@", error as NSError)
                projects = []
            }
            results = projects.map({$0.project})
            
        }
        return results
    }
    
    func listTasks(project: String, prefix: String) -> [String] {
        var results : [String]!
        container.viewContext.performAndWait {
            let request = NSFetchRequest<Task>(entityName: "Task")
            
            let tasks : [Task]
            do {
                request.sortDescriptors = [
                    .init(key: "lastUsed", ascending: false),
                    .init(key: "task", ascending: true)
                ]
                var predicate = NSPredicate(format: "project.project = %@", project)
                if !prefix.isEmpty {
                    predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                        predicate,
                        NSPredicate(format: "task BEGINSWITH %@", prefix)])
                }
                request.predicate = predicate
                request.fetchLimit = 10
                tasks = try request.execute()
            } catch {
                NSLog("couldn't load projects: %@", error as NSError)
                tasks = []
            }
            results = tasks.map({$0.task})
            
        }
        return results
    }
    
    func listEntries(since: Date) -> [FlatEntry] {
        var results : [FlatEntry] = []
        container.viewContext.performAndWait {
            do {
                let request = NSFetchRequest<Entry>(entityName: "Entry")
                request.predicate = NSPredicate(format: "timeApproximatelyStarted >= %@", since as NSDate)
                let entries = try request.execute()
                results = entries.map({entry in
                    FlatEntry(
                        from: entry.timeApproximatelyStarted,
                        to: entry.timeEntered,
                        project: entry.task.project.project,
                        task: entry.task.task,
                        notes: entry.notes
                    )
                })
            } catch {
                NSLog("couldn't load projects: %@", error as NSError)
                results = []
            }
        }
        return results
    }
    
    func printAll() {
        container.viewContext.performAndWait {
            do {
                let projectsRequest = NSFetchRequest<Project>(entityName: "Project")
                let projects = try projectsRequest.execute()
                for project in projects {
                    print("\(project.project) (\(project.lastUsed))")
                    for task in project.tasks {
                        print("    \(task.task) (\(task.lastUsed))")
                        for entry in task.entries {
                            print("        \(entry.notes ?? "<no notes>"): from \(entry.timeApproximatelyStarted) to \(entry.timeEntered)")
                        }
                    }
                }
                print("")
            } catch {
                NSLog("couldn't list everything: %@", error as NSError)
            }
            
        }
    }
    
    func addBreakEntry(callback: @escaping () -> ()) {
        addEntryNow(project: Model.BUILTIN_PROJECT, task: Model.BREAK_TASK, notes: Model.BREAK_TASK_NOTES, callback: callback)
    }
    
    func addEntryNow(project: String, task: String, notes: String, callback: @escaping ()->()) {
        container.performBackgroundTask({context in
            let lastUpdate = self.lastEntryDate
            let now = Date()
            self.lastEntryDate = now
            context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
            
            let projectData = Project.init(context: context)
            projectData.project = project.trimmingCharacters(in: .whitespacesAndNewlines)
            projectData.lastUsed = lastUpdate
            
            let taskData = Task.init(context: context)
            taskData.project = projectData
            taskData.task = task.trimmingCharacters(in: .whitespacesAndNewlines)
            taskData.lastUsed = now
            
            let entry = Entry.init(context: context)
            entry.task = taskData
            entry.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
            entry.timeApproximatelyStarted = lastUpdate
            entry.timeEntered = now
            
            do {
                NSLog("Saving project(%@), task(%@), notes(%@)", project, task, notes)
                try context.save()
            } catch {
                NSLog("Error saving entry: %@", error as NSError)
            }
            callback()
        })
    }
    
    /// Given a list of FlatEntries, returns a nested map whose first level keys are project names, second level keys are task names
    /// within those projects, and leaf values are the FlatEntries ordered by time started (with earliest as the first element)
    static func group(entries: [FlatEntry]) -> [String: [String: [FlatEntry]]] {
        let byProject = MutableDict<String, MutableDict<String, MutableList<FlatEntry>>>()
        entries.forEach({entry in
            var byTask = byProject[entry.project]
            if byTask == nil {
                byTask = MutableDict()
                byProject[entry.project] = byTask
            }
            var entryList = byTask?[entry.task]
            if entryList == nil {
                entryList = MutableList()
                byTask![entry.task] = entryList
            }
            entryList?.append(entry)
        })
        return byProject.asDictionary(mapValuesTo: {byTask in
            byTask.asDictionary(mapValuesTo: {entries in
                entries.asList().sorted()
            })
        })
    }
    
    struct FlatEntry : Comparable {
        
        let from : Date
        let to : Date
        let project : String
        let task : String
        let notes : String?
        
        static func < (lhs: Model.FlatEntry, rhs: Model.FlatEntry) -> Bool {
            return lhs.project < rhs.project
                && lhs.task < rhs.task
                && isLessThan(lhs: lhs.notes, rhs: rhs.notes)
                && lhs.from < rhs.from
                && lhs.to < rhs.to
        }
        
        func durationSeconds() -> Double {
            return (to.timeIntervalSince1970 - from.timeIntervalSince1970)
        }
        
        static func totalSeconds(projects: [String: [String: [FlatEntry]]]) -> Double {
            return projects.values.map( { totalSeconds(tasksForProject: $0) }).reduce(0, +)
        }
        
        static func totalSeconds(tasksForProject: [String: [FlatEntry]]) -> Double {
            return totalSeconds(entriesForTask: tasksForProject.flatMap { $0.value })
        }
        
        static func totalSeconds(entriesForTask: [FlatEntry]) -> Double {
            return entriesForTask.map { $0.durationSeconds() }.reduce(0, +)
            
        }
        
        private static func isLessThan(lhs: String?, rhs: String?) -> Bool {
            if lhs == nil {
                return rhs != nil
            } else if rhs == nil {
                return false
            } else {
                return lhs! < rhs!
            }
        }
    }
}